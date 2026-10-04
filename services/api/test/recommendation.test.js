import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import {
  buildRecommendationInteractions,
  modelInteraction,
  recommendationUserId,
} from '../src/modules/listing/recommendationInteractions.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

const renterHeaders = {
  'x-user-id': 'u-renter',
  'x-user-email': 'renter@renthub.my',
  'x-user-name': 'Renter',
  'x-user-roles': 'renter,owner',
};

let mongodb;

function user(authId, overrides = {}) {
  return {
    authId,
    email: `${authId}@renthub.my`,
    displayName: authId,
    roles: ['owner'],
    activeRole: 'owner',
    ...overrides,
  };
}

function listing(publicId, ownerId, overrides = {}) {
  return {
    publicId,
    ownerId,
    ownerName: ownerId,
    title: 'Canon EOS Camera',
    description: 'Mirrorless camera kit',
    category: 'Devices',
    subcategory: 'Cameras',
    brand: 'Canon',
    productModel: 'EOS R50',
    listingType: 'physical',
    dailyPrice: 70,
    condition: 'Excellent',
    fulfilmentMethods: ['pickup'],
    location: 'Kuala Lumpur',
    status: 'active',
    rating: 4.8,
    reviewCount: 12,
    ...overrides,
  };
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    BookingModel.init(),
    ReviewModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    BookingModel.deleteMany({}),
    ReviewModel.deleteMany({}),
  ]);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('canonical interaction precedence is review, completed, booking, saved', () => {
  const interactions = buildRecommendationInteractions({
    users: [{
      authId: 'u-renter',
      savedListingIds: ['l-camera', 'l-saved'],
      updatedAt: new Date('2026-01-01T00:00:00Z'),
    }],
    bookings: [
      {
        publicId: 'RH-BKG-2026-A',
        renterId: 'u-renter',
        listingId: 'l-camera',
        status: 'completed',
        sourceType: 'marketplace',
        completedAt: new Date('2026-01-02T00:00:00Z'),
      },
      {
        publicId: 'RH-BKG-2026-BOOKED',
        renterId: 'u-renter',
        listingId: 'l-booked',
        status: 'approved',
        sourceType: 'marketplace',
        createdAt: new Date('2026-01-02T00:00:00Z'),
      },
      {
        publicId: 'RH-BKG-2026-COMPLETE',
        renterId: 'u-renter',
        listingId: 'l-completed',
        status: 'completed',
        sourceType: 'marketplace',
        completedAt: new Date('2026-01-02T00:00:00Z'),
      },
      {
        publicId: 'RH-BKG-2026-B',
        renterId: 'u-renter',
        listingId: 'l-demo',
        status: 'completed',
        sourceType: 'demo_seed',
        completedAt: new Date('2026-01-02T00:00:00Z'),
      },
      {
        publicId: 'RH-BKG-2026-C',
        renterId: 'u-renter',
        listingId: 'l-cancelled',
        status: 'cancelled',
        sourceType: 'marketplace',
        createdAt: new Date('2026-01-02T00:00:00Z'),
      },
    ],
    reviews: [{
      bookingId: 'RH-BKG-2026-A',
      authorId: 'u-renter',
      authorRole: 'renter',
      listingId: 'l-camera',
      overallRating: 2,
      status: 'published',
      createdAt: new Date('2026-01-03T00:00:00Z'),
    }],
  });

  assert.equal(interactions.length, 4);
  const byListing = new Map(interactions.map((item) => [item.listingId, item]));
  assert.equal(byListing.get('l-camera').interactionType, 'published_review');
  assert.equal(byListing.get('l-camera').rating, 2);
  assert.equal(byListing.get('l-saved').interactionType, 'saved');
  assert.equal(byListing.get('l-booked').interactionType, 'booking');
  assert.equal(byListing.get('l-completed').interactionType, 'completed_rental');
  const serialized = modelInteraction(byListing.get('l-camera'));
  assert.equal(serialized.user_id, recommendationUserId('u-renter'));
  assert.notEqual(serialized.user_id, 'u-renter');
  assert.equal(serialized.source_type, 'marketplace');
});

test('recommendation endpoint sends eligible listings and canonical signals', async () => {
  await Promise.all([
    UserModel.create(user('u-renter', {
      email: 'renter@renthub.my',
      roles: ['renter', 'owner'],
      activeRole: 'renter',
      savedListingIds: ['l-eligible'],
      blockedUserIds: ['u-blocked'],
    })),
    UserModel.create(user('u-active-owner')),
    UserModel.create(user('u-blocked')),
    UserModel.create(user('u-suspended', { accountStatus: 'suspended' })),
  ]);
  await Promise.all([
    ListingModel.create(listing('l-eligible', 'u-active-owner')),
    ListingModel.create(listing('l-own', 'u-renter')),
    ListingModel.create(listing('l-inactive', 'u-active-owner', {
      status: 'inactive',
    })),
    ListingModel.create(listing('l-blocked', 'u-blocked')),
    ListingModel.create(listing('l-suspended', 'u-suspended')),
  ]);
  const original = aiClient.recommendItems;
  let received;
  aiClient.recommendItems = async (payload) => {
    received = payload;
    return payload.candidates.map((candidate) => ({
      item_id: candidate.item_id,
      score: 0.82,
      content_score: 0.8,
      collaborative_score: 0.85,
      reason: 'Similar to listings you saved, booked, completed, or reviewed',
      adapter: 'content-cosine-with-popularity-fallback-v1',
    }));
  };
  try {
    const response = await request(app)
      .get('/api/v1/listings/recommended?limit=10')
      .set(renterHeaders);
    assert.equal(response.status, 200);
    assert.deepEqual(
      received.candidates.map((item) => item.item_id),
      ['l-eligible'],
    );
    assert.equal(received.candidates[0].subcategory, 'Cameras');
    assert.equal(received.candidates[0].brand, 'Canon');
    assert.equal(received.candidates[0].product_model, 'EOS R50');
    assert.equal(received.user_id, recommendationUserId('u-renter'));
    assert.equal(received.interactions.length, 1);
    assert.equal(received.interactions[0].interaction_type, 'saved');
    assert.equal(received.interactions[0].rating, 3.5);
    assert.equal(response.body.data.length, 1);
    assert.equal(response.body.data[0].publicId, 'l-eligible');
    assert.equal(
      response.body.data[0].recommendation.adapter,
      'content-cosine-with-popularity-fallback-v1',
    );
  } finally {
    aiClient.recommendItems = original;
  }
});

test('AI failure returns truthful active-marketplace fallback metadata', async () => {
  await Promise.all([
    UserModel.create(user('u-renter', {
      email: 'renter@renthub.my',
      roles: ['renter'],
      activeRole: 'renter',
    })),
    UserModel.create(user('u-active-owner')),
    ListingModel.create(listing('l-fallback', 'u-active-owner')),
  ]);
  const original = aiClient.recommendItems;
  aiClient.recommendItems = async () => [];
  try {
    const response = await request(app)
      .get('/api/v1/listings/recommended')
      .set(renterHeaders);
    assert.equal(response.status, 200);
    assert.equal(response.body.data[0].recommendation.available, false);
    assert.equal(
      response.body.data[0].recommendation.adapter,
      'marketplace-ordering-fallback-v1',
    );
    assert.doesNotMatch(
      response.body.data[0].recommendation.reason,
      /rental history/i,
    );
  } finally {
    aiClient.recommendItems = original;
  }
});
