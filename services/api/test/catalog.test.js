import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import {
  catalogProvider,
  rankCatalogProviderItems,
} from '../src/modules/catalog/catalog.provider.js';
import {
  catalogService,
  normalizeCatalogText,
  resolveProductIdentity,
} from '../src/modules/catalog/catalog.service.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

const ownerHeaders = {
  'x-user-id': 'u-catalog-owner',
  'x-user-email': 'catalog-owner@renthub.my',
  'x-user-name': 'Catalog Owner',
  'x-user-roles': 'owner',
};

let mongodb;
let originalSearch;

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([ProductCatalogModel.init(), UserModel.init()]);
  originalSearch = catalogProvider.search;
});

beforeEach(async () => {
  await Promise.all([
    ProductCatalogModel.deleteMany({}),
    UserModel.deleteMany({}),
  ]);
  catalogProvider.search = originalSearch;
  await request(app).post('/api/v1/users/session').set(ownerHeaders);
});

after(async () => {
  catalogProvider.search = originalSearch;
  await disconnectDatabase();
  await mongodb.stop();
});

test('caches catalog brand and model selections with canonical identity', async () => {
  catalogProvider.search = async ({ entityType }) => entityType === 'brand'
    ? [{ id: 'QBRAND', label: 'Giant', source: 'wikidata', aliases: [] }]
    : [{ id: 'QMODEL', label: 'Talon 2', source: 'wikidata', aliases: ['Talon-2'] }];

  const brandResponse = await request(app)
    .get('/api/v1/catalog/brands?category=Vehicles&subcategory=Bicycles&query=Giant')
    .set(ownerHeaders);
  assert.equal(brandResponse.status, 200);
  assert.equal(brandResponse.body.data[0].brand, 'Giant');
  assert.equal(brandResponse.body.data[0].queryMatch, 'exact');
  const brandId = brandResponse.body.data[0].catalogBrandId;

  const modelResponse = await request(app)
    .get(`/api/v1/catalog/models?category=Vehicles&subcategory=Bicycles&brand=Giant&query=Talon%202&catalogBrandId=${encodeURIComponent(brandId)}`)
    .set(ownerHeaders);
  assert.equal(modelResponse.status, 200);
  assert.equal(modelResponse.body.data[0].model, 'Talon 2');
  assert.equal(modelResponse.body.data[0].canonicalProductId, 'wikidata:QMODEL');

  const identity = await resolveProductIdentity({
    category: 'Vehicles',
    subcategory: 'Bicycles',
    brand: 'GIANT',
    productModel: 'talon2',
    canonicalProductId: 'wikidata:QMODEL',
    productMatchType: 'fuzzy_catalog_match',
  });
  assert.equal(identity.brand, 'Giant');
  assert.equal(identity.model, 'Talon 2');
  assert.equal(identity.productMatchType, 'fuzzy_catalog_match');
});

test('uses stale MongoDB cache when the external catalog is unavailable', async () => {
  await ProductCatalogModel.create({
    entityType: 'brand',
    catalogEntityId: 'wikidata:QCACHED',
    canonicalBrandId: 'wikidata:QCACHED',
    category: 'Vehicles',
    subcategory: 'Bicycles',
    brand: 'Giant',
    model: '',
    normalizedBrand: 'giant',
    normalizedModel: '',
    aliases: ['Giant Bicycles'],
    source: 'wikidata',
    description: 'Cached bicycle brand',
    lastSyncedAt: new Date('2020-01-01T00:00:00Z'),
  });
  catalogProvider.search = async () => {
    throw new Error('provider offline');
  };

  const result = await catalogService.brands({
    category: 'Vehicles',
    subcategory: 'Bicycles',
    query: 'Giant',
  });
  assert.equal(result.items[0].brand, 'Giant');
  assert.equal(result.provider, 'mongodb-cache');
  assert.equal(result.providerAvailable, false);
  assert.equal(result.stale, true);
});

test('keeps unknown products as manual entries instead of rejecting them', async () => {
  const identity = await resolveProductIdentity({
    category: 'Vehicles',
    subcategory: 'Bicycles',
    brand: 'CustomBike',
    productModel: 'X200',
  });
  assert.deepEqual(identity, {
    brand: 'CustomBike',
    model: 'X200',
    canonicalProductId: null,
    catalogBrandId: null,
    productMatchType: 'manual_entry',
    catalogSource: null,
  });
});

test('maps Vehicles and Cars to case-insensitive Toyota make and model records', async () => {
  assert.equal(normalizeCatalogText('  TOYOTA  '), 'toyota');
  catalogProvider.search = async ({ entityType, query }) => {
    if (entityType === 'brand') {
      return [{
        id: 'Q53268',
        label: 'Toyota',
        source: 'wikidata',
        description: 'Japanese multinational automotive manufacturer',
        aliases: ['Toyota Motor Corporation'],
      }];
    }
    return [{
      id: query.toLowerCase() === 'camry' ? 'QCAMRY' : 'QCOROLLA',
      label: `Toyota ${query[0].toUpperCase()}${query.slice(1).toLowerCase()}`,
      source: 'wikidata',
      description: 'automobile model series produced by Toyota',
      aliases: [],
    }];
  };

  const brandResponse = await request(app)
    .get('/api/v1/catalog/brands?category=Vehicles&subcategory=Cars&query=toyota')
    .set(ownerHeaders);
  assert.equal(brandResponse.status, 200);
  assert.equal(brandResponse.body.data[0].brand, 'Toyota');
  assert.equal(brandResponse.body.data[0].queryMatch, 'exact');
  const brandId = brandResponse.body.data[0].catalogBrandId;

  for (const model of ['Corolla', 'Camry']) {
    const response = await request(app)
      .get(`/api/v1/catalog/models?category=Vehicles&subcategory=Cars&brand=Toyota&query=${model}&catalogBrandId=${encodeURIComponent(brandId)}`)
      .set(ownerHeaders);
    assert.equal(response.status, 200);
    assert.equal(response.body.data[0].brand, 'Toyota');
    assert.equal(response.body.data[0].model, `Toyota ${model}`);
  }

  const cachedToyota = await ProductCatalogModel.find({
    category: 'Vehicles',
    subcategory: 'Cars',
    normalizedBrand: 'toyota',
  }).lean();
  assert.equal(cachedToyota.length, 3);
});

test('ranks generic automotive manufacturers above same-name places', () => {
  const ranked = rankCatalogProviderItems([
    {
      id: 'QCITY',
      label: 'Acme',
      description: 'city in an administrative region',
      aliases: [],
    },
    {
      id: 'QMAKE',
      label: 'Acme',
      description: 'automotive manufacturer and vehicle brand',
      aliases: [],
    },
  ], {
    entityType: 'brand',
    category: 'Vehicles',
    subcategory: 'Cars',
    query: 'acme',
  });
  assert.equal(ranked[0].id, 'QMAKE');
});

test('returns catalog unavailable instead of converting provider errors to no match', async () => {
  catalogProvider.search = async () => {
    throw new Error('provider offline');
  };
  const response = await request(app)
    .get('/api/v1/catalog/brands?category=Vehicles&subcategory=Cars&query=toyota')
    .set(ownerHeaders);
  assert.equal(response.status, 503);
  assert.equal(response.body.error.code, 'CATALOG_UNAVAILABLE');
});
