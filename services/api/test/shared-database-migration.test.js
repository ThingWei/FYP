import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { BSON, MongoClient, ObjectId, Long, Int32, Double, Binary } from 'mongodb';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { portableIndex, bsonDocuments, inventory, assertEmpty, snapshotDatabase,
  transferSnapshot } from '../src/scripts/migrateSharedDatabase.js';

test('portable indexes retain text fields, compound order and identity uniqueness', () => {
  assert.deepEqual(portableIndex({ v: 2, background: true, key: { tenant: 1, _fts: 'text', _ftsx: 1, date: -1 },
    name: 'text', weights: { title: 1, description: 2 }, collation: { locale: 'simple', version: '57' } }),
  { key: { tenant: 1, title: 'text', description: 'text', date: -1 }, name: 'text',
    weights: { title: 1, description: 2 } });
  assert.deepEqual(portableIndex({ key: { point: '2dsphere' }, name: 'geo', '2dsphereIndexVersion': 4 }),
    { key: { point: '2dsphere' }, name: 'geo' });
  assert.throws(() => portableIndex({ key: { a: 1 }, name: 'a', unsupported: true }), /unsupported_index_option/);
});

test('snapshot refuses corrupt BSON and preserves numeric BSON types', () => {
  const raw = BSON.serialize({ _id: new ObjectId(), n: new Int32(3), decimal: new Double(3),
    long: Long.fromString('9007199254740993'), date: new Date('2026-11-03T00:00:00Z'),
    binary: new Binary(Buffer.from('test')), string: '001234567890' });
  assert.deepEqual(BSON.serialize(bsonDocuments(raw)[0]), raw);
  assert.throws(() => bsonDocuments(raw.subarray(0, raw.length - 1)), /invalid_snapshot/);
});

test('isolated database transfer preserves complete BSON and ordinary, text, geo, TTL and private indexes', async () => {
  const server = await MongoMemoryServer.create({ binary: { version: '7.0.24' } });
  const client = new MongoClient(server.getUri());
  try {
    await client.connect();
    const source = client.db('source'), target = client.db('target');
    const users = source.collection('users');
    await users.createIndex({ verifiedIdentityFingerprint: 1 }, { name: 'verified_mykad_identity_unique',
      unique: true, partialFilterExpression: { verifiedIdentityFingerprint: { $type: 'string' } } });
    await users.createIndex({ displayName: 'text', email: 'text' });
    await users.insertMany([{ _id: new ObjectId(), displayName: 'Unicode 测试', email: 'test@example.invalid',
      verifiedIdentityFingerprint: 'private-test-binding', number: new Double(7), whole: new Int32(7),
      long: Long.fromString('9007199254740993'), date: new Date(), binary: new Binary(Buffer.from('test')) },
    { _id: new ObjectId(), displayName: 'Leading zero', code: '00123' }]);
    const listingId = new ObjectId();
    await source.collection('listings').createIndex({ publicPoint: '2dsphere' });
    await source.collection('listings').insertOne({ _id: listingId,
      publicPoint: { type: 'Point', coordinates: [101.7, 3.1] }, price: new Double(71.44) });
    await source.collection('localsessions').createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await source.collection('localsessions').insertOne({ _id: new ObjectId(), expiresAt: new Date('2099-01-01') });
    const before = await inventory(source);
    await assertEmpty(target);
    assert.equal((await target.listCollections().toArray()).length, 0);
    const root = await mkdtemp(path.join(tmpdir(), 'renthub-migration-test-'));
    const directory = path.join(root, 'snapshot');
    const manifest = await snapshotDatabase(source, directory);
    assert.equal(manifest.documents, 4);
    assert.equal((await target.listCollections().toArray()).length, 0, 'snapshot must not write target');
    const result = await transferSnapshot(source, target, directory, manifest);
    assert.equal(result.documentHashesMatched, true);
    assert.equal(result.indexesMatched, true);
    assert.equal((await target.collection('users').findOne({ code: '00123' })).code, '00123');
    assert.equal((await inventory(source)).reduce((n, row) => n + row.count, 0), 4);
    assert.deepEqual(await inventory(source), before, 'source unchanged');
    assert.deepEqual(BSON.serialize(bsonDocuments(await readFile(path.join(directory, 'listings.bson')))[0]),
      await target.collection('listings').findOne({ _id: listingId }, { raw: true }));
    await assert.rejects(() => target.collection('users').insertOne({ verifiedIdentityFingerprint: 'private-test-binding' }),
      error => error.code === 11000);
    await assert.rejects(() => transferSnapshot(source, target, directory, manifest), /target_not_empty/);
    await assert.rejects(() => transferSnapshot(source, source, directory, manifest), /same_database/);
    await assert.rejects(() => snapshotDatabase(source, directory), error => error.code === 'EEXIST');
    const resumed = client.db('resumed');
    await resumed.createCollection('listings');
    await resumed.collection('listings').insertOne(bsonDocuments(await readFile(path.join(directory, 'listings.bson')))[0]);
    await resumed.createCollection('users');
    assert.equal((await transferSnapshot(source, resumed, directory, manifest, { resume: true })).indexesMatched, true);
    const foreign = client.db('foreign');
    await foreign.collection('users').insertOne({ _id: new ObjectId(), displayName: 'Different account' });
    await assert.rejects(() => transferSnapshot(source, foreign, directory, manifest, { resume: true }), /resume_target_conflict/);
    assert.equal(await foreign.collection('users').countDocuments({}), 1);
    assert.equal((await foreign.listCollections().toArray()).length, 1, 'conflict creates no further collections');
    await source.collection('users').updateOne({ code: '00123' }, { $set: { code: '00124' } });
    const clean = client.db('clean');
    await assert.rejects(() => transferSnapshot(source, clean, directory, manifest), /source_changed/);
    assert.equal((await clean.listCollections().toArray()).length, 0, 'changed source refused before target writes');
  } finally {
    await client.close();
    await server.stop();
  }
});
