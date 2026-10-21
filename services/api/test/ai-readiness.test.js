import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { readRecommendationTrainingExport } from '../src/scripts/exportRecommendationData.js';
import { readPricingTrainingExport } from '../src/scripts/exportPricingData.js';
import { writeNewExport } from '../src/scripts/writeNewExport.js';
import { trainingComparableFeatures } from '../src/modules/listing/pricingTrainingExport.js';

test('native recommendation export is bounded/read-only/private and explicitly separates staged users', async () => {
  const server = await MongoMemoryServer.create();
  const client = new mongoose.mongo.MongoClient(server.getUri());
  try {
    await client.connect();
    const db = client.db('readiness'), now = new Date('2026-10-21T00:00:00Z');
    await db.collection('users').insertOne({ authId: 'private-user', email: 'secret@example.com',
      coordinates: [101, 3], savedListingIds: ['l1'], updatedAt: new Date('2026-10-20') });
    await db.collection('listingviews').insertOne({ userId: 'private-user', listingId: 'l2',
      lastViewedAt: new Date('2026-10-19'), expiresAt: new Date('2026-11-01') });
    await db.collection('bookings').insertMany([
      { publicId: 'b1', renterId: 'private-user', listingId: 'l1', status: 'completed',
        sourceType: 'marketplace', completedAt: new Date('2026-10-20') },
      { publicId: 'b2', renterId: 'demo-user', listingId: 'l3', status: 'completed',
        sourceType: 'demo_seed', completedAt: new Date('2026-10-20') },
    ]);
    const collections = await db.listCollections().toArray();
    const indexes = await db.collection('users').indexes();
    const natural = await readRecommendationTrainingExport(db, { now });
    assert.equal(natural.summary.interactions, 3);
    assert.deepEqual(natural.summary.sourceTypes, { demo_seed: 1, marketplace: 2 });
    const staged = await readRecommendationTrainingExport(db, { now, stagedUserIds: ['private-user'] });
    assert.deepEqual(staged.summary.sourceTypes, { demo_seed: 3 });
    assert.equal(staged.rows.find((r) => r.listingId === 'l1').interactionType, 'completed_rental');
    for (const secret of ['private-user', 'demo-user', 'secret@example.com', 'coordinates', 'authId']) {
      assert.equal(JSON.stringify(staged).includes(secret), false, secret);
    }
    assert.deepEqual(await db.listCollections().toArray(), collections);
    assert.deepEqual(await db.collection('users').indexes(), indexes);
    assert.equal((await db.collection('bookings').findOne({ publicId: 'b1' })).sourceType, 'marketplace');
    await assert.rejects(readRecommendationTrainingExport(db, { limit: 1, now }), /limit exceeded/);
    await assert.rejects(readRecommendationTrainingExport(db, { limit: 0, now }), /Limit/);
    await assert.rejects(readRecommendationTrainingExport(db, { stagedUserIds: [null] }), /Staged users/);
    await db.collection('listings').insertOne({ publicId: 'l1', ownerId: 'owner', listingType: 'physical',
      category: 'Devices', subcategory: 'Cameras', brand: 'Canon', productModel: 'camera',
      status: 'inactive', dailyPrice: 100, updatedAt: new Date('2026-10-20') });
    await db.collection('bookings').updateOne({ publicId: 'b1' }, { $set: { listingType: 'physical',
      paymentStatus: 'captured', startDate: '2026-10-18', endDate: '2026-10-19', pricing: { baseAmount: 200 } } });
    const prices = await readPricingTrainingExport(db, { now, stagedUserIds: ['private-user'] });
    assert.equal(prices.summary.targetSources.demo_seed_completed_rental, 1);
    assert.equal(prices.summary.targetSources.completed_rental, undefined);
  } finally { await client.close(); await server.stop(); }
});

test('export file creation never overwrites an earlier export, even concurrently', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'renthub-readiness-'));
  try {
    const file = path.join(directory, 'export.json');
    const results = await Promise.allSettled([writeNewExport(file, { first: true }), writeNewExport(file, { second: true })]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    const before = await readFile(file, 'utf8');
    await assert.rejects(writeNewExport(file, { replacement: true }), { code: 'EEXIST' });
    assert.equal(await readFile(file, 'utf8'), before);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('forward-time features reject future, late-known, same-product and demo evidence', () => {
  const subject = { category: 'Devices', subcategory: 'Cameras', group_id: 'subject', brand: 'Canon',
    product_model: 'R5', state: 'Selangor', rental_duration_days: 1, source_type: 'real',
    observed_at: '2026-10-20T00:00:00Z' };
  const prior = (i, patch = {}) => ({ ...subject, group_id: `prior-${i}`, product_model: `camera-${i}`,
    observed_at: '2026-10-10T00:00:00Z', daily_price: 100,
    target_source: 'active_asking', ...patch });
  const history = [prior(1), prior(2), prior(3), prior(4, { source_type: 'demo_seed', daily_price: 9999 }),
    prior(5, { group_id: 'subject', daily_price: 9999 }),
    prior(6, { observed_at: '2026-10-21', daily_price: 9999 }),
    prior(7, { source_type: 'external_asking_price', target_source: 'external_asking_price',
      available_at: '2026-10-21', daily_price: 9999 }),
    prior(8, { source_type: 'external_asking_price', target_source: 'external_asking_price', daily_price: 9999 })];
  const result = trainingComparableFeatures(subject, history);
  assert.equal(result.comparable_active_count, 3);
  assert.equal(result.comparable_active_median, 100);
  assert.equal(result.historical_rental_count, 0);
});
