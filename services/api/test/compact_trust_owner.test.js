import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { refreshTrustProfile } from '../src/modules/user/trust.service.js';
import { TRUST_POLICY_VERSION } from '../src/modules/user/trustPolicy.js';
import { trustFacts } from './helpers/trustFacts.js';

let mongo;
const h = (id = 'viewer') => ({ 'x-user-id': id, 'x-user-roles': id === 'admin' ? 'admin' : 'owner,renter', 'x-user-email': `${id}@example.test`, 'x-user-name': id });
const models = [UserModel, ReviewModel, RentalModel, BookingModel, ListingModel, PaymentModel];
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(m => m.init())); });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(m => m.deleteMany({})));
  await UserModel.create(['owner', 'viewer', 'other', 'admin'].map(id => ({ authId: id, displayName: `Demo ${id}`, email: `${id}@example.test`,
    roles: id === 'admin' ? ['admin'] : ['renter', 'owner'], activeRole: id === 'admin' ? 'admin' : 'owner', accountStatus: 'active' })));
});
const reviewsUrl = '/api/v1/reviews/subjects/owner';
async function reviews() {
  await ReviewModel.collection.insertMany(Array.from({ length: 48 }, (_, i) => ({ publicId: `RH-REV-EXAMPLE${i}`, authorId: `reviewer${i}`,
    authorName: `Demo reviewer ${i}`, authorRole: 'renter', subjectId: 'owner', subjectRole: i < 33 ? 'owner' : 'renter',
    listingTitle: `Demo item ${i}`, overallRating: 4, text: 'The item was returned in the recorded condition.', status: i === 47 ? 'hidden' : 'published',
    rentalId: `PRIVATE${i}`, bookingId: `PRIVATE${i}`, moderation: { reason: 'PRIVATE' }, createdAt: new Date('2026-11-01T01:00:00Z') })));
}
test('published subject reviews paginate before totals with safe projections and role isolation', async () => {
  await reviews();
  const page1 = await request(app).get(`${reviewsUrl}?page=1&limit=20`).set(h()).expect(200);
  const page2 = await request(app).get(`${reviewsUrl}?page=2&limit=20`).set(h()).expect(200);
  assert.equal(page1.body.meta.total, 47); assert.equal(page2.body.data.length, 20);
  const ids = [...page1.body.data, ...page2.body.data].map(r => r.publicId); assert.equal(new Set(ids).size, 40);
  assert.ok(!JSON.stringify(page1.body.data).includes('PRIVATE'));
  for (const r of page1.body.data) assert.equal(r.authorId, undefined);
  const owners = await request(app).get(`${reviewsUrl}?role=owner&page=2&limit=20`).set(h()).expect(200);
  assert.equal(owners.body.meta.total, 33); assert.equal(owners.body.data.length, 13);
  assert.ok(owners.body.data.every(r => r.subjectRole === 'owner'));
  assert.equal((await request(app).get('/api/v1/reviews/subjects/other').set(h()).expect(200)).body.meta.total, 0);
});
test('subject reviews enforce session, blocking, inactive targets and safe admin access', async () => {
  await reviews(); const previous = env.authMode;
  try { env.authMode = 'local'; await request(app).get(reviewsUrl).expect(401); } finally { env.authMode = previous; }
  await UserModel.updateOne({ authId: 'owner' }, { $set: { blockedUserIds: ['viewer'] } });
  await request(app).get(reviewsUrl).set(h()).expect(404);
  await request(app).get(reviewsUrl).set(h('admin')).expect(200);
  await UserModel.updateOne({ authId: 'owner' }, { $set: { blockedUserIds: [], accountStatus: 'deactivated' } });
  await request(app).get(reviewsUrl).set(h()).expect(404);
  await request(app).get(reviewsUrl).set(h('owner')).expect(403);
});
test('review format validation and hidden/self reviews cannot bypass the new endpoint', async () => {
  await reviews();
  for (const query of ['role=admin', 'limit=101', 'page=0', 'page=abc', 'role[]=owner']) await request(app).get(`${reviewsUrl}?${query}`).set(h()).expect(422);
  await ReviewModel.collection.insertOne({ publicId: 'RH-REV-SELF', subjectId: 'owner', authorId: 'owner', status: 'published' });
  assert.equal((await request(app).get(reviewsUrl).set(h()).expect(200)).body.meta.total, 47);
});
test('an old cached trust policy refreshes to recorded trust while sources stay unchanged', async () => {
  const facts = trustFacts(3, true);
  const offset = Date.now() - Date.parse('2026-10-28T08:00:00Z');
  for (const b of facts.bookings) b.completedAt = new Date(Date.parse(b.completedAt) + offset);
  for (const p of facts.payments) { p.createdAt = new Date(Date.parse(p.createdAt) + offset); p.idempotencyKey = `trust-${p.publicId}`; }
  await Promise.all([BookingModel.collection.insertMany(facts.bookings), RentalModel.collection.insertMany(facts.rentals), PaymentModel.collection.insertMany(facts.payments)]);
  await UserModel.updateOne({ authId: 'owner' }, { $set: { trustProfile: { version: 'renthub-trust-v1', calculatedAt: new Date(), overall: { marketplace: { status: 'insufficient_history' } } } } });
  const result = await refreshTrustProfile('owner'); assert.equal(result.policyVersion, TRUST_POLICY_VERSION);
  assert.equal(result.owner.recorded.completedRentals, 3); assert.equal(result.owner.marketplace.completedRentals, 0);
  assert.ok((await PaymentModel.find().lean()).every(p => p.simulated === true));
  assert.ok((await BookingModel.find().lean()).every(b => b.sourceType === 'marketplace'));
});

async function order(index, changes = {}) {
  const b = `RH-BKG-2026-LATE${index}`, r = `RH-RNT-2026-LATE${index}`;
  await BookingModel.collection.insertOne({ publicId: b, ownerId: changes.ownerId ?? 'owner', renterId: 'viewer', status: changes.bookingStatus ?? 'active' });
  return RentalModel.create({ publicId: r, bookingId: b, listingId: `demo-${index}`, renterId: 'viewer', ownerId: 'owner',
    listingType: 'physical', status: 'active', startDate: new Date('2026-01-01'), endDate: new Date('2026-01-02'), ...changes });
}
test('Owner overdue attention counts all pages, excludes returned/services and preserves approval semantics', async () => {
  for (let i = 0; i < 25; i++) await order(i);
  await order(30, { status: 'disputed' });
  await order(31, { status: 'return_submitted' });
  await order(32, { status: 'active', returnSubmission: { recordedAt: new Date() } });
  await order(33, { listingType: 'service' });
  await order(34, { status: 'scheduled', startDate: new Date('2035-01-01'), endDate: new Date('2035-01-02') });
  await order(35, { ownerId: 'other' });
  // A completed linked booking must not inflate attention from a stale rental.
  await order(36); await BookingModel.updateOne({ publicId: 'RH-BKG-2026-LATE36' }, { $set: { status: 'completed' } });
  await BookingModel.collection.insertMany([0, 1].map(i => ({ publicId: `RH-BKG-2026-PENDING${i}`, ownerId: 'owner', renterId: 'viewer', status: 'pending', paymentStatus: 'authorized', expiresAt: new Date(Date.now() + 3600000) })));
  const summary = await request(app).get('/api/v1/bookings/owner?limit=1').set(h('owner')).expect(200);
  assert.equal(summary.body.meta.summary.pending, 2); assert.equal(summary.body.meta.summary.overdueReturns, 26);
  assert.equal(summary.body.meta.summary.attentionNeeded, 28);
  const first = await request(app).get('/api/v1/rentals/owner?attention=overdue&limit=20').set(h('owner')).expect(200);
  const next = await request(app).get('/api/v1/rentals/owner?attention=overdue&limit=20&page=2').set(h('owner')).expect(200);
  assert.equal(first.body.meta.total, 26); assert.equal(next.body.data.length, 6);
  assert.equal(new Set([...first.body.data, ...next.body.data].map(r => r.id)).size, 26);
  assert.ok(first.body.data.every(r => r.overdueInfo.isOverdue));
  await request(app).get('/api/v1/rentals/mine?attention=overdue').set(h()).expect(422);
  await request(app).get('/api/v1/rentals/owner?attention=unknown').set(h('owner')).expect(422);
  assert.equal((await request(app).get('/api/v1/rentals/owner?attention=overdue').set(h('other')).expect(200)).body.meta.total, 1);
});
