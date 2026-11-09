import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env, validateEnv } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { PricingReferenceModel } from '../src/modules/listing/pricingReference.model.js';
import { PRICE_PRODUCT_DOMAINS, compatibleProductReference, productTypeFor } from '../src/modules/listing/priceProductDomains.js';
import { demonstrationBookingReason, limitedPriceGuide } from '../src/modules/listing/pricingRecovery.js';
import { selectComparableTier } from '../src/modules/listing/pricingEvidence.js';
import { buildPricingTrainingExport } from '../src/modules/listing/pricingTrainingExport.js';
import { pricingReadinessSummary } from '../src/scripts/auditPricingReadiness.js';
import { parsePriceSource } from '../src/modules/listing/priceSource.parsers.js';
import { priceSource } from '../src/modules/listing/priceSources.registry.js';

const at = new Date('2026-10-20T12:00:00Z');
const snapshot = { listingType: 'physical', sourceType: 'marketplace', category: 'Devices', subcategory: 'Audio',
  brand: 'JBL', productModel: 'Charge 5', condition: 'Good', priceProvenance: { origin: 'owner_entered', independence: 'unverified' } };
const booking = { publicId: 'RH-BKG-2026-TESTDEMO', listingId: 'l-demo-speaker', listingType: 'physical',
  status: 'completed', paymentStatus: 'settled', sourceType: 'marketplace', pricingEvidenceSnapshot: snapshot,
  completedAt: at, pricing: { baseAmount: 40, total: 40, originalRentalDays: 2 },
  startDate: new Date('2026-10-18'), endDate: new Date('2026-10-19') };
const payment = { bookingId: booking.publicId, type: 'capture', status: 'succeeded', amount: 40,
  currency: 'MYR', simulated: true, createdAt: new Date('2026-10-18') };

test('demo history requires immutable non-AI identity, completion and recorded simulated capture', () => {
  assert.equal(demonstrationBookingReason(booking, [payment], at), null);
  for (const change of [{ status: 'active' }, { pricingEvidenceSnapshot: null }, { paymentStatus: 'unpaid' },
    { completedAt: new Date('2099-01-01') }, { pricing: { ...booking.pricing, currency: 'USD' } },
    { pricingEvidenceSnapshot: { ...snapshot, listingType: 'service' } },
    { pricingEvidenceSnapshot: { ...snapshot, priceProvenance: { origin: 'ai_edited' } } },
    { pricingEvidenceSnapshot: { ...snapshot, priceProvenance: { origin: 'unknown' } } }]) {
    assert.ok(demonstrationBookingReason({ ...booking, ...change }, [payment], at));
  }
  for (const change of [{ simulated: false }, { amount: 1 }, { currency: 'USD' }, { status: 'failed' },
    { createdAt: new Date('2099-01-01') }]) {
    assert.ok(demonstrationBookingReason(booking, [{ ...payment, ...change }], at));
  }
  assert.ok(demonstrationBookingReason(booking, [], at));
  assert.equal(buildPricingTrainingExport({ bookings: [booking], payments: [payment] }).rows.length, 0);
});

test('sparse and identical observations offer factual guides without invented uncertainty', () => {
  const p = { ...snapshot, product_model: snapshot.productModel, rental_duration_days: 1 };
  const tier = selectComparableTier([{ ...snapshot, dailyPrice: 20 }], p);
  const guide = limitedPriceGuide(tier, { items: [] }, 'Devices');
  assert.equal(guide.suggested_daily_price, 20);
  assert.equal(guide.lower_bound, null);
  assert.equal(guide.upper_bound, null);
  assert.equal(guide.confidence, 0);
  const identical = limitedPriceGuide({ items: [20, 20, 20].map((dailyPrice) => ({ dailyPrice })) }, { items: [] }, 'Devices');
  assert.equal(identical.lower_bound, 20);
  assert.equal(identical.upper_bound, 20);
  assert.equal(limitedPriceGuide({ items: [] }, { items: [] }, 'Books'), null);
});

test('exact named identities survive missing type keywords without permitting cross-model guesses', () => {
  const row = { category: 'Devices', subcategory: 'Audio', brand: 'Maker', productModel: 'Model Q100' };
  assert.equal(compatibleProductReference(row, row), true);
  assert.equal(compatibleProductReference(row, { ...row, productModel: 'Model Q200' }), false);
  assert.equal(compatibleProductReference(row, { ...row, subcategory: 'Gaming' }), false);
  assert.equal(compatibleProductReference({ ...row, variant: '256GB' }, { ...row, variant: '128GB' }), false);
  assert.equal(productTypeFor('Equipment', 'Event equipment', 'Projector screen 100 inch'), 'projector_screen');
  const portable = { ...row, productModel: 'Portable speaker 100 W RMS' };
  assert.equal(compatibleProductReference(portable, { ...row, productModel: 'PA speaker 100 W RMS' }), false);
  assert.equal(compatibleProductReference(portable, { ...row, productModel: 'Portable speaker 100 W peak' }), false);
  assert.equal(compatibleProductReference(portable, { ...row, productModel: 'Portable speaker 200 W RMS' }), false);
  assert.equal(compatibleProductReference(portable, { ...row, productModel: 'Microphone' }), false);
});

test('all-22 readiness audit is aggregate-only, including absent data and excluded legacy records', () => {
  const summary = pricingReadinessSummary({ rows: [] }, [], [booking, { ...booking, pricingEvidenceSnapshot: null }], [payment], at);
  assert.equal(summary.rows.length, 22);
  assert.equal(summary.completedWithoutSnapshots, 1);
  assert.equal(summary.rows.find((r) => r.subcategory === 'Audio').eligibleSimulatedCompletedRentals, 1);
  assert.equal(summary.rows.find((r) => r.subcategory === 'Audio').cleanCompletedRentals, 0);
  assert.equal(JSON.stringify(summary).includes(booking.publicId), false);
  assert.equal(JSON.stringify(summary).includes('Charge 5'), false);
  assert.equal(summary.databaseWrites, 0);
});

test('Audio parser handles multiple product types and keeps PA bundles outside portable speakers', () => {
  const html = '<p>JBL Charge 5 RM20/day</p><p>Sony WH-1000XM5 RM25/day</p><p>Boya Microphone RM30/day</p>';
  const result = parsePriceSource(priceSource('rentism'), html);
  assert.deepEqual(result.rows.map((r) => r.productType).sort(), ['headphones', 'microphone', 'speaker']);
  assert.ok(result.rows.every((r) => r.subcategory === 'Audio'));
});

test('demonstration evidence must be explicitly selected and cannot run in production', () => {
  assert.throws(() => validateEnv({ port: 3000, mongoUri: 'mongodb://localhost/test', authMode: 'mock',
    pricingEvidenceMode: 'bad' }), /PRICING_EVIDENCE_MODE/);
  assert.throws(() => validateEnv({ port: 3000, mongoUri: 'mongodb://localhost/test', authMode: 'mock',
    nodeEnv: 'production', pricingEvidenceMode: 'demonstration' }), /Demonstration pricing evidence/);
});

let mongo, originalAI, originalMode, originalDemo;
const headers = { 'x-user-id': 'u-recovery-owner', 'x-user-name': 'Recovery Owner', 'x-user-roles': 'owner' };
const profile = { category: 'Devices', subcategory: 'Audio', brand: 'JBL', product_model: 'Charge 5',
  condition: 'Good', item_age_years: 1 };
const endpoint = '/api/v1/listings/price-recommendation';
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  originalAI = aiClient.recommendPrice; originalMode = env.pricingEvidenceMode; originalDemo = env.pricingIncludeDemoSeed;
  await Promise.all([UserModel.init(), BookingModel.init(), PaymentModel.init(), PricingReferenceModel.init()]);
});
beforeEach(async () => {
  await Promise.all([UserModel.deleteMany({}), BookingModel.deleteMany({}), PaymentModel.deleteMany({}), PricingReferenceModel.deleteMany({})]);
  env.pricingEvidenceMode = 'clean'; env.pricingIncludeDemoSeed = false;
  aiClient.recommendPrice = async () => ({ available: false, error: 'test service offline' });
  await request(app).post('/api/v1/users/session').set(headers).expect(201);
});
after(async () => {
  aiClient.recommendPrice = originalAI; env.pricingEvidenceMode = originalMode; env.pricingIncludeDemoSeed = originalDemo;
  await disconnectDatabase(); await mongo.stop();
});
const reference = (category, subcategory, brand, productModel, id) => ({
  publicId: `pr-test-${id}`, observationKey: `test-${id}`, category, subcategory, brand, productModel,
  quotedAmount: 20, dailyPrice: 20, rentalDurationDays: 1, rateBasis: 'daily_rate',
  sourceName: 'Controlled fixture, not a live quote', sourceUrl: `https://example.test/${id}`,
  observedAt: new Date(), reviewedAt: new Date(), reviewedBy: 'fixture-admin' });

test('every subcategory has actionable no-data recovery and a usable exact-reference guide', async () => {
  let i = 0;
  for (const domain of PRICE_PRODUCT_DOMAINS) {
    const itemProfile = { ...domain, brand: 'Fixture maker', product_model: 'Reviewed named item', condition: 'Good', item_age_years: 1 };
    delete itemProfile.productTypes; delete itemProfile.requiredIdentity;
    const missing = await request(app).post(endpoint).set(headers).send({ itemProfile }).expect(200);
    assert.equal(missing.body.data.available, false, domain.subcategory);
    assert.equal(missing.body.data.pricing_guidance.manualPricingAvailable, true);
    assert.equal(missing.body.data.pricing_guidance.canRetry, false);
    await PricingReferenceModel.create(reference(domain.category, domain.subcategory, itemProfile.brand, itemProfile.product_model, i++));
    const found = await request(app).post(endpoint).set(headers).send({ itemProfile }).expect(200);
    assert.equal(found.body.data.available, true, domain.subcategory);
    assert.equal(found.body.data.estimate_kind, 'reference_guide');
    assert.equal(found.body.data.suggested_daily_price, 20);
    assert.equal(found.body.data.evidence.historical_rental_count, 0);
  }
});

test('completed simulated history is an opt-in fallback, never relabelled as clean payment evidence', async () => {
  await BookingModel.create({ ...booking, ownerId: 'u-other', renterId: 'u-tester', renterName: 'Tester', listingTitle: 'Speaker fixture', fulfilmentMethod: 'pickup' });
  await PaymentModel.collection.insertOne(payment);
  const before = await BookingModel.findOne().lean();
  const clean = await request(app).post(endpoint).set(headers).send({ itemProfile: profile, rentalDurationDays: 2, evidenceMode: 'demonstration' }).expect(200);
  assert.equal(clean.body.data.available, false);
  env.pricingEvidenceMode = 'demonstration';
  const demo = await request(app).post(endpoint).set(headers).send({ itemProfile: profile, rentalDurationDays: 2 }).expect(200);
  assert.equal(demo.body.data.available, true);
  assert.equal(demo.body.data.suggested_daily_price, 20);
  assert.equal(demo.body.data.evidence.historical_rental_count, 1);
  assert.equal(demo.body.data.evidence.marketplace_completed_rental_count, 0);
  assert.equal(demo.body.data.evidence.simulated_completed_rental_count, 1);
  assert.equal(demo.body.data.evidence.evidence_cohort, 'demonstration');
  assert.equal(demo.body.data.confidence_label, 'low');
  assert.deepEqual(await BookingModel.findOne().lean(), before);
  assert.equal((await PaymentModel.collection.findOne()).simulated, true);
  // Independent asking evidence always takes precedence, rather than being mixed.
  await PricingReferenceModel.create(reference('Devices', 'Audio', 'JBL', 'Charge 5', 'speaker'));
  const independent = await request(app).post(endpoint).set(headers).send({ itemProfile: profile, rentalDurationDays: 2 }).expect(200);
  assert.equal(independent.body.data.evidence.simulated_completed_rental_count, 0);
  assert.equal(independent.body.data.evidence.historical_rental_count, 0);
  assert.equal(independent.body.data.evidence.external_asking_price_count, 1);
});
