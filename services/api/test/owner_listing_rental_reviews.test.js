import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';

const headers = id => ({ 'x-user-id': id, 'x-user-name': id,
  'x-user-email': `${id}@example.test`, 'x-user-roles': 'renter,owner' });
const models = [UserModel, ListingModel, RentalModel, ReviewModel];
const rentalId = 'RH-RNT-2026-REVIEWS';
let mongo;
async function unauthenticated(path) {
  const old = env.authMode;
  try { env.authMode = 'local'; await request(app).get(path).expect(401); }
  finally { env.authMode = old; }
}
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  await Promise.all(models.map(model => model.init()));
});
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(model => model.deleteMany({})));
  await UserModel.create(['owner', 'renter', 'foreign'].map(authId => ({ authId,
    displayName: authId, email: `${authId}@example.test`, roles: ['owner', 'renter'], activeRole: 'owner' })));
});
const listing = (extra = {}) => ListingModel.create({ publicId: 'l-owned-camera', ownerId: 'owner', ownerName: 'Owner',
  title: 'Private camera', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', dailyPrice: 40,
  location: 'Private entrance', coordinates: { latitude: 3.14234, longitude: 101.68678 },
  locationDetails: { coordinates: { latitude: 3.14234, longitude: 101.68678 }, displayAddress: 'Private entrance', city: 'Kuala Lumpur' },
  condition: 'Good', fulfilmentMethods: ['pickup'], status: 'active', ...extra });
async function rental() {
  await RentalModel.create({ publicId: rentalId, bookingId: 'PRIVATE-BOOKING', listingId: 'l-owned-camera',
    listingType: 'physical', renterId: 'renter', ownerId: 'owner', startDate: '2026-01-01', endDate: '2026-01-02', status: 'completed' });
}
const review = (role, extra = {}) => ReviewModel.create({ publicId: `RH-REV-${role}`, rentalId, bookingId: 'PRIVATE-BOOKING',
  listingId: 'l-owned-camera', listingTitle: 'Camera', listingType: 'physical', authorId: role, authorName: role,
  authorRole: role, subjectId: role === 'owner' ? 'renter' : 'owner', subjectName: 'Counterpart',
  subjectRole: role === 'owner' ? 'renter' : 'owner', overallRating: 5, communicationRating: 4,
  text: `Readable ${role} review.`, ...extra });

test('owned details work for every saved status without making private records public', async () => {
  for (const status of ['draft', 'pending_review', 'active', 'rejected', 'inactive']) {
    await ListingModel.deleteMany({}); await listing({ status });
    const result = (await request(app).get('/api/v1/listings/owner/l-owned-camera').set(headers('owner')).expect(200)).body.data;
    assert.equal(result.status, status); assert.equal(result.coordinates.latitude, 3.14234);
    assert.equal(result.locationDetails.displayAddress, 'Private entrance');
    await request(app).get('/api/v1/listings/owner/l-owned-camera').set(headers('foreign')).expect(404);
    if (status !== 'active') await request(app).get('/api/v1/listings/l-owned-camera').expect(404);
    else {
      const publicRow = (await request(app).get('/api/v1/listings/l-owned-camera').expect(200)).body.data;
      assert.equal(publicRow.locationDetails, undefined);
      assert.notEqual(publicRow.coordinates?.latitude, 3.14234);
    }
  }
  assert.equal(await ReviewModel.countDocuments(), 0);
});
test('owned detail requires authentication and an active Owner profile, and supports services', async () => {
  await listing({ listingType: 'service', category: 'Services', subcategory: '', serviceDetails: { packageName: 'Photography', durationMinutes: 60 }, status: 'pending_review' });
  await unauthenticated('/api/v1/listings/owner/l-owned-camera');
  await UserModel.updateOne({ authId: 'owner' }, { $set: { roles: ['renter'], activeRole: 'renter' } });
  await request(app).get('/api/v1/listings/owner/l-owned-camera').set(headers('owner')).expect(403);
  await UserModel.updateOne({ authId: 'owner' }, { $set: { roles: ['owner', 'renter'], activeRole: 'owner' } });
  assert.equal((await request(app).get('/api/v1/listings/owner/l-owned-camera').set(headers('owner')).expect(200)).body.data.listingType, 'service');
  await UserModel.updateOne({ authId: 'owner' }, { $set: { accountStatus: 'suspended' } });
  await request(app).get('/api/v1/listings/owner/l-owned-camera').set(headers('owner')).expect(403);
});
test('participants retrieve both reviews without relying on loaded pages; expired reviews stay readable', async () => {
  await rental();
  await review('owner', { createdAt: new Date(Date.now() - 3 * 86400000), moderation: { reason: 'PRIVATE', moderatedBy: 'PRIVATE' } });
  await review('renter');
  for (const actor of ['owner', 'renter']) {
    const result = (await request(app).get(`/api/v1/reviews/rental/${rentalId}`).set(headers(actor)).expect(200)).body.data;
    assert.equal(result.writtenReview.authorId, actor); assert.equal(result.receivedReview.subjectId, actor);
    assert.equal(result.receivedReview.canEdit, false);
    assert.ok(!JSON.stringify(result).includes('PRIVATE')); assert.equal(result.writtenReview._id, undefined);
    if (actor === 'owner') assert.equal(result.writtenReview.canEdit, false);
  }
  assert.equal(await ReviewModel.countDocuments(), 2);
});
test('hidden counterpart review stays private while its author retains read access', async () => {
  await rental(); await review('renter', { status: 'hidden', flag: { reason: 'PRIVATE' } });
  const owner = (await request(app).get(`/api/v1/reviews/rental/${rentalId}`).set(headers('owner')).expect(200)).body.data;
  assert.deepEqual(owner, { writtenReview: null, receivedReview: null });
  const renter = (await request(app).get(`/api/v1/reviews/rental/${rentalId}`).set(headers('renter')).expect(200)).body.data;
  assert.equal(renter.writtenReview.status, 'hidden'); assert.equal(renter.writtenReview.flag, undefined);
});
test('foreign, missing and unauthenticated rental review requests disclose no records', async () => {
  await rental(); await review('owner');
  await unauthenticated(`/api/v1/reviews/rental/${rentalId}`);
  await request(app).get(`/api/v1/reviews/rental/${rentalId}`).set(headers('foreign')).expect(404);
  await request(app).get('/api/v1/reviews/rental/RH-RNT-2026-MISSING').set(headers('owner')).expect(404);
  await request(app).get('/api/v1/reviews/rental/invalid').set(headers('owner')).expect(422);
});

