import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { adminModule } from '../src/modules/admin/index.js';
import { PricingReferenceModel } from '../src/modules/listing/pricingReference.model.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { REFERENCE_COLUMNS, parseReferenceCsv } from '../src/modules/listing/pricingReference.service.js';

const admin = { 'x-user-id': 'u-price-admin', 'x-user-name': 'Price Admin', 'x-user-roles': 'admin' };
const owner = { 'x-user-id': 'u-price-owner', 'x-user-name': 'Price Owner', 'x-user-roles': 'owner' };
const date = new Date().toISOString().slice(0, 10);
const observation = { category: 'Devices', subcategory: 'Cameras', brand: 'Canon', model: 'EOS R50',
  quotedAmount: '65.00', rentalDays: '1', currency: 'MYR', sourceName: 'Reviewed example',
  sourceUrl: 'https://example.com/rental/canon', observedDate: date, location: '', state: '', condition: '', itemAgeYears: '', packageNotes: 'Body only' };
const csv = (...rows) => REFERENCE_COLUMNS.join(',') + '\r\n' + rows.map((row) =>
  REFERENCE_COLUMNS.map((key) => `"${String(row[key] ?? '').replaceAll('"', '""')}"`).join(',')).join('\r\n');
const endpoint = '/api/v1/admin/pricing-references';
let mongodb, originalRecommend;
before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([PricingReferenceModel.init(), ProductCatalogModel.init(), UserModel.init()]);
  originalRecommend = aiClient.recommendPrice;
});
beforeEach(async () => {
  await Promise.all([PricingReferenceModel.deleteMany({}), ProductCatalogModel.deleteMany({}),
    UserModel.deleteMany({}), BookingModel.deleteMany({}), ListingModel.deleteMany({}), adminModule.Model.deleteMany({})]);
  await request(app).post('/api/v1/users/session').set(owner);
});
after(async () => { aiClient.recommendPrice = originalRecommend; await disconnectDatabase(); await mongodb.stop(); });

test('the sourced starter CSV previews twenty observations without importing them', async () => {
  const content = await readFile(new URL('../../../docs/data/rental_price_references_starter.csv', import.meta.url), 'utf8');
  const response = await request(app).post(endpoint + '/preview').set(admin).send({ csv: content });
  assert.equal(response.status, 200);
  assert.equal(response.body.data.valid, true, JSON.stringify(response.body.data.errors));
  assert.equal(response.body.data.rowCount, 20);
  assert.equal(response.body.data.rows.find((row) => row.productModel === 'Camry').canonicalProductId,
    'renthub-curated:vehicles:cars:toyota:camry');
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  assert.equal(await BookingModel.countDocuments(), 0);
});

test('importing asking prices preserves an existing completed-rental count, median and provenance', async () => {
  await ListingModel.create({ publicId: 'l-reference-history', ownerId: owner['x-user-id'], ownerName: 'Owner',
    title: 'Canon EOS R50', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', brand: 'Canon',
    productModel: 'EOS R50', condition: 'Excellent', itemAgeYears: 3, fulfilmentMethods: ['pickup'],
    location: 'Kuala Lumpur', dailyPrice: 60, status: 'inactive' });
  await BookingModel.create({ publicId: 'RH-BKG-2026-REF1', listingId: 'l-reference-history', listingTitle: 'Canon EOS R50',
    listingType: 'physical', renterId: 'u-reference-renter', renterName: 'Renter', ownerId: owner['x-user-id'],
    startDate: '2026-10-01', endDate: '2026-10-01', fulfilmentMethod: 'pickup', status: 'completed',
    paymentStatus: 'settled', completedAt: new Date(), sourceType: 'marketplace', pricing: { baseAmount: 60, total: 60 } });
  let evidence;
  aiClient.recommendPrice = async (input) => { evidence = input.market_evidence; return { available: true, suggested_daily_price: 60 }; };
  const payload = { itemProfile: { category: 'Devices', subcategory: 'Cameras', condition: 'Excellent',
    brand: 'Canon', product_model: 'EOS R50', item_age_years: 3 }, rentalDurationDays: 1 };
  await request(app).post('/api/v1/listings/price-recommendation').set(owner).send(payload).expect(200);
  const beforeImport = { ...evidence };
  assert.equal(beforeImport.historical_rental_count, 1);
  await request(app).post(endpoint + '/import').set(admin).send({ csv: csv(observation), confirmed: true }).expect(200);
  await request(app).post('/api/v1/listings/price-recommendation').set(owner).send(payload).expect(200);
  for (const key of ['historical_rental_count', 'historical_rental_median', 'marketplace_completed_rental_count', 'demo_seed_completed_rental_count']) {
    assert.equal(evidence[key], beforeImport[key], key);
  }
  assert.equal(evidence.external_asking_price_count, 1);
  assert.equal(await BookingModel.countDocuments(), 1);
});

test('template and all import operations require an administrator', async () => {
  for (const [method, path] of [['get', '/template'], ['get', ''], ['post', '/preview'], ['post', '/import'], ['patch', '/pr-00000000000000000000000000000000/deactivate']]) {
    assert.equal((await request(app)[method](endpoint + path).set(owner).send({ csv: csv(observation), confirmed: true })).status, 403);
  }
  assert.equal((await request(app).get(endpoint + '/template').set(admin)).body.data.content, REFERENCE_COLUMNS.join(',') + '\r\n');
});

test('quoted UTF-8, comma, newline and escaped quote fields survive parsing', () => {
  const row = { ...observation, sourceName: 'Sewaan, Malaysia', packageNotes: 'Bag "included"\nNo delivery', model: 'Cámara' };
  assert.equal(parseReferenceCsv('\uFEFF' + csv(row))[0].packageNotes, row.packageNotes);
  assert.equal(parseReferenceCsv(csv(row))[0].model, 'Cámara');
  assert.throws(() => parseReferenceCsv('"unfinished'));
  assert.throws(() => parseReferenceCsv('a,b\n"closed"garbage,x'));
  assert.throws(() => parseReferenceCsv('x'.repeat(1048577)));
  assert.throws(() => parseReferenceCsv(csv(...Array(501).fill(observation))));
});

test('preview resolves cached identity but writes nothing; confirmation is explicit and idempotent', async () => {
  await ProductCatalogModel.create({ entityType: 'product', category: 'Devices', subcategory: 'Cameras', brand: 'Canon', model: 'EOS R50',
    normalizedBrand: 'canon', normalizedModel: 'eos r50', canonicalProductId: 'curated:canon:r50', catalogEntityId: 'curated:canon:r50',
    source: 'renthub-curated', lastSyncedAt: new Date() });
  const content = csv(observation, observation);
  const preview = await request(app).post(endpoint + '/preview').set(admin).send({ csv: content });
  assert.equal(preview.status, 200);
  assert.equal(preview.body.data.valid, true);
  assert.equal(preview.body.data.rows[0].canonicalProductId, 'curated:canon:r50');
  assert.equal(preview.body.data.duplicateCount, 1);
  assert.equal(await PricingReferenceModel.countDocuments(), 0);
  assert.equal((await request(app).post(endpoint + '/import').set(admin).send({ csv: content })).status, 400);
  const imported = await request(app).post(endpoint + '/import').set(admin).send({ csv: content, confirmed: true });
  assert.deepEqual(imported.body.data, { imported: 1, duplicates: 1 });
  const again = await request(app).post(endpoint + '/import').set(admin).send({ csv: content, confirmed: true });
  assert.deepEqual(again.body.data, { imported: 0, duplicates: 2 });
  const saved = await PricingReferenceModel.findOne().lean();
  assert.equal(saved.sourceType, 'external_asking_price');
  assert.equal(saved.reviewedBy, admin['x-user-id']);
  assert.equal(await BookingModel.countDocuments(), 0);
  assert.equal(await adminModule.Model.countDocuments({ action: 'pricing_references.imported' }), 2);
});

test('invalid rows and conflicting observations prevent the entire file from being imported', async () => {
  for (const change of [{ quotedAmount: 'abc65' }, { quotedAmount: '65.001' }, { quotedAmount: '1e2' },
    { quotedAmount: 'Infinity' }, { rentalDays: '1.5' }, { rentalDays: '0' }, { rentalDays: '366' },
    { currency: 'USD' }, { subcategory: 'Cars' }, { observedDate: '2026-02-30' },
    { observedDate: '2999-01-01' }, { sourceUrl: 'http://localhost:3000' }, { itemAgeYears: 'abc' },
    { packageNotes: 'from RM65' }, { packageNotes: 'crew included' }, { condition: 'Unknown' }]) {
    const content = csv(observation, { ...observation, model: 'Different model', ...change });
    const response = await request(app).post(endpoint + '/import').set(admin).send({ csv: content, confirmed: true });
    assert.equal(response.status, 400, JSON.stringify(change));
    assert.equal(await PricingReferenceModel.countDocuments(), 0);
  }
  const conflicting = await request(app).post(endpoint + '/import').set(admin)
    .send({ csv: csv(observation, { ...observation, quotedAmount: '70' }), confirmed: true });
  assert.equal(conflicting.status, 400);
  await request(app).post(endpoint + '/import').set(admin).send({ csv: csv(observation), confirmed: true });
  const existingConflict = await request(app).post(endpoint + '/import').set(admin)
    .send({ csv: csv({ ...observation, quotedAmount: '70' }), confirmed: true });
  assert.equal(existingConflict.status, 400);
  assert.equal((await PricingReferenceModel.findOne()).quotedAmount, 65);
});

test('references reach fitted-feature inputs without becoming completed rentals; other domains and inactive/stale references are excluded', async () => {
  await request(app).post(endpoint + '/import').set(admin).send({ csv: csv(observation,
    { ...observation, category: 'Vehicles', subcategory: 'Cars', brand: 'Toyota', model: 'Camry', sourceUrl: 'https://example.com/car', quotedAmount: '500' },
    { ...observation, model: 'EOS R6', sourceUrl: 'https://example.com/old', observedDate: '2020-01-01' },
    { ...observation, subcategory: 'Smartphones', brand: 'Apple', model: 'iPhone 14', sourceUrl: 'https://example.com/phone' }), confirmed: true });
  let received;
  aiClient.recommendPrice = async (input) => { received = input; return { available: true, suggested_daily_price: 65, evidence: input.market_evidence }; };
  const payload = { itemProfile: { category: 'Devices', subcategory: 'Cameras', condition: 'Excellent', brand: 'Canon', product_model: 'EOS R50', item_age_years: 3 }, rentalDurationDays: 1 };
  const price = await request(app).post('/api/v1/listings/price-recommendation').set(owner).send(payload);
  assert.equal(price.status, 200);
  assert.equal(received.market_evidence.comparable_active_count, 1);
  assert.equal(received.market_evidence.external_asking_price_count, 1);
  assert.equal(received.market_evidence.marketplace_active_listing_count, 0);
  assert.equal(received.market_evidence.historical_rental_count, 0);
  assert.equal(received.market_evidence.marketplace_completed_rental_count, 0);
  assert.equal(received.item_profile.item_age_years, 3);
  assert.equal(received.market_evidence.comparable_active_median, 65);
  const list = await request(app).get(endpoint).set(admin);
  const item = list.body.data.items.find((row) => row.productModel === 'EOS R50');
  assert.equal((await request(app).patch(`${endpoint}/${item.publicId}/deactivate`).set(admin).send({ confirmed: true })).status, 200);
  await request(app).post('/api/v1/listings/price-recommendation').set(owner).send(payload);
  assert.equal(received.market_evidence.comparable_active_count, 0);
  assert.equal(await BookingModel.countDocuments(), 0);
  assert.equal(await adminModule.Model.countDocuments({ action: 'pricing_reference.deactivated' }), 1);
});
