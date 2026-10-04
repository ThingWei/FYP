import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import {
  catalogProvider,
  catalogProviderStrategy,
  isValidWikidataFallback,
  rankCatalogProviderItems,
} from '../src/modules/catalog/catalog.provider.js';
import { CATALOG_COVERAGE } from '../src/modules/catalog/catalog.coverage.js';
import {
  CURATED_CATALOG,
  searchCuratedCatalog,
} from '../src/modules/catalog/catalog.curated.js';
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

test('a generic fallback cache does not override a domain provider', async () => {
  await ProductCatalogModel.create({
    entityType: 'brand',
    catalogEntityId: 'wikidata:QOLD',
    canonicalBrandId: 'wikidata:QOLD',
    category: 'Vehicles',
    subcategory: 'Cars',
    brand: 'Toyota place',
    model: '',
    normalizedBrand: 'toyota',
    normalizedModel: '',
    aliases: ['Toyota'],
    source: 'wikidata',
    description: 'Old generic fallback record',
    lastSyncedAt: new Date(),
  });
  catalogProvider.search = async () => [{
    id: '448',
    label: 'Toyota',
    source: 'nhtsa-vpic',
    description: 'Vehicle make listed in NHTSA vPIC',
    aliases: [],
  }];
  const result = await catalogService.brands({
    category: 'Vehicles', subcategory: 'Cars', query: 'toyota',
  });
  assert.equal(result.provider, 'nhtsa-vpic');
  assert.equal(result.items[0].brand, 'Toyota');
  assert.equal(result.items[0].catalogSource, 'nhtsa-vpic');
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

test('maps supported subcategories to product-domain providers', () => {
  assert.equal(catalogProviderStrategy({
    category: 'Vehicles', subcategory: 'Cars',
  }), 'nhtsa-vpic');
  assert.equal(catalogProviderStrategy({
    category: 'Devices', subcategory: 'Smartphones',
  }), 'wikidata-smartphones');
  assert.equal(catalogProviderStrategy({
    category: 'Books', subcategory: 'Fiction',
  }), 'openlibrary');
  assert.equal(catalogProviderStrategy({
    category: 'Devices', subcategory: 'Cameras',
  }), 'renthub-curated');
});

test('coverage matrix and curated identities cover every listing subcategory', () => {
  assert.equal(CATALOG_COVERAGE.length, 22);
  assert.deepEqual(
    new Set(CATALOG_COVERAGE.map((entry) =>
      `${entry.category}:${entry.subcategory}`)),
    new Set(CURATED_CATALOG.map((entry) =>
      `${entry.category}:${entry.subcategory}`)),
  );
  for (const entry of CURATED_CATALOG) {
    const brandResults = searchCuratedCatalog({
      entityType: 'brand',
      category: entry.category,
      subcategory: entry.subcategory,
      query: entry.brand.slice(0, 3),
    });
    assert.equal(brandResults[0]?.label, entry.brand,
      `Missing brand for ${entry.category} -> ${entry.subcategory}`);
    const modelResults = searchCuratedCatalog({
      entityType: 'product',
      category: entry.category,
      subcategory: entry.subcategory,
      brand: entry.brand,
      catalogBrandId: `renthub-curated:${brandResults[0].id}`,
      query: '',
    });
    assert.equal(modelResults[0]?.label, entry.models[0],
      `Missing model for ${entry.category} -> ${entry.subcategory}`);
    assert.equal(modelResults[0]?.specifications.curated, true);
  }
});

test('curated Audio catalog resolves JBL products through generic lookup', () => {
  const brands = searchCuratedCatalog({
    entityType: 'brand',
    category: 'Devices',
    subcategory: 'Audio',
    query: 'jbl',
  });
  assert.equal(brands[0]?.label, 'JBL');
  const models = searchCuratedCatalog({
    entityType: 'product',
    category: 'Devices',
    subcategory: 'Audio',
    brand: 'JBL',
    catalogBrandId: `renthub-curated:${brands[0].id}`,
    query: '',
  });
  assert.deepEqual(
    models.slice(0, 3).map((item) => item.label),
    ['Charge 5', 'Flip 6', 'PartyBox 310'],
  );
});

test('external failure falls through to curated identity results', {
  concurrency: false,
}, async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => {
    throw new Error('provider offline');
  };
  try {
    const result = await catalogProvider.search({
      entityType: 'brand',
      category: 'Devices',
      subcategory: 'Smartphones',
      query: 'appl',
    });
    assert.equal(result.provider, 'renthub-curated');
    assert.equal(result.items[0].label, 'Apple');
  } finally {
    global.fetch = originalFetch;
  }
});

test('provider router returns a brand and model for every coverage row', {
  concurrency: false,
}, async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => {
    throw new Error('external provider intentionally unavailable');
  };
  try {
    for (const entry of CURATED_CATALOG) {
      const brandResult = await catalogProvider.search({
        entityType: 'brand',
        category: entry.category,
        subcategory: entry.subcategory,
        query: entry.brand.slice(0, 3),
      });
      const brand = brandResult.items.find((item) => item.label === entry.brand);
      assert.ok(brand,
        `Provider chain missed ${entry.category} -> ${entry.subcategory} brand`);
      const modelResult = await catalogProvider.search({
        entityType: 'product',
        category: entry.category,
        subcategory: entry.subcategory,
        brand: entry.brand,
        catalogBrandId: `${brand.source}:${brand.id}`,
        query: '',
      });
      assert.equal(modelResult.items[0]?.label, entry.models[0],
        `Provider chain missed ${entry.category} -> ${entry.subcategory} model`);
    }
  } finally {
    global.fetch = originalFetch;
  }
});

test('distinguishes an unavailable provider chain from a successful no-match', {
  concurrency: false,
}, async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => {
    throw new Error('catalog network unavailable');
  };
  try {
    await assert.rejects(
      catalogProvider.search({
        entityType: 'brand',
        category: 'Devices',
        subcategory: 'Smartphones',
        query: 'unknown-maker-with-no-curated-match',
      }),
      /could not determine a reliable no-match/,
    );
  } finally {
    global.fetch = originalFetch;
  }
});

test('rejects software and journals from a smartphone brand fallback', () => {
  const context = {
    entityType: 'brand',
    category: 'Devices',
    subcategory: 'Smartphones',
    query: 'appl',
  };
  for (const item of [
    { label: 'Apple Music', description: 'music streaming service' },
    { label: 'application software', description: 'computer software' },
    { label: 'Applied Physics Letters', description: 'scientific journal' },
    { label: 'Applied and Environmental Microbiology', description: 'academic journal' },
  ]) {
    assert.equal(isValidWikidataFallback(item, context), false);
  }
  assert.equal(isValidWikidataFallback({
    label: 'Example Mobile',
    description: 'smartphone manufacturer and electronics company',
  }, context), true);
});

test('smartphone provider constrains Apple brands and preloaded models', {
  concurrency: false,
}, async () => {
  const originalFetch = global.fetch;
  global.fetch = async (url) => {
    const query = new URL(url).searchParams.get('query');
    const isBrand = query.includes('?manufacturer');
    return {
      ok: true,
      json: async () => ({
        results: {
          bindings: isBrand
            ? [{
                manufacturer: { value: 'http://www.wikidata.org/entity/Q312' },
                manufacturerLabel: { value: 'Apple Inc.' },
              }]
            : [
                {
                  model: { value: 'http://www.wikidata.org/entity/Q96608989' },
                  modelLabel: { value: 'iPhone 12' },
                },
                {
                  model: { value: 'http://www.wikidata.org/entity/Q122442399' },
                  modelLabel: { value: 'iPhone 15 Pro' },
                },
              ],
        },
      }),
    };
  };
  try {
    const brand = await catalogProvider.search({
      entityType: 'brand', category: 'Devices', subcategory: 'Smartphones',
      query: 'appl',
    });
    assert.equal(brand.provider, 'wikidata-smartphones');
    assert.deepEqual(brand.items.map((item) => item.label), ['Apple']);
    const models = await catalogProvider.search({
      entityType: 'product', category: 'Devices', subcategory: 'Smartphones',
      brand: 'Apple', catalogBrandId: 'wikidata-smartphones:Q312', query: '',
    });
    assert.deepEqual(models.items.map((item) => item.label), [
      'iPhone 12', 'iPhone 15 Pro',
    ]);
  } finally {
    global.fetch = originalFetch;
  }
});

test('vehicle provider retrieves models using the selected canonical make', {
  concurrency: false,
}, async () => {
  const originalFetch = global.fetch;
  global.fetch = async (url) => {
    const path = new URL(url).pathname;
    return {
      ok: true,
      json: async () => path.includes('GetMakesForVehicleType')
        ? { Results: [{ MakeId: 448, MakeName: 'TOYOTA' }] }
        : {
            Results: [
              { Make_ID: 448, Make_Name: 'TOYOTA', Model_ID: 2208, Model_Name: 'Camry' },
              { Make_ID: 448, Make_Name: 'TOYOTA', Model_ID: 2209, Model_Name: 'Corolla' },
            ],
          },
    };
  };
  try {
    const brand = await catalogProvider.search({
      entityType: 'brand', category: 'Vehicles', subcategory: 'Cars', query: 'toyota',
    });
    assert.equal(brand.items[0].label, 'Toyota');
    const models = await catalogProvider.search({
      entityType: 'product', category: 'Vehicles', subcategory: 'Cars',
      brand: 'Toyota', catalogBrandId: 'nhtsa-vpic:448', query: '',
    });
    assert.deepEqual(models.items.map((item) => item.label), ['Camry', 'Corolla']);
  } finally {
    global.fetch = originalFetch;
  }
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

test('allows a first page of models to preload without a text query', async () => {
  catalogProvider.search = async () => [{
    id: '448:2208',
    label: 'Camry',
    source: 'nhtsa-vpic',
    description: 'Toyota vehicle model',
    aliases: [],
  }];
  const response = await request(app)
    .get('/api/v1/catalog/models?category=Vehicles&subcategory=Cars&brand=Toyota&catalogBrandId=nhtsa-vpic%3A448')
    .set(ownerHeaders);
  assert.equal(response.status, 200);
  assert.equal(response.body.data[0].model, 'Camry');
  assert.equal(response.body.data[0].brand, 'Toyota');
});

test('normalizes and caches curated category results through Express', async () => {
  catalogProvider.search = originalSearch;
  const brandResponse = await request(app)
    .get('/api/v1/catalog/brands?category=Devices&subcategory=Cameras&query=canon')
    .set(ownerHeaders);
  assert.equal(brandResponse.status, 200);
  assert.equal(brandResponse.body.data[0].brand, 'Canon');
  assert.equal(brandResponse.body.data[0].catalogSource, 'renthub-curated');
  const brandId = brandResponse.body.data[0].catalogBrandId;
  const modelResponse = await request(app)
    .get(`/api/v1/catalog/models?category=Devices&subcategory=Cameras&brand=Canon&catalogBrandId=${encodeURIComponent(brandId)}`)
    .set(ownerHeaders);
  assert.equal(modelResponse.status, 200);
  assert.equal(modelResponse.body.data[0].model, 'EOS R6 Mark II');
  assert.equal(modelResponse.body.data[0].specifications.curated, true);
  assert.equal(await ProductCatalogModel.countDocuments({
    category: 'Devices',
    subcategory: 'Cameras',
    source: 'renthub-curated',
  }), 3);
});
