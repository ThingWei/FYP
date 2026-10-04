import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

const enabled = process.env.RUN_CATALOG_E2E === 'true';
let mongodb;

const ownerHeaders = {
  'x-user-id': 'u-live-catalog-owner',
  'x-user-email': 'live-catalog-owner@renthub.my',
  'x-user-name': 'Live Catalog Owner',
  'x-user-roles': 'owner',
};

before(async () => {
  if (!enabled) return;
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([ProductCatalogModel.init(), UserModel.init()]);
  await request(app).post('/api/v1/users/session').set(ownerHeaders);
});

after(async () => {
  if (!enabled) return;
  await disconnectDatabase();
  await mongodb.stop();
});

test('live Wikidata supports Vehicles Cars Toyota and common models', {
  skip: !enabled,
}, async () => {
  const brandResponse = await request(app)
    .get('/api/v1/catalog/brands?category=Vehicles&subcategory=Cars&query=toyota')
    .set(ownerHeaders);
  assert.equal(brandResponse.status, 200);
  const toyota = brandResponse.body.data.find((item) =>
    item.brand.toLowerCase() === 'toyota' &&
    item.description.toLowerCase().includes('automotive'));
  assert.ok(toyota, 'Toyota automotive manufacturer was not returned');

  for (const model of ['Corolla', 'Camry', 'Vios', 'Hilux']) {
    const response = await request(app)
      .get(`/api/v1/catalog/models?category=Vehicles&subcategory=Cars&brand=Toyota&query=${model}&catalogBrandId=${encodeURIComponent(toyota.catalogBrandId)}`)
      .set(ownerHeaders);
    assert.equal(response.status, 200);
    assert.ok(
      response.body.data.some((item) =>
        `${item.model} ${item.description}`.toLowerCase().includes(model.toLowerCase())),
      `${model} was not returned by the live provider`,
    );
  }

  const cachedToyota = await ProductCatalogModel.countDocuments({
    category: 'Vehicles',
    subcategory: 'Cars',
    normalizedBrand: 'toyota',
  });
  assert.ok(cachedToyota >= 5);
});
