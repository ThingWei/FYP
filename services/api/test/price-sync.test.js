import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import axios from 'axios';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { PriceSourceModel } from '../src/modules/listing/priceSource.model.js';
import { PricingReferenceModel } from '../src/modules/listing/pricingReference.model.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { adminModule } from '../src/modules/admin/index.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { setPriceSourceEnabled, runPriceSourceSync, drainPriceSyncJobs } from '../src/modules/listing/priceSync.service.js';

const endpoint = '/api/v1/admin/pricing-references/sources';
const admin = { 'x-user-id': 'source-admin', 'x-user-name': 'Source Admin', 'x-user-roles': 'admin' };
const owner = { 'x-user-id': 'source-owner', 'x-user-name': 'Source Owner', 'x-user-roles': 'owner' };
const identity = { authId: 'source-admin' };
const html = '<p>Canon EOS R50 (body only) RM 65/day</p><p>iPhone 15 RM 100/day</p>';
const fetchText = async (url) => url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : html;
let mongo, originalApproved, originalGet, originalRecommend;
before(async () => {
  mongo = await MongoMemoryServer.create();
  await connectDatabase(mongo.getUri());
  await Promise.all([PriceSourceModel.init(), PricingReferenceModel.init(), ProductCatalogModel.init(), UserModel.init()]);
  originalApproved = env.priceSyncApprovedSources;
  originalGet = axios.get;
  originalRecommend = aiClient.recommendPrice;
});
beforeEach(async () => {
  await drainPriceSyncJobs();
  await Promise.all([PriceSourceModel, PricingReferenceModel, ProductCatalogModel, BookingModel, ListingModel, UserModel, adminModule.Model].map((model) => model.deleteMany({})));
  env.priceSyncApprovedSources = ['rentism', 'rental-guy'];
  axios.get = originalGet;
});
after(async () => {
  await drainPriceSyncJobs(); env.priceSyncApprovedSources = originalApproved; axios.get = originalGet;
  aiClient.recommendPrice = originalRecommend; await disconnectDatabase(); await mongo.stop();
});
const enable = () => setPriceSourceEnabled('rentism', true, identity, { fetchText });

test('source status and all source mutations are admin only; strict payload and approval gate', async () => {
  for (const [method, path, body] of [['get', '', {}], ['patch', '/rentism', { enabled: false, confirmed: true }], ['post', '/rentism/sync', { confirmed: true }]]) {
    await request(app)[method](endpoint + path).set(owner).send(body).expect(403);
  }
  const status = await request(app).get(endpoint).set(admin).expect(200);
  assert.equal(status.body.data.coverage.length, 22);
  assert.equal(status.body.data.coverageReport.rows.length, 22);
  assert.equal(status.body.data.coverageReport.categoriesWithReferences, 0);
  assert.equal(await PriceSourceModel.countDocuments(), 0); // GET is read-only.
  await request(app).patch(endpoint + '/rentism').set(admin).send({ enabled: 'true', confirmed: true }).expect(400);
  await request(app).post(endpoint + '/rentism/sync').set(admin).send({ confirmed: true, url: 'https://evil.test/' }).expect(400);
  await request(app).patch(endpoint + '/missing').set(admin).send({ enabled: false, confirmed: true }).expect(404);
  await request(app).patch(endpoint + '/irent').set(admin).send({ enabled: true, confirmed: true }).expect(409);
  env.priceSyncApprovedSources = [];
  await request(app).patch(endpoint + '/rentism').set(admin).send({ enabled: true, confirmed: true }).expect(409);
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
});
test('enable verifies access/parser without inserting observations or fake administrator review', async () => {
  await assert.rejects(setPriceSourceEnabled('rentism', true, identity, { fetchText: async () => { throw new Error('HTTP_403'); } }), { code: 'PRICE_SOURCE_UNAVAILABLE' });
  assert.equal(await PriceSourceModel.countDocuments(), 0);
  await enable();
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  const source = await PriceSourceModel.findOne().lean();
  assert.equal(source.accessCheckedBy, identity.authId);
  await runPriceSourceSync('rentism', { fetchText, force: true });
  const reference = await PricingReferenceModel.findOne({ subcategory: 'Cameras' }).lean();
  assert.equal(reference.reviewedBy, undefined);
  assert.equal(reference.reviewedAt, undefined);
  assert.equal(reference.canonicalProductId, 'renthub-curated:devices:cameras:canon:eos-r50');
  assert.equal(reference.validationStatus, 'accepted');
  assert.equal(await BookingModel.countDocuments(), 0);
  assert.ok(await adminModule.Model.exists({ action: 'pricing_source.synced' }));
});
test('refresh is idempotent, scheduled jobs respect 24 hours, deactivation survives refresh', async () => {
  await enable(); await runPriceSourceSync('rentism', { fetchText });
  assert.equal((await runPriceSourceSync('rentism', { fetchText })).skipped, true);
  const ref = await PricingReferenceModel.findOne().lean();
  await request(app).patch('/api/v1/admin/pricing-references/' + ref.publicId + '/deactivate').set(admin).send({ confirmed: true }).expect(200);
  await runPriceSourceSync('rentism', { fetchText, force: true });
  assert.equal(await PricingReferenceModel.countDocuments(), 2);
  const refreshed = await PricingReferenceModel.findOne({ publicId: ref.publicId }).lean();
  assert.equal(refreshed.active, false);
  assert.equal(refreshed.deactivatedBy, 'source-admin');
  const state = await PriceSourceModel.findOne().lean();
  assert.equal(state.nextRunAt.getTime() - state.lastSuccessAt.getTime(), 86_400_000);
});

test('coverage is read-only, admin-only and counts only currently enabled eligible references', async () => {
  await enable(); await runPriceSourceSync('rentism', { fetchText });
  const before = await PricingReferenceModel.find().sort({ publicId: 1 }).lean();
  const response = await request(app).get(endpoint).set(admin).expect(200);
  const report = response.body.data.coverageReport;
  assert.equal(report.categoriesWithReferences, 2);
  assert.equal(report.rows.find((row) => row.subcategory === 'Cameras').uniqueOfferCount, 1);
  assert.equal(report.rows.find((row) => row.subcategory === 'Fiction').eligibleObservations, 0);
  assert.deepEqual(await PricingReferenceModel.find().sort({ publicId: 1 }).lean(), before);
  await setPriceSourceEnabled('rentism', false, identity);
  const disabled = await request(app).get(endpoint).set(admin).expect(200);
  assert.equal(disabled.body.data.coverageReport.categoriesWithReferences, 0);
  assert.equal(await BookingModel.countDocuments(), 0);
});

test('PC Rent can enable after approval and missing robots; probes do not import quotes', async () => {
  const pcFetcher = async (url) => {
    if (url.endsWith('/robots.txt')) throw Object.assign(new Error('HTTP_404'), { status: 404 });
    return '<table><tr><td>Daily</td><td>RM 200 2200 ANSI Lumens</td><td>RM 350 2700 ANSI Lumens</td><td>RM 500 3500 ANSI Lumens</td></tr></table>';
  };
  await assert.rejects(setPriceSourceEnabled('pc-rent', true, identity, { fetchText: pcFetcher }), { code: 'PRICE_SOURCE_REVIEW_REQUIRED' });
  env.priceSyncApprovedSources.push('pc-rent');
  assert.deepEqual(await setPriceSourceEnabled('pc-rent', true, identity, { fetchText: pcFetcher }), { sourceId: 'pc-rent', enabled: true });
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  const result = await runPriceSourceSync('pc-rent', { force: true, fetchText: pcFetcher });
  assert.equal(result.acceptedCount, 3);
  const rows = await PricingReferenceModel.find().lean();
  assert.ok(rows.every((row) => row.brand === '' && row.canonicalProductId === null && row.reviewedBy === undefined));
  assert.equal(await BookingModel.countDocuments(), 0);
});

test('enable failures expose only safe source diagnostic codes and never change source state', async () => {
  axios.get = async () => ({ status: 403, data: 'private path and secret' });
  const response = await request(app).patch(endpoint + '/rentism').set(admin)
    .send({ enabled: true, confirmed: true }).expect(503);
  assert.equal(response.body.error.code, 'PRICE_SOURCE_UNAVAILABLE');
  assert.deepEqual(response.body.error.details, { errorCode: 'HTTP_403' });
  assert.ok(!JSON.stringify(response.body).includes('private path'));
  assert.equal(await PriceSourceModel.countDocuments(), 0);
  await assert.rejects(setPriceSourceEnabled('rentism', true, identity, {
    fetchText: async () => { throw new Error('https://private.example/secret'); },
  }), (error) => error.details.errorCode === 'SOURCE_UNAVAILABLE');
});
test('per-source leases prevent overlapping workers and background endpoint returns 202', async () => {
  await enable();
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  let started;
  const entered = new Promise((resolve) => { started = resolve; });
  const first = runPriceSourceSync('rentism', { force: true, fetchText: async (url) => { started(); await held; return fetchText(url); } });
  await entered;
  assert.equal((await runPriceSourceSync('rentism', { force: true, fetchText })).skipped, true);
  await request(app).post(endpoint + '/rentism/sync').set(admin).send({ confirmed: true }).expect(409);
  release(); await first;
  axios.get = async (url) => ({ status: 200, data: await fetchText(url) });
  const response = await request(app).post(endpoint + '/rentism/sync').set(admin).send({ confirmed: true }).expect(202);
  assert.equal(response.body.data.status, 'running');
  await drainPriceSyncJobs();
  assert.equal(await PricingReferenceModel.countDocuments(), 2);
  assert.equal((await PriceSourceModel.findOne()).status, 'ready');
});
test('failed/empty collection preserves valid values and dates, reports bounded backoff', async () => {
  await enable(); await runPriceSourceSync('rentism', { fetchText });
  const ref = await PricingReferenceModel.findOne().lean(), state = await PriceSourceModel.findOne().lean();
  await assert.rejects(runPriceSourceSync('rentism', { force: true, fetchText: async () => { throw new Error('HTTP_429'); } }), { code: 'PRICE_SOURCE_UNAVAILABLE' });
  let failed = await PriceSourceModel.findOne().lean();
  assert.equal(failed.errorCode, 'HTTP_429');
  assert.equal(failed.lastSuccessAt.getTime(), state.lastSuccessAt.getTime());
  assert.equal(failed.nextRunAt.getTime() - failed.lastAttemptAt.getTime(), 3_600_000);
  await assert.rejects(runPriceSourceSync('rentism', { force: true, fetchText: async (url) => url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : '<p>Changed</p>' }));
  failed = await PriceSourceModel.findOne().lean();
  assert.equal(failed.consecutiveFailures, 2);
  assert.equal(failed.nextRunAt.getTime() - failed.lastAttemptAt.getTime(), 7_200_000);
  const retained = await PricingReferenceModel.findOne({ publicId: ref.publicId }).lean();
  assert.equal(retained.observedAt.getTime(), ref.observedAt.getTime());
  assert.equal(retained.dailyPrice, ref.dailyPrice);
});
test('source disabled during collection cannot insert prices and releases its lease', async () => {
  await enable();
  let stopped = false;
  await assert.rejects(runPriceSourceSync('rentism', { force: true, fetchText: async (url) => {
    if (!stopped) { stopped = true; await setPriceSourceEnabled('rentism', false, identity); }
    return fetchText(url);
  } }));
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  const source = await PriceSourceModel.findOne().lean();
  assert.equal(source.status, 'disabled');
  assert.equal(source.leaseToken, undefined);
});
test('expired leases recover and withdrawn approvals exclude enabled sources', async () => {
  await enable();
  await PriceSourceModel.updateOne({ sourceId: 'rentism' }, { $set: { leaseToken: 'crashed-worker', leaseUntil: new Date(Date.now() - 1000) } });
  await runPriceSourceSync('rentism', { force: true, fetchText });
  assert.equal(await PricingReferenceModel.countDocuments(), 2);
  env.priceSyncApprovedSources = [];
  const status = await request(app).get(endpoint).set(admin).expect(200);
  assert.equal(status.body.data.sources.find((row) => row.sourceId === 'rentism').enabled, false);
  await assert.rejects(runPriceSourceSync('rentism', { force: true, fetchText }), { code: 'PRICE_SOURCE_REVIEW_REQUIRED' });
});
test('specification-only automated quotes can be stored without fabricated brands, review or catalogue IDs', async () => {
  const specFetcher = async (url) => url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : '<div class="trg-catalogue-card"><h3 class="trg-product-heading">Projector 4000 lumens</h3><span class="trg-reference-price">One-day reference: RM 180</span><p class="trg-product-description">Equipment only</p></div>';
  await setPriceSourceEnabled('rental-guy', true, identity, { fetchText: specFetcher });
  await runPriceSourceSync('rental-guy', { force: true, fetchText: specFetcher });
  const reference = await PricingReferenceModel.findOne().lean();
  assert.equal(reference.brand, ''); assert.equal(reference.identityLevel, 'specification_only');
  assert.equal(reference.canonicalProductId, null); assert.equal(reference.reviewedBy, undefined);
});
test('Goritta stays gated until review; permitted four-day fixtures reach inference without becoming history', async () => {
  let fetches = 0;
  const gorittaHtml = '<div class="advc-carousel-images-with-text"><div class="advc-carousel-images-with-text__head">Tents Fee covers up to 4 days of usage</div><li class="advc-carousel-images-with-text__item"><div class="advc-carousel-images-with-text__item-title">Mobi Garden QR Tent - Black Coated</div><div class="advc-carousel-images-with-text__item-description">2-3 person RM112</div></li></div>';
  const fixture = async (url) => { fetches++; return url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : gorittaHtml; };
  await assert.rejects(setPriceSourceEnabled('goritta', true, identity, { fetchText: fixture }), { code: 'PRICE_SOURCE_REVIEW_REQUIRED' });
  assert.equal(fetches, 0);
  assert.equal(await PriceSourceModel.countDocuments(), 0);
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  env.priceSyncApprovedSources = ['goritta']; // Test-only permission configuration, not a publisher-rights claim.
  await setPriceSourceEnabled('goritta', true, identity, { fetchText: fixture });
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  await runPriceSourceSync('goritta', { fetchText: fixture, force: true });
  const row = await PricingReferenceModel.findOne().lean();
  assert.equal(row.quotedAmount, 112);
  assert.equal(row.rentalDurationDays, 4);
  assert.equal(row.dailyPrice, 28);
  assert.equal(row.productModel, 'QR Tent - Black Coated');
  assert.equal(row.reviewedBy, undefined);
  await request(app).post('/api/v1/users/session').set(owner).expect(201);
  let evidence;
  aiClient.recommendPrice = async (input) => { evidence = input.market_evidence; return { available: true, suggested_daily_price: 28 }; };
  const input = { itemProfile: { category: 'Equipment', subcategory: 'Sports equipment', brand: 'Mobi Garden',
    product_model: 'QR Tent - Black Coated', condition: 'Good', item_age_years: 2 }, rentalDurationDays: 4 };
  await request(app).post('/api/v1/listings/price-recommendation').set(owner).send(input).expect(200);
  assert.equal(evidence.external_asking_price_count, 1);
  assert.equal(evidence.historical_rental_count, 0);
  await request(app).post('/api/v1/listings/price-recommendation').set(owner).send({ ...input, rentalDurationDays: 1 }).expect(200);
  assert.equal(evidence.external_asking_price_count, 0);
  assert.equal(await BookingModel.countDocuments(), 0);
  await PricingReferenceModel.updateOne({ _id: row._id }, { $set: { active: false } });
  await runPriceSourceSync('goritta', { fetchText: fixture, force: true });
  assert.equal((await PricingReferenceModel.findById(row._id)).active, false);
  assert.equal(await PricingReferenceModel.countDocuments(), 1);
});

test('automatic evidence reaches inference, source disable and stale dates exclude it; history unchanged', async () => {
  await request(app).post('/api/v1/users/session').set(owner).expect(201);
  await enable(); await runPriceSourceSync('rentism', { fetchText });
  const listing = await ListingModel.create({ publicId: 'l-source-history', ownerId: 'source-owner', ownerName: 'Owner',
    title: 'Canon EOS R50', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', brand: 'Canon', productModel: 'EOS R50',
    condition: 'Excellent', itemAgeYears: 3, fulfilmentMethods: ['pickup'], location: 'Kuala Lumpur', dailyPrice: 60, status: 'inactive' });
  await BookingModel.create({ publicId: 'RH-BKG-2026-SYNC1', listingId: listing.publicId, listingTitle: listing.title, listingType: 'physical',
    renterId: 'source-renter', renterName: 'Renter', ownerId: 'source-owner', startDate: '2026-10-01', endDate: '2026-10-01',
    fulfilmentMethod: 'pickup', status: 'completed', paymentStatus: 'settled', completedAt: new Date(), sourceType: 'marketplace', pricing: { baseAmount: 60, total: 60 } });
  let evidence;
  aiClient.recommendPrice = async (input) => { evidence = input.market_evidence; return { available: true, suggested_daily_price: 65 }; };
  const payload = { itemProfile: { category: 'Devices', subcategory: 'Cameras', brand: 'Canon', product_model: 'EOS R50', condition: 'Excellent', item_age_years: 3 }, rentalDurationDays: 1 };
  const price = () => request(app).post('/api/v1/listings/price-recommendation').set(owner).send(payload).expect(200);
  await price();
  assert.equal(evidence.automated_asking_price_count, 1);
  assert.equal(evidence.reviewed_asking_price_count, 0);
  assert.equal(evidence.external_asking_price_count, 1);
  assert.equal(evidence.comparable_active_median, 65);
  assert.equal(evidence.historical_rental_count, 1);
  await request(app).patch(endpoint + '/rentism').set(admin).send({ enabled: false, confirmed: true }).expect(200);
  await price(); assert.equal(evidence.external_asking_price_count, 0); assert.equal(evidence.historical_rental_count, 1);
  await enable();
  await PricingReferenceModel.updateMany({}, { $set: { observedAt: new Date(Date.now() - 366 * 86_400_000) } });
  await price(); assert.equal(evidence.external_asking_price_count, 0); assert.equal(evidence.historical_rental_count, 1);
  assert.equal(await BookingModel.countDocuments(), 1);
});
