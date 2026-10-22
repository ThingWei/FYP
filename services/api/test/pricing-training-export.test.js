import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';
import { buildPricingTrainingExport, eligibleTrainingReference, trainingProductGroup } from '../src/modules/listing/pricingTrainingExport.js';
import { readPricingTrainingExport } from '../src/scripts/exportPricingData.js';
import { env } from '../src/config/env.js';
import { buildRecommendationInteractions } from '../src/modules/listing/recommendationInteractions.js';

const now = new Date('2026-10-20T00:00:00Z');
const item = (id, extra = {}) => ({ publicId: id, ownerId: 'private-owner', listingType: 'physical',
  category: 'Devices', subcategory: 'Cameras', brand: 'Canon', productModel: id,
  condition: 'Good', state: 'Selangor', location: 'PRIVATE UNIT', coordinates: [101, 3],
  dailyPrice: 100, status: 'active', updatedAt: new Date('2026-10-19'), ...extra });
const reference = (id, extra = {}) => ({ publicId: id, observationKey: id,
  sourceType: 'external_asking_price', active: true, currency: 'MYR', country: 'MY',
  category: 'Devices', subcategory: 'Cameras', brand: 'Canon', productModel: id,
  quotedAmount: 100, rentalDurationDays: 1, dailyPrice: 100,
  sourceName: 'Reviewed source', sourceUrl: 'https://example.com/rental',
  observedAt: new Date('2026-10-01'), reviewedAt: new Date('2026-10-02'),
  createdAt: new Date('2026-10-02'), reviewedBy: 'private-reviewer', collectionMethod: 'manual_csv', ...extra });
const automatic = (id, extra = {}) => reference(id, { collectionMethod: 'automatic', sourceId: 'rentism',
  validatedAt: new Date('2026-10-02'), validationStatus: 'accepted', productType: 'camera',
  durationMinDays: 1, durationMaxDays: 365, ...extra });
const build = (options) => buildPricingTrainingExport({ now, ...options });

test('reviewed/automated asking observations stay separate from completed rentals and private fields', () => {
  const result = build({ listings: [item('subject')], references: [reference('manual'), automatic('auto')],
    enabledSourceIds: ['rentism'] });
  assert.equal(result.rows.length, 3);
  assert.deepEqual(result.summary.targetSources, { external_asking_price: 2, active_asking: 1 });
  const subject = result.rows.find((r) => r.product_model === 'subject');
  assert.equal(subject.external_asking_price_count, 2);
  assert.equal(subject.historical_rental_count, 0);
  const serialized = JSON.stringify(result);
  for (const secret of ['private-owner', 'private-reviewer', 'PRIVATE UNIT', 'coordinates', '_knownAt']) {
    assert.equal(serialized.includes(secret), false, secret);
  }
  assert.ok(serialized.includes('https://example.com/rental'));
});

test('reference validation rejects disabled, stale, future, malformed, unreviewed or bundled observations', () => {
  for (const patch of [{ active: false }, { currency: 'USD' }, { country: 'SG' },
    { observedAt: new Date('2025-01-01') }, { observedAt: new Date('2027-01-01') },
    { reviewedAt: new Date('2027-01-01') }, { reviewedBy: null }, { sourceUrl: 'http://example.com' },
    { sourceUrl: 'https://localhost/x' }, { quotedAmount: '100' }, { quotedAmount: 100.001 },
    { dailyPrice: 101 }, { rentalDurationDays: 1.5 }, { rentalDurationDays: 0 },
    { itemAgeYears: Infinity }, { packageNotes: 'from RM100' }, { packageNotes: 'crew included' },
    { category: 'Toys' }, { subcategory: 'Cars' }]) {
    assert.equal(eligibleTrainingReference(reference('bad', patch), [], now), false, JSON.stringify(patch));
  }
  assert.equal(eligibleTrainingReference(automatic('disabled'), [], now), false);
  for (const patch of [{ validationStatus: 'pending' }, { validatedAt: null },
    { validatedAt: new Date('2027-01-01') }, { productType: 'smartphone' },
    { durationMinDays: 7, durationMaxDays: 2 }]) {
    assert.equal(eligibleTrainingReference(automatic('bad', patch), ['rentism'], now), false);
  }
});

test('past observations collected/reviewed later cannot leak into earlier targets', () => {
  const refs = ['a', 'b', 'c'].map((id) => reference(id, { reviewedAt: new Date('2026-10-18') }));
  const result = build({ listings: [item('early', { updatedAt: new Date('2026-10-10') }), item('late')], references: refs });
  assert.equal(result.rows.find((r) => r.product_model === 'early').external_asking_price_count, 0);
  assert.equal(result.rows.find((r) => r.product_model === 'late').external_asking_price_count, 3);
});

test('external comparables respect subcategory, product type and advertised duration band', () => {
  const refs = [automatic('lens1', { productModel: 'RF lens 35mm', productType: 'camera_lens' }),
    automatic('lens2', { productModel: 'RF lens 50mm', productType: 'camera_lens' }),
    automatic('long', { durationMinDays: 7, durationMaxDays: 30 }),
    reference('phone', { subcategory: 'Smartphones' })];
  const result = build({ listings: [item('camera')], references: refs, enabledSourceIds: ['rentism'] });
  const camera = result.rows.find((r) => r.product_model === 'camera');
  assert.equal(camera.external_asking_price_count, 0);
  const band = result.rows.find((r) => r.product_model === 'long');
  assert.equal(band.quoted_rental_days, 1);
  assert.equal(band.rental_duration_days, 7);
  assert.equal(band.duration_feature_basis, 'eligible_band_minimum');
});

test('same-product observations stay in one split group and cannot supply their own target evidence', () => {
  const a = item('a', { canonicalProductId: 'provider:camera' });
  const b = reference('b', { canonicalProductId: 'provider:camera' });
  assert.equal(trainingProductGroup(a), trainingProductGroup(b));
  assert.equal(trainingProductGroup(item('a', { brand: ' CANON ', productModel: 'EOS R6' })),
    trainingProductGroup(item('b', { brand: 'canon', productModel: 'eos r6' })));
  const result = build({ listings: [a], references: [b] });
  assert.equal(result.rows[1].external_asking_price_count, 0);
});

test('specification-only records never invent canonical/brand identities', () => {
  const result = build({ references: [automatic('spec', { category: 'Equipment', subcategory: 'Event equipment',
    productModel: 'Projector 5000 lumens', productType: 'projector', brand: 'Unbranded',
    canonicalProductId: 'invalid-claim', identityLevel: 'specification_only' })], enabledSourceIds: ['rentism'] });
  assert.equal(result.rows[0].brand, null);
  assert.equal(result.rows[0].canonicalProductId, null);
  assert.equal(result.rows[0].productMatchType, 'manual_entry');
});

test('completed evidence requires settled/captured payment; demos cannot contaminate marketplace evidence', () => {
  const listings = [item('subject'), item('old', { status: 'inactive' }), item('demo', { sourceType: 'demo_seed', status: 'inactive' })];
  const booking = (id, paymentStatus, extra = {}) => ({ listingId: id, status: 'completed', paymentStatus,
    startDate: '2026-09-01', endDate: '2026-09-02', completedAt: '2026-09-03', pricing: { baseAmount: 200 }, ...extra });
  const result = build({ listings, bookings: [booking('old', 'captured'), booking('old', 'authorized'),
    booking('demo', 'captured'), booking('old', 'captured', { status: 'cancelled' })] });
  assert.equal(result.summary.targetSources.completed_rental, 1);
  assert.equal(result.summary.targetSources.demo_seed_completed_rental, 1);
  assert.equal(result.rows.find((r) => r.product_model === 'subject').historical_rental_count, 1);
});

test('duplicate refreshes deduplicate; conflicting observations stop export', () => {
  assert.equal(build({ references: [reference('a'), reference('a')] }).summary.duplicateReferences, 1);
  assert.throws(() => build({ references: [reference('a'), reference('a', { dailyPrice: 200, quotedAmount: 200 })] }), /Conflicting/);
});

test('marketplace interaction cannot be relabelled demo by a stronger demo signal', () => {
  const rows = buildRecommendationInteractions({ includeDemoSeed: true,
    views: [{ userId: 'u', listingId: 'l', lastViewedAt: now }],
    bookings: [{ publicId: 'b', renterId: 'u', listingId: 'l', status: 'completed',
      sourceType: 'demo_seed', completedAt: now }] });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].sourceType, 'marketplace');
  assert.equal(rows[0].interactionType, 'viewed');
});

test('explicit staging applies before action precedence without promoting synthetic signals', () => {
  const input = { includeDemoSeed: true,
    views: [{ userId: 'u', listingId: 'l', lastViewedAt: now }],
    bookings: [{ publicId: 'b', renterId: 'u', listingId: 'l', status: 'completed',
      sourceType: 'demo_seed', completedAt: now },
    { publicId: 's', renterId: 'synthetic-u', listingId: 'synthetic-l', status: 'completed',
      sourceType: 'synthetic', completedAt: now }] };
  for (const classification of [{ allStaged: true }, { stagedUserIds: ['u'] }]) {
    const rows = buildRecommendationInteractions({ ...input, ...classification });
    const staged = rows.find((row) => row.userId === 'u');
    assert.equal(staged.sourceType, 'demo_seed');
    assert.equal(staged.interactionType, 'completed_rental');
    assert.equal(rows.find((row) => row.userId === 'synthetic-u').sourceType, 'synthetic');
  }
});

test('bounded native database export is read-only and does not create indexes or collections', async () => {
  const server = await MongoMemoryServer.create();
  const client = new mongoose.mongo.MongoClient(server.getUri());
  const approved = env.priceSyncApprovedSources;
  try {
    await client.connect();
    const db = client.db('export-test');
    await db.collection('listings').insertOne(item('subject'));
    await db.collection('pricing_references').insertMany([reference('a'), reference('b')]);
    const before = await db.listCollections().toArray();
    const indexes = await db.collection('listings').indexes();
    const result = await readPricingTrainingExport(db, { now });
    assert.equal(result.rows.length, 3);
    assert.equal(await db.collection('pricing_references').countDocuments(), 2);
    assert.deepEqual(await db.listCollections().toArray(), before);
    assert.deepEqual(await db.collection('listings').indexes(), indexes);
    const staged = await readPricingTrainingExport(db, { now, allStaged: true });
    assert.deepEqual(staged.summary.sourceTypes, { external_asking_price: 2, demo_seed: 1 });
    assert.equal(staged.summary.targetSources.demo_seed_active_asking, 1);
    assert.equal(staged.summary.targetSources.active_asking, undefined);
    assert.equal((await db.collection('listings').findOne({ publicId: 'subject' })).sourceType, undefined);
    await assert.rejects(readPricingTrainingExport(db, { now, limit: 1 }), /limit exceeded/);
    await assert.rejects(readPricingTrainingExport(db, { now, limit: 0 }), /Limit/);
    await db.collection('pricing_references').insertOne(automatic('auto'));
    await db.collection('pricing_sources').insertOne({ sourceId: 'rentism', enabled: true });
    env.priceSyncApprovedSources = [];
    assert.equal((await readPricingTrainingExport(db, { now })).rows.length, 3);
    env.priceSyncApprovedSources = ['rentism'];
    assert.equal((await readPricingTrainingExport(db, { now })).rows.length, 4);
    await db.collection('pricing_sources').updateOne({ sourceId: 'rentism' }, { $set: { enabled: false } });
    assert.equal((await readPricingTrainingExport(db, { now })).rows.length, 3);
  } finally { env.priceSyncApprovedSources = approved; await client.close(); await server.stop(); }
});
