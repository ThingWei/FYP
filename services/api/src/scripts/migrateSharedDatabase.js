// Explicit, one-way transfer into an EMPTY database. Never drops or rewrites data.
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BSON, MongoClient } from 'mongodb';
import dotenv from 'dotenv';

const apiRoot = fileURLToPath(new URL('../../', import.meta.url));
const maxDocuments = 100_000;
const maxBytes = 128 * 1024 * 1024;
const indexOptions = new Set(['name', 'unique', 'sparse', 'partialFilterExpression',
  'expireAfterSeconds', 'weights', 'default_language', 'language_override',
  'textIndexVersion', '2dsphereIndexVersion', 'collation', 'hidden']);

function fail(code) { throw Object.assign(new Error(code), { migrationCode: code }); }

export function portableIndex(index) {
  const result = { key: {} };
  for (const [field, direction] of Object.entries(index.key)) {
    if (field === '_fts') {
      for (const name of Object.keys(index.weights ?? {})) result.key[name] = 'text';
    } else if (field !== '_ftsx') result.key[field] = direction;
  }
  for (const [key, value] of Object.entries(index)) {
    // Index encoding versions are server-specific. Rebuild geospatial indexes
    // using the target's default encoding; fields/directions remain identical.
    if (key === '2dsphereIndexVersion') continue;
    if (indexOptions.has(key)) result[key] = structuredClone(value);
    else if (!['key', 'v', 'ns', 'background'].includes(key)) fail('unsupported_index_option');
  }
  if (result.collation) delete result.collation.version;
  // Collections with non-default options are refused by inventory(). Version 9
  // explicitly reports simple collation, whereas versions 7/8 may omit it.
  if (result.collation?.locale === 'simple') delete result.collation;
  return result;
}

// JSON comparison is order-independent for option objects; compound index keys retain order.
function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') return Object.fromEntries(
    Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, sorted(v)]));
  return value;
}
function indexSignature(index) {
  const portable = portableIndex(index);
  // Text index field order is normalized by MongoDB; its weights retain field identity.
  const key = Object.values(portable.key).includes('text')
    ? Object.entries(portable.key).sort(([a], [b]) => a.localeCompare(b))
    : Object.entries(portable.key);
  const { key: ignored, ...options } = portable;
  return JSON.stringify({ key, options: sorted(options) });
}

export function bsonDocuments(buffer) {
  const documents = [];
  for (let offset = 0; offset < buffer.length;) {
    if (offset + 4 > buffer.length) fail('invalid_snapshot');
    const length = buffer.readInt32LE(offset);
    if (length < 5 || offset + length > buffer.length) fail('invalid_snapshot');
    documents.push(BSON.deserialize(buffer.subarray(offset, offset + length),
      { promoteValues: false, promoteLongs: false }));
    offset += length;
  }
  return documents;
}
const hash = buffer => createHash('sha256').update(buffer).digest('hex');

export async function inventory(db) {
  const rows = await db.listCollections().toArray();
  const output = [];
  let documents = 0;
  for (const row of rows.sort((a, b) => a.name.localeCompare(b.name))) {
    if (!/^[A-Za-z0-9_]+$/.test(row.name) || row.type !== 'collection'
      || Object.keys(row.options ?? {}).length) fail('unsupported_collection');
    const count = await db.collection(row.name).countDocuments({});
    documents += count;
    if (documents > maxDocuments) fail('document_limit');
    const indexes = await db.collection(row.name).listIndexes().toArray();
    indexes.forEach(portableIndex);
    output.push({ name: row.name, count, indexes });
  }
  return output;
}

async function collectionBytes(db, name) {
  const buffers = [];
  let bytes = 0;
  for await (const raw of db.collection(name).find({}, { raw: true }).sort({ _id: 1 })) {
    if (!Buffer.isBuffer(raw)) fail('raw_bson_required');
    bytes += raw.length;
    if (bytes > maxBytes) fail('snapshot_size_limit');
    buffers.push(raw);
  }
  return Buffer.concat(buffers);
}

export async function assertEmpty(db) {
  if ((await db.listCollections({}, { nameOnly: true }).toArray()).length) fail('target_not_empty');
}

export async function snapshotDatabase(source, directory) {
  await mkdir(directory, { recursive: false }); // Refuse overwrite/reuse.
  const manifest = { version: 1, database: source.databaseName,
    createdAt: new Date().toISOString(), sourceVersion: (await source.admin().command({ buildInfo: 1 })).version,
    collections: [], bytes: 0, documents: 0 };
  for (const item of await inventory(source)) {
    const buffer = await collectionBytes(source, item.name);
    const count = bsonDocuments(buffer).length;
    if (count !== item.count) fail('source_changed');
    manifest.bytes += buffer.length;
    manifest.documents += count;
    if (manifest.bytes > maxBytes || manifest.documents > maxDocuments) fail('snapshot_size_limit');
    await writeFile(path.join(directory, `${item.name}.bson`), buffer, { flag: 'wx', mode: 0o600 });
    manifest.collections.push({ ...item, count, bytes: buffer.length, sha256: hash(buffer) });
  }
  await verifySnapshotSource(source, directory, manifest);
  await writeFile(path.join(directory, 'manifest.json'), JSON.stringify(manifest, null, 2), { flag: 'wx', mode: 0o600 });
  return manifest;
}

export async function verifySnapshotSource(source, directory, manifest) {
  const current = await inventory(source);
  if (current.length !== manifest.collections.length) fail('source_changed');
  for (const item of manifest.collections) {
    const now = current.find(row => row.name === item.name);
    const buffer = await readFile(path.join(directory, `${item.name}.bson`));
    if (!now || now.count !== item.count || hash(buffer) !== item.sha256
      || hash(await collectionBytes(source, item.name)) !== item.sha256
      || JSON.stringify(now.indexes.map(indexSignature).sort())
        !== JSON.stringify(item.indexes.map(indexSignature).sort())) fail('source_changed');
  }
}

export async function transferSnapshot(source, target, directory, manifest, { resume = false } = {}) {
  if (source.client === target.client && source.databaseName === target.databaseName) fail('same_database');
  if (manifest.version !== 1 || manifest.database !== source.databaseName
    || !Array.isArray(manifest.collections) || manifest.documents > maxDocuments || manifest.bytes > maxBytes
    || new Set(manifest.collections.map(item => item.name)).size !== manifest.collections.length
    || manifest.collections.some(item => !/^[A-Za-z0-9_]+$/.test(item.name)
      || !/^[a-f0-9]{64}$/.test(item.sha256))) fail('invalid_snapshot');
  if (!resume) await assertEmpty(target);
  await verifySnapshotSource(source, directory, manifest);
  const existing = resume ? await inventory(target) : [];
  // Resume only a verified prefix of THIS snapshot. Never merge, update, drop,
  // overwrite or guess how to reconcile a partly inserted collection.
  for (const row of existing) {
    const expected = manifest.collections.find(item => item.name === row.name);
    if (!expected || row.indexes.some(index => !expected.indexes.some(wanted =>
      indexSignature(index) === indexSignature(wanted)))) fail('resume_target_conflict');
    if (row.count && (row.count !== expected.count
      || hash(await collectionBytes(target, row.name)) !== expected.sha256)) fail('resume_target_conflict');
  }
  // This is a one-time, quiesced-source operation, not ongoing replication.
  const deferred = [];
  for (const item of manifest.collections) {
    const previous = existing.find(row => row.name === item.name);
    if (!previous) await target.createCollection(item.name);
    const collection = target.collection(item.name);
    for (const index of item.indexes.filter(index => index.name !== '_id_')) {
      if (index.expireAfterSeconds !== undefined) deferred.push({ name: item.name, index });
      else if (!previous?.indexes.some(found => indexSignature(found) === indexSignature(index))) {
        await collection.createIndexes([portableIndex(index)]);
      }
    }
    const buffer = await readFile(path.join(directory, `${item.name}.bson`));
    if (hash(buffer) !== item.sha256) fail('snapshot_changed');
    const documents = bsonDocuments(buffer);
    for (let offset = previous?.count ? documents.length : 0; offset < documents.length; offset += 100) {
      await collection.insertMany(documents.slice(offset, offset + 100),
        { ordered: true, writeConcern: { w: 'majority' } });
    }
    if (await collection.countDocuments({}) !== item.count
      || hash(await collectionBytes(target, item.name)) !== item.sha256) fail('verification_failed');
  }
  // Recheck ALL source/target documents before enabling normal TTL expiration.
  await verifySnapshotSource(source, directory, manifest);
  for (const item of manifest.collections) {
    if (hash(await collectionBytes(target, item.name)) !== item.sha256) fail('verification_failed');
  }
  for (const { name, index } of deferred) await target.collection(name).createIndexes([portableIndex(index)]);
  for (const item of manifest.collections) {
    const actual = await target.collection(item.name).listIndexes().toArray();
    if (JSON.stringify(actual.map(indexSignature).sort())
      !== JSON.stringify(item.indexes.map(indexSignature).sort())) fail('index_verification_failed');
  }
  return { status: 'verified', collections: manifest.collections.length,
    documents: manifest.documents, bytes: manifest.bytes, documentHashesMatched: true,
    indexesMatched: true, sourceWrites: 0, environmentChanged: false,
    geographicIndexesRebuiltUsingTargetDefault: true,
    note: 'TTL expiration resumes after verification; keep source and snapshot for rollback.' };
}

async function main() {
  let sourceClient, targetClient;
  let phase = 'configuration';
  const deadline = setTimeout(() => {
    console.log(JSON.stringify({ status: 'failed', phase, reason: 'deadline_exceeded', environmentChanged: false }));
    process.exit(2);
  }, 10 * 60 * 1000);
  try {
    const args = process.argv.slice(2);
    const resumeArg = args.find(arg => arg.startsWith('--resume='));
    if (args.some(arg => !['--snapshot', '--apply'].includes(arg) && arg !== resumeArg)) fail('invalid_arguments');
    if (resumeArg && (args.includes('--snapshot') || !args.includes('--apply'))) fail('invalid_arguments');
    if (args.includes('--apply') && !args.includes('--snapshot') && !resumeArg) fail('snapshot_flag_required');
    const sourceUri = dotenv.parse(await readFile(path.join(apiRoot, '.env'))).MONGODB_URI;
    const targetUri = dotenv.parse(await readFile(path.join(apiRoot, '.data/atlas-target.env'))).MONGODB_URI;
    if (!sourceUri?.startsWith('mongodb://') || !targetUri?.startsWith('mongodb+srv://')
      || sourceUri === targetUri) fail('invalid_transfer_configuration');
    const options = { serverSelectionTimeoutMS: 15000, connectTimeoutMS: 10000, maxPoolSize: 2 };
    sourceClient = new MongoClient(sourceUri, options);
    targetClient = new MongoClient(targetUri, options);
    if (sourceClient.options.dbName !== 'renthub' || targetClient.options.dbName !== 'renthub') fail('wrong_database');
    phase = 'connection';
    await sourceClient.connect();
    await targetClient.connect();
    const source = sourceClient.db(), target = targetClient.db();
    if (!resumeArg) await assertEmpty(target);
    const rows = await inventory(source);
    console.log(JSON.stringify({ status: 'plan', collections: rows.length,
      documents: rows.reduce((sum, row) => sum + row.count, 0), requireEmptyTarget: !resumeArg,
      sourceWrites: 0, targetWrites: 0 }));
    if (!args.includes('--snapshot') && !resumeArg) return;
    phase = 'snapshot';
    const name = resumeArg?.slice('--resume='.length);
    if (name && !/^atlas-logical-\d+$/.test(name)) fail('invalid_snapshot_directory');
    const directory = path.join(apiRoot, '.data/backups', name ?? `atlas-logical-${Date.now()}`);
    const manifest = resumeArg ? JSON.parse(await readFile(path.join(directory, 'manifest.json')))
      : await snapshotDatabase(source, directory);
    if (resumeArg) await verifySnapshotSource(source, directory, manifest);
    console.log(JSON.stringify({ status: 'snapshot_verified', directory,
      collections: manifest.collections.length, documents: manifest.documents, bytes: manifest.bytes }));
    if (!args.includes('--apply')) return;
    phase = 'transfer';
    const report = await transferSnapshot(source, target, directory, manifest, { resume: Boolean(resumeArg) });
    await writeFile(path.join(directory, 'transfer-result.json'), JSON.stringify(report, null, 2), { flag: 'wx' });
    console.log(JSON.stringify(report));
  } catch (error) {
    // Driver errors may embed credentials, IC fingerprints or duplicate emails. Never print them.
    console.log(JSON.stringify({ status: 'failed', phase,
      reason: error.migrationCode ?? 'database_operation_failed',
      databaseCode: typeof error.code === 'number' ? error.code : undefined,
      environmentChanged: false, sourceWrites: 0,
      guidance: 'Source is preserved. Inspect privately; do not rerun against a partially populated target.' }));
    process.exitCode = 1;
  } finally {
    clearTimeout(deadline);
    await sourceClient?.close();
    await targetClient?.close();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
