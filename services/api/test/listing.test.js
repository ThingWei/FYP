import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { AvailabilityModel } from '../src/modules/listing/availability.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { uploadService } from '../src/modules/upload/upload.service.js';
import { env } from '../src/config/env.js';

let mongodb;

const ownerHeaders = {
  'x-user-id': 'u-owner',
  'x-user-email': 'owner@renthub.my',
  'x-user-name': 'Sarah J.',
  'x-user-roles': 'owner',
};
const renterHeaders = {
  'x-user-id': 'u-renter',
  'x-user-email': 'renter@renthub.my',
  'x-user-name': 'Alex Tan',
  'x-user-roles': 'renter',
};
const adminHeaders = {
  'x-user-id': 'u-admin',
  'x-user-email': 'admin@renthub.my',
  'x-user-name': 'Admin Farah',
  'x-user-roles': 'admin',
};

const cameraInput = {
  title: 'Sony Alpha a7S III Mirrorless Camera',
  description: 'Professional full-frame camera kit.',
  category: 'Devices',
  listingType: 'physical',
  dailyPrice: 85,
  condition: 'Excellent',
  securityDeposit: 300,
  fulfilmentMethods: ['pickup', 'owner_delivery'],
  location: 'Bukit Bintang, Kuala Lumpur',
  state: 'Kuala Lumpur',
  images: [
    'local://listing/camera-front.jpg',
    'local://listing/camera-back.jpg',
    'local://listing/camera-side.jpg',
  ],
};

async function startOwner() {
  return request(app).post('/api/v1/users/session').set(ownerHeaders);
}

async function activeListing(overrides = {}) {
  return ListingModel.create({
    publicId: `l-${new ListingModel()._id}`,
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    title: 'Sony Alpha Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 85,
    condition: 'Excellent',
    securityDeposit: 300,
    fulfilmentMethods: ['pickup'],
    location: 'Bukit Bintang, Kuala Lumpur',
    verified: true,
    status: 'active',
    ...overrides,
  });
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    AvailabilityModel.init(),
    ProductCatalogModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    AvailabilityModel.deleteMany({}),
    ProductCatalogModel.deleteMany({}),
  ]);
});

test('persists only a server-verified canonical product identity', async () => {
  await startOwner();
  await ProductCatalogModel.create({
    entityType: 'product',
    catalogEntityId: 'wikidata:QCAMERA',
    canonicalProductId: 'wikidata:QCAMERA',
    canonicalBrandId: 'wikidata:QSONY',
    category: 'Devices',
    subcategory: 'Cameras',
    brand: 'Sony',
    model: 'Alpha a7S III',
    normalizedBrand: 'sony',
    normalizedModel: 'alpha a7s iii',
    source: 'wikidata',
    lastSyncedAt: new Date(),
  });

  const response = await request(app)
    .post('/api/v1/listings')
    .set(ownerHeaders)
    .send({
      ...cameraInput,
      subcategory: 'Cameras',
      brand: 'SONY',
      productModel: 'Alpha a7S III',
      canonicalProductId: 'wikidata:QCAMERA',
      catalogBrandId: 'wikidata:QSONY',
      productMatchType: 'exact_catalog_match',
      catalogSource: 'untrusted-client-value',
    });

  assert.equal(response.status, 201);
  assert.equal(response.body.data.brand, 'Sony');
  assert.equal(response.body.data.canonicalProductId, 'wikidata:QCAMERA');
  assert.equal(response.body.data.catalogBrandId, 'wikidata:QSONY');
  assert.equal(response.body.data.productMatchType, 'exact_catalog_match');
  assert.equal(response.body.data.catalogSource, 'wikidata');
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('only an Owner can create strict physical and service drafts', async () => {
  await startOwner();

  const forbidden = await request(app)
    .post('/api/v1/listings')
    .set(adminHeaders)
    .send(cameraInput);
  assert.equal(forbidden.status, 403);

  const camera = await request(app)
    .post('/api/v1/listings')
    .set(ownerHeaders)
    .send(cameraInput);
  assert.equal(camera.status, 201);
  assert.equal(camera.body.data.id.startsWith('l-'), true);
  assert.equal(camera.body.data.ownerName, 'Sarah J.');
  assert.equal(camera.body.data.status, 'draft');
  assert.equal(camera.body.data.isService, false);
  assert.equal(camera.body.data._id, undefined);

  const invalidService = await request(app)
    .post('/api/v1/listings')
    .set(ownerHeaders)
    .send({
      title: 'Event Photography',
      category: 'Services',
      listingType: 'service',
      dailyPrice: 450,
      location: 'Kuala Lumpur',
    });
  assert.equal(invalidService.status, 422);

  const service = await request(app)
    .post('/api/v1/listings')
    .set(ownerHeaders)
    .send({
      title: 'Event Photography Package',
      category: 'Services',
      listingType: 'service',
      dailyPrice: 450,
      priceUnit: 'package',
      location: 'Kuala Lumpur',
      serviceDetails: {
        packageName: 'Essential Event Coverage',
        durationMinutes: 180,
        venueMode: 'renter_location',
      },
    });
  assert.equal(service.status, 201);
  assert.equal(service.body.data.isService, true);
  assert.equal(service.body.data.condition, undefined);
  assert.equal(service.body.data.securityDeposit, 0);
});

test('builds an AI price request from marketplace data without a current price', async () => {
  await startOwner();
  await activeListing({
    publicId: 'l-price-comparable',
    dailyPrice: 90,
    state: 'Kuala Lumpur',
    subcategory: 'Cameras',
    brand: 'Sony',
    productModel: 'Alpha a7S III',
  });
  const original = aiClient.recommendPrice;
  let received;
  aiClient.recommendPrice = async (payload) => {
    received = payload;
    return {
      available: true,
      suggested_daily_price: 88,
      lower_bound: 82,
      upper_bound: 94,
      confidence: 0.9,
      confidence_label: 'high',
      model_source: 'global_xgboost',
      explanation: [],
      evidence: payload.market_evidence,
    };
  };
  try {
    const response = await request(app)
      .post('/api/v1/listings/price-recommendation')
      .set(ownerHeaders)
      .send({
        itemProfile: {
          category: 'Devices',
          subcategory: 'Cameras',
          condition: 'Excellent',
          brand: 'Sony',
          product_model: 'Alpha a7S III',
          state: 'Kuala Lumpur',
          item_age_years: 2,
        },
        rentalDurationDays: 3,
        marketEvidence: { comparable_active_mean: 99999 },
        supplyDemandRatio: 999,
      });

    assert.equal(response.status, 200);
    assert.equal(response.body.data.suggested_daily_price, 88);
    assert.equal(received.schema_version, 'renthub-price-v2');
    assert.equal(received.market_evidence.comparable_active_mean, 90);
    assert.notEqual(received.market_evidence.comparable_active_mean, 99999);
    assert.equal(received.market_evidence.historical_rental_count, 0);
    assert.equal(received.owner_trust_score, 50);
    assert.equal(received.rental_duration_days, 3);
    assert.equal(received.item_profile.item_age_years, 2);
    assert.equal(received.market_evidence.active_comparable_tier, 'exact_product_malaysia');
    assert.equal(received.market_evidence.exact_active_count, 1);
  } finally {
    aiClient.recommendPrice = original;
  }
});

test('uses a labelled statistical fallback only with sufficient database evidence', async () => {
  await startOwner();
  await Promise.all([
    activeListing({ publicId: 'l-stat-1', dailyPrice: 60 }),
    activeListing({ publicId: 'l-stat-2', dailyPrice: 80 }),
    activeListing({ publicId: 'l-stat-3', dailyPrice: 100 }),
    activeListing({ publicId: 'l-stat-4', dailyPrice: 120 }),
  ]);
  const original = aiClient.recommendPrice;
  aiClient.recommendPrice = async (payload) => ({
    available: false,
    confidence: 0,
    confidence_label: 'low',
    adapter: 'xgboost-v2',
    model_source: 'unavailable',
    explanation: [],
    warnings: ['artifact missing'],
    evidence: payload.market_evidence,
    error: 'artifact missing',
  });
  try {
    const response = await request(app)
      .post('/api/v1/listings/price-recommendation')
      .set(ownerHeaders)
      .send({
        itemProfile: {
          category: 'Devices',
          subcategory: 'Cameras',
          condition: 'Excellent',
          brand: 'Sony',
          product_model: 'Alpha a7S III',
          state: 'Kuala Lumpur',
          item_age_years: 1,
        },
        rentalDurationDays: 1,
      });

    assert.equal(response.status, 200);
    assert.equal(response.body.data.suggested_daily_price, 90);
    assert.equal(response.body.data.lower_bound, 75);
    assert.equal(response.body.data.upper_bound, 105);
    assert.equal(response.body.data.model_source, 'active_listing_median');
    assert.match(response.body.data.warnings[0], /not an AI prediction/i);
  } finally {
    aiClient.recommendPrice = original;
  }
});

test('only excludes the requesting Owner listing from comparable evidence', async () => {
  await startOwner();
  await Promise.all([
    activeListing({ publicId: 'l-owned-edit', dailyPrice: 70 }),
    activeListing({
      publicId: 'l-another-owner',
      ownerId: 'u-another-owner',
      ownerName: 'Another Owner',
      dailyPrice: 120,
    }),
  ]);
  const original = aiClient.recommendPrice;
  const received = [];
  aiClient.recommendPrice = async (payload) => {
    received.push(payload.market_evidence);
    return {
      available: false,
      confidence: 0,
      confidence_label: 'low',
      adapter: 'xgboost-v2',
      model_source: 'unavailable',
      warnings: [],
      evidence: payload.market_evidence,
    };
  };
  const requestBody = {
    itemProfile: {
      category: 'Devices',
      condition: 'Excellent',
      state: 'Kuala Lumpur',
    },
  };
  try {
    await request(app)
      .post('/api/v1/listings/price-recommendation')
      .set(ownerHeaders)
      .send({ ...requestBody, excludeListingId: 'l-owned-edit' });
    await request(app)
      .post('/api/v1/listings/price-recommendation')
      .set(ownerHeaders)
      .send({ ...requestBody, excludeListingId: 'l-another-owner' });

    assert.equal(received[0].comparable_active_count, 1);
    assert.equal(received[0].comparable_active_mean, 120);
    assert.equal(received[1].comparable_active_count, 2);
    assert.equal(received[1].comparable_active_mean, 95);
  } finally {
    aiClient.recommendPrice = original;
  }
});

test('enforces owner submission and administrator moderation transitions', async () => {
  await startOwner();
  await UserModel.updateOne({ authId: 'u-owner' }, { $set: {
    'verification.status': 'approved', 'verification.documentType': 'mykad',
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
  } });
  const created = await request(app)
    .post('/api/v1/listings')
    .set(ownerHeaders)
    .send(cameraInput);
  const id = created.body.data.id;

  const submitted = await request(app)
    .post(`/api/v1/listings/${id}/submit`)
    .set(ownerHeaders);
  assert.equal(submitted.status, 200);
  assert.equal(submitted.body.data.status, 'pending_review');

  const renterCannotViewQueue = await request(app)
    .get('/api/v1/listings/admin')
    .set(renterHeaders);
  assert.equal(renterCannotViewQueue.status, 403);

  const moderationQueue = await request(app)
    .get('/api/v1/listings/admin?status=pending_review')
    .set(adminHeaders);
  assert.equal(moderationQueue.status, 200);
  assert.equal(moderationQueue.body.data.length, 1);
  assert.equal(moderationQueue.body.data[0].id, id);
  assert.equal(moderationQueue.body.meta.total, 1);

  const editDuringReview = await request(app)
    .patch(`/api/v1/listings/${id}`)
    .set(ownerHeaders)
    .send({ dailyPrice: 90 });
  assert.equal(editDuringReview.status, 409);

  const approved = await request(app)
    .patch(`/api/v1/listings/${id}/moderation`)
    .set(adminHeaders)
    .send({ status: 'active' });
  assert.equal(approved.status, 200);
  assert.equal(approved.body.data.status, 'active');

  const publicResult = await request(app).get(`/api/v1/listings/${id}`);
  assert.equal(publicResult.status, 200);
  assert.equal(publicResult.body.data.id, id);

  const edited = await request(app)
    .patch(`/api/v1/listings/${id}`)
    .set(ownerHeaders)
    .send({ dailyPrice: 95 });
  assert.equal(edited.status, 200);
  assert.equal(edited.body.data.status, 'draft');
});

test('persists advisory physical photo evidence and history without auto-publishing', async () => {
  await startOwner();
  await UserModel.updateOne({ authId: 'u-owner' }, { $set: {
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
  } });
  const verifyOriginal = aiClient.verifyItem;
  const readOriginal = uploadService.readOwnedReferences;
  let received;
  uploadService.readOwnedReferences = async () => [{ content_base64: 'fixture' }];
  aiClient.verifyItem = async (payload) => {
    received = payload;
    return { accepted: false, outcome: 'manual_review', confidence: 0,
      extracted_fields: { authenticityVerified: false, adminReviewRequired: true },
      reasons: ['Risk classifier unavailable'] };
  };
  try {
    const created = await request(app).post('/api/v1/listings').set(ownerHeaders)
      .send({ ...cameraInput, subcategory: 'Cameras' });
    assert.equal(created.status, 201);
    const id = created.body.data.id;
    const submitted = await request(app).post(`/api/v1/listings/${id}/submit`).set(ownerHeaders);
    assert.equal(submitted.status, 200);
    assert.equal(received.category, 'Devices');
    assert.equal(received.subcategory, 'Cameras');
    assert.equal(received.condition, 'Excellent');
    assert.equal(submitted.body.data.status, 'pending_review');
    assert.equal(submitted.body.data.itemVerification.outcome, 'manual_review');
    assert.equal(submitted.body.data.itemVerificationHistory.length, 1);
    assert.equal(submitted.body.data.itemVerificationHistory[0].subcategory, 'Cameras');
    await request(app).patch(`/api/v1/listings/${id}/moderation`).set(adminHeaders)
      .send({ status: 'rejected', reason: 'Please upload clearer views' });
    const edited = await request(app).patch(`/api/v1/listings/${id}`).set(ownerHeaders)
      .send({ condition: 'Good' });
    assert.equal(edited.status, 200);
    assert.equal(edited.body.data.itemVerification, undefined);
    assert.equal(edited.body.data.itemVerificationHistory.length, 1);
    await request(app).post(`/api/v1/listings/${id}/submit`).set(ownerHeaders);
    const saved = await ListingModel.findOne({ publicId: id });
    assert.equal(saved.itemVerificationHistory.length, 2);
    assert.equal(saved.itemVerificationHistory[1].condition, 'Good');
    assert.equal(saved.status, 'pending_review');
  } finally {
    aiClient.verifyItem = verifyOriginal;
    uploadService.readOwnedReferences = readOriginal;
  }
});

test('strict submission preserves failed evidence and still needs admin approval for a candidate', async () => {
  await startOwner();
  await UserModel.updateOne({ authId: 'u-owner' }, { $set: {
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
  } });
  const originalMode = env.aiEnforcementMode;
  const originalVerify = aiClient.verifyItem;
  const originalRead = uploadService.readOwnedReferences;
  env.aiEnforcementMode = 'strict';
  uploadService.readOwnedReferences = async () => [{ content_base64: 'fixture' }];
  aiClient.verifyItem = async () => ({ outcome: 'manual_review', accepted: false });
  try {
    const created = await request(app).post('/api/v1/listings').set(ownerHeaders).send(cameraInput);
    const id = created.body.data.id;
    const failed = await request(app).post(`/api/v1/listings/${id}/submit`).set(ownerHeaders);
    assert.equal(failed.status, 409);
    const saved = await ListingModel.findOne({ publicId: id });
    assert.equal(saved.status, 'draft');
    assert.equal(saved.itemVerificationHistory.length, 1);
    aiClient.verifyItem = async () => ({ outcome: 'approved_candidate', accepted: true });
    const candidate = await request(app).post(`/api/v1/listings/${id}/submit`).set(ownerHeaders);
    assert.equal(candidate.status, 200);
    assert.equal(candidate.body.data.status, 'pending_review');
    assert.equal(candidate.body.data.itemVerificationHistory.length, 2);
  } finally {
    env.aiEnforcementMode = originalMode;
    aiClient.verifyItem = originalVerify;
    uploadService.readOwnedReferences = originalRead;
  }
});

test('services submit without physical item analysis', async () => {
  await startOwner();
  await UserModel.updateOne({ authId: 'u-owner' }, { $set: {
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
  } });
  const original = aiClient.verifyItem;
  let calls = 0;
  aiClient.verifyItem = async () => { calls++; return { outcome: 'warning' }; };
  try {
    const created = await request(app).post('/api/v1/listings').set(ownerHeaders).send({
      title: 'Event Photography Package', category: 'Services', listingType: 'service',
      dailyPrice: 450, priceUnit: 'package', location: 'Kuala Lumpur',
      serviceDetails: { packageName: 'Event Coverage', durationMinutes: 180, venueMode: 'renter_location' },
    });
    const submitted = await request(app).post(`/api/v1/listings/${created.body.data.id}/submit`).set(ownerHeaders);
    assert.equal(submitted.status, 200);
    assert.equal(calls, 0);
    assert.equal(submitted.body.data.itemVerification, undefined);
    assert.equal(submitted.body.data.itemVerificationHistory.length, 0);
  } finally {
    aiClient.verifyItem = original;
  }
});

test('prevents one Owner from changing another Owner listing', async () => {
  await startOwner();
  await request(app)
    .post('/api/v1/users/session')
    .set({
      ...ownerHeaders,
      'x-user-id': 'u-other-owner',
      'x-user-email': 'other@renthub.my',
      'x-user-name': 'Other Owner',
    });
  const listing = await activeListing({ publicId: 'l-owner-only' });

  const response = await request(app)
    .patch(`/api/v1/listings/${listing.publicId}`)
    .set({ ...ownerHeaders, 'x-user-id': 'u-other-owner' })
    .send({ dailyPrice: 99 });

  assert.equal(response.status, 404);
});

test('supports renter discovery search, category, type and price filters', async () => {
  await activeListing({ publicId: 'l-camera', promoted: true });
  await ListingModel.create({
    publicId: 'l-photo',
    ownerId: 'u-aina',
    ownerName: 'Aina Rahman',
    title: 'Event Photography Package',
    category: 'Services',
    listingType: 'service',
    dailyPrice: 450,
    priceUnit: 'package',
    serviceDetails: {
      packageName: 'Essential Event Coverage',
      durationMinutes: 180,
    },
    location: 'Kuala Lumpur',
    verified: true,
    status: 'active',
  });
  await activeListing({
    publicId: 'l-hidden',
    title: 'Hidden Camera',
    status: 'draft',
  });

  const response = await request(app).get(
    '/api/v1/listings?search=Photography&category=Services&type=service&minPrice=400&maxPrice=500&verified=true',
  );

  assert.equal(response.status, 200);
  assert.equal(response.body.meta.total, 1);
  assert.equal(response.body.data[0].id, 'l-photo');
  assert.equal(response.body.data[0].isService, true);
});

test('stores validated availability and excludes conflicting date ranges', async () => {
  await startOwner();
  const listing = await activeListing({ publicId: 'l-camera' });

  const overlap = await request(app)
    .put(`/api/v1/listings/${listing.publicId}/availability`)
    .set(ownerHeaders)
    .send({
      unavailableRanges: [
        { start: '2026-09-20', end: '2026-09-23' },
        { start: '2026-09-22', end: '2026-09-24' },
      ],
    });
  assert.equal(overlap.status, 400);
  assert.equal(overlap.body.error.code, 'VALIDATION_ERROR');

  const saved = await request(app)
    .put(`/api/v1/listings/${listing.publicId}/availability`)
    .set(ownerHeaders)
    .send({
      unavailableRanges: [
        {
          start: '2026-09-20T00:00:00.000Z',
          end: '2026-09-23T00:00:00.000Z',
          reason: 'Confirmed booking',
        },
      ],
      minimumNoticeHours: 24,
      bufferHours: 2,
    });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.data.minimumNoticeHours, 24);

  const unavailable = await request(app).get(
    '/api/v1/listings?availableFrom=2026-09-20&availableTo=2026-09-22',
  );
  assert.equal(unavailable.status, 200);
  assert.equal(unavailable.body.meta.total, 0);

  const available = await request(app).get(
    '/api/v1/listings?availableFrom=2026-10-01&availableTo=2026-10-03',
  );
  assert.equal(available.status, 200);
  assert.equal(available.body.meta.total, 1);

  const details = await request(app).get(
    `/api/v1/listings/${listing.publicId}/availability`,
  );
  assert.equal(details.status, 200);
  assert.equal(details.body.data.unavailableRanges.length, 1);
});

test('manages active promotions and physical-item bundle offers', async () => {
  await startOwner();
  const camera = await activeListing({ publicId: 'l-camera' });
  await activeListing({
    publicId: 'l-tripod',
    title: 'Professional Camera Tripod',
    dailyPrice: 25,
  });

  const promoted = await request(app)
    .put(`/api/v1/listings/${camera.publicId}/promotion`)
    .set(ownerHeaders)
    .send({
      label: 'Production Week Deal',
      discountPercent: 20,
      startsAt: '2020-01-01T00:00:00.000Z',
      endsAt: '2035-01-01T00:00:00.000Z',
    });
  assert.equal(promoted.status, 200);
  assert.equal(promoted.body.data.promotionActive, true);
  assert.equal(promoted.body.data.effectiveDailyPrice, 68);

  const bundled = await request(app)
    .put(`/api/v1/listings/${camera.publicId}/bundle`)
    .set(ownerHeaders)
    .send({
      title: 'Camera Production Kit',
      listingIds: ['l-camera', 'l-tripod'],
      discountPercent: 10,
    });
  assert.equal(bundled.status, 200);
  assert.deepEqual(bundled.body.data.bundleOffer.listingIds, [
    'l-camera',
    'l-tripod',
  ]);

  const publicListing = await request(app).get('/api/v1/listings/l-camera');
  assert.equal(publicListing.body.data.promotion.label, 'Production Week Deal');
  assert.equal(publicListing.body.data.bundleOffer.title, 'Camera Production Kit');

  const cleared = await request(app)
    .delete(`/api/v1/listings/${camera.publicId}/promotion`)
    .set(ownerHeaders);
  assert.equal(cleared.status, 200);
  assert.equal(cleared.body.data.promotion, undefined);
  assert.equal(cleared.body.data.effectiveDailyPrice, 85);
});
