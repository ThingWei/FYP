import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

const enabled = process.env.RUN_AI_E2E === 'true';
let mongodb;

const ownerHeaders = {
  'x-user-id': 'u-price-e2e-owner',
  'x-user-email': 'price-e2e@renthub.my',
  'x-user-name': 'Pricing Owner',
  'x-user-roles': 'owner',
};

before(async () => {
  if (!enabled) return;
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    ProductCatalogModel.init(),
    ListingModel.init(),
    UserModel.init(),
  ]);
});

beforeEach(async () => {
  if (!enabled) return;
  await Promise.all([
    ProductCatalogModel.deleteMany({}),
    ListingModel.deleteMany({}),
    UserModel.deleteMany({}),
  ]);
});

after(async () => {
  if (!enabled) return;
  await disconnectDatabase();
  await mongodb.stop();
});

test('catalog identity and Mongo evidence reach real XGBoost inference', {
  skip: !enabled,
}, async () => {
  await request(app).post('/api/v1/users/session').set(ownerHeaders);
  await ProductCatalogModel.create({
    entityType: 'product',
    catalogEntityId: 'wikidata:QGIANTTALON2',
    canonicalProductId: 'wikidata:QGIANTTALON2',
    canonicalBrandId: 'wikidata:QGIANT',
    category: 'Vehicles',
    subcategory: 'Bicycles',
    brand: 'Giant',
    model: 'Talon 2',
    normalizedBrand: 'giant',
    normalizedModel: 'talon 2',
    source: 'wikidata',
    lastSyncedAt: new Date(),
  });
  await ListingModel.create([
    {
      publicId: 'l-e2e-bike-1',
      ownerId: 'u-market-1',
      ownerName: 'Market Owner 1',
      title: 'Giant Talon 2 Mountain Bike',
      category: 'Vehicles',
      subcategory: 'Bicycles',
      listingType: 'physical',
      brand: 'Giant',
      productModel: 'Talon 2',
      canonicalProductId: 'wikidata:QGIANTTALON2',
      catalogBrandId: 'wikidata:QGIANT',
      productMatchType: 'exact_catalog_match',
      catalogSource: 'wikidata',
      condition: 'Excellent',
      itemAgeYears: 1,
      fulfilmentMethods: ['pickup'],
      location: 'Kuala Lumpur',
      state: 'Kuala Lumpur',
      dailyPrice: 72,
      status: 'active',
    },
    {
      publicId: 'l-e2e-bike-2',
      ownerId: 'u-market-2',
      ownerName: 'Market Owner 2',
      title: 'Giant Talon 2 Trail Bike',
      category: 'Vehicles',
      subcategory: 'Bicycles',
      listingType: 'physical',
      brand: 'Giant',
      productModel: 'Talon 2',
      canonicalProductId: 'wikidata:QGIANTTALON2',
      catalogBrandId: 'wikidata:QGIANT',
      productMatchType: 'exact_catalog_match',
      catalogSource: 'wikidata',
      condition: 'Excellent',
      itemAgeYears: 1.5,
      fulfilmentMethods: ['pickup'],
      location: 'Petaling Jaya, Selangor',
      state: 'Selangor',
      dailyPrice: 78,
      status: 'active',
    },
  ]);

  const response = await request(app)
    .post('/api/v1/listings/price-recommendation')
    .set(ownerHeaders)
    .send({
      itemProfile: {
        category: 'Vehicles',
        subcategory: 'Bicycles',
        condition: 'Excellent',
        brand: 'Giant',
        product_model: 'Talon 2',
        canonicalProductId: 'wikidata:QGIANTTALON2',
        catalogBrandId: 'wikidata:QGIANT',
        productMatchType: 'exact_catalog_match',
        catalogSource: 'wikidata',
        item_age_years: 1,
        location: 'Kuala Lumpur',
        state: 'Kuala Lumpur',
      },
      rentalDurationDays: 1,
    });

  assert.equal(response.status, 200);
  assert.equal(response.body.data.available, true);
  assert.match(response.body.data.model_source, /xgboost/);
  assert.equal(response.body.data.product_match.type, 'exact_catalog_match');
  assert.equal(response.body.data.evidence.exact_active_count, 2);
  assert.equal(response.body.data.evidence.active_comparable_tier, 'exact_canonical_city');
  assert.ok(response.body.data.suggested_daily_price > 0);
  assert.ok(response.body.data.lower_bound <= response.body.data.suggested_daily_price);
  assert.ok(response.body.data.upper_bound >= response.body.data.suggested_daily_price);
  if (process.env.E2E_REPORT === 'true') {
    console.log(JSON.stringify({
      suggestedDailyPrice: response.body.data.suggested_daily_price,
      range: [response.body.data.lower_bound, response.body.data.upper_bound],
      confidence: response.body.data.confidence,
      confidenceLabel: response.body.data.confidence_label,
      modelSource: response.body.data.model_source,
      productMatch: response.body.data.product_match,
      evidence: response.body.data.evidence,
      explanation: response.body.data.explanation,
    }));
  }
});
