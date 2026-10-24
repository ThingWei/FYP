import test from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { readPriceCoverageAudit, parseAuditOptions } from '../src/scripts/auditPriceCoverage.js';

const now = new Date('2026-10-24T00:00:00Z');
const reference = (patch = {}) => ({ category: 'Books', subcategory: 'Fiction', brand: 'PRIVATE-AUTHOR',
  productModel: 'PRIVATE-TITLE', sourceType: 'external_asking_price', sourceName: 'PRIVATE-SOURCE',
  sourceUrl: 'https://example.test/book', active: true, currency: 'MYR', country: 'MY',
  collectionMethod: 'manual_csv', reviewedBy: 'PRIVATE-REVIEWER', reviewedAt: now, observedAt: now,
  quotedAmount: 5, rentalDurationDays: 60, dailyPrice: 5 / 60, ...patch });

test('audit options fail before connecting on malformed bounds, missing paths and unknown writes', () => {
  assert.deepEqual(parseAuditOptions([]), { limit: 10000, output: undefined });
  assert.deepEqual(parseAuditOptions(['--limit', '20', '--output', 'new.json']), { limit: 20, output: 'new.json' });
  for (const args of [['--limit'], ['--limit', '0'], ['--limit', '10001'], ['--limit', '1e2'],
    ['--limit', '1.5'], ['--output'], ['--output', '--limit'], ['--enable'], ['--import']]) {
    assert.throws(() => parseAuditOptions(args), undefined, JSON.stringify(args));
  }
});

test('native audit is bounded, aggregate-only, all-22, respects source gates and creates no collections/indexes', async () => {
  const server = await MongoMemoryServer.create();
  const client = new mongoose.mongo.MongoClient(server.getUri(), { monitorCommands: true });
  try {
    await client.connect();
    const db = client.db('audit-test');
    await db.collection('pricing_references').insertMany([
      reference(), reference({ sourceUrl: 'https://example.test/old', observedAt: new Date('2020-01-01') }),
      reference({ category: 'Devices', subcategory: 'Cameras', brand: 'Canon', productModel: 'RF lens 35mm',
        quotedAmount: 100, rentalDurationDays: 1, dailyPrice: 100, collectionMethod: 'automatic',
        sourceId: 'rentism', productType: 'camera_lens', validationStatus: 'accepted',
        validatedAt: now, durationMinDays: 1, durationMaxDays: 1 }),
    ]);
    await db.collection('pricing_sources').insertMany([{ sourceId: 'rentism', enabled: true, lastSuccessAt: now },
      { sourceId: 'itpa', enabled: false, leaseToken: 'PRIVATE-TOKEN', errorMessage: 'PRIVATE-ERROR' }]);
    const before = await db.listCollections().toArray();
    const beforeIndexes = await db.collection('pricing_references').indexes();
    const writes = [];
    client.on('commandStarted', (event) => {
      if (['insert', 'update', 'delete', 'create', 'createIndexes', 'drop', 'findAndModify'].includes(event.commandName)) writes.push(event.commandName);
    });
    const report = await readPriceCoverageAudit(db, { now, approvedSourceIds: ['rentism', 'itpa'] });
    assert.equal(report.rows.length, 22);
    assert.equal(report.categoriesWithReferences, 2);
    assert.equal(report.totals.eligibleObservations, 2);
    assert.equal(report.databaseWrites, 0);
    const fiction = report.rows.find((row) => row.subcategory === 'Fiction');
    assert.equal(fiction.storedObservations, 2);
    assert.equal(fiction.excludedObservations, 1);
    assert.equal(report.actions.find((row) => row.subcategory === 'Textbooks').nextAction, 'seek_permissioned_product_quotes');
    assert.equal(report.actions.find((row) => row.subcategory === 'Sports equipment').nextAction, 'review_source_access');
    const camera = report.actions.find((row) => row.subcategory === 'Cameras');
    assert.deepEqual(camera.missingProductTypes, ['camera']);
    assert.equal(camera.nextAction, 'expand_product_type_evidence');
    assert.equal(camera.observationsWithoutCondition, 1);
    assert.equal(camera.observationsWithoutItemAge, 1);
    assert.equal(report.sources.find((s) => s.sourceId === 'itpa').collectionGate, 'disabled');
    assert.equal(report.sources.find((s) => s.sourceId === 'irent').collectionGate, 'access_review_required');
    assert.equal(report.sources.find((s) => s.sourceId === 'rentsmart').collectionGate, 'adapter_unavailable');
    const serialized = JSON.stringify(report);
    for (const privateValue of ['PRIVATE-', 'example.test/book', 'quotedAmount', 'reviewedBy', 'coordinates']) {
      assert.equal(serialized.includes(privateValue), false, privateValue);
    }
    const disabled = await readPriceCoverageAudit(db, { now, approvedSourceIds: [] });
    assert.equal(disabled.categoriesWithReferences, 1);
    assert.equal(disabled.actions.find((row) => row.subcategory === 'Cameras').nextAction, 'review_source_access');
    await assert.rejects(readPriceCoverageAudit(db, { now, limit: 2 }), /limit exceeded/);
    await assert.rejects(readPriceCoverageAudit(db, { now, limit: 0 }), /Limit/);
    await assert.rejects(readPriceCoverageAudit(db, { now: new Date('bad') }), /time/);
    await assert.rejects(readPriceCoverageAudit(db, { approvedSourceIds: true }), /approvals/);
    assert.deepEqual(await db.listCollections().toArray(), before);
    assert.deepEqual(await db.collection('pricing_references').indexes(), beforeIndexes);
    assert.equal(await db.collection('pricing_references').countDocuments(), 3);
    assert.deepEqual(writes, []);
    const emptyDb = client.db('missing-db');
    const empty = await readPriceCoverageAudit(emptyDb, { now, approvedSourceIds: [] });
    assert.equal(empty.rows.length, 22);
    assert.equal(empty.categoriesWithReferences, 0);
    assert.deepEqual(await emptyDb.listCollections().toArray(), []);
  } finally { await client.close(); await server.stop(); }
});
