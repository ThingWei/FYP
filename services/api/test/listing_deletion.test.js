import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingRequestLockModel, withOperationLock } from '../src/modules/booking/bookingRequestLock.js';
import { listingDeletionEligibility, deleteListing } from '../src/modules/listing/listingDeletion.js';
import { listingService } from '../src/modules/listing/listing.service.js';

const headers = id => ({ 'x-user-id': id, 'x-user-name': id,
  'x-user-email': `${id}@example.test`, 'x-user-roles': id === 'admin' ? 'admin' : 'renter,owner' });
const owner = { authId: 'owner', roles: ['owner'] };
let mongo;
const models = [ListingModel, BookingModel, RentalModel, DisputeModel, UserModel, BookingRequestLockModel];
before(async () => {
  mongo = await MongoMemoryServer.create();
  await connectDatabase(mongo.getUri());
  await Promise.all(models.map(model => model.init()));
});
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(model => model.deleteMany({})));
  await UserModel.create(['owner', 'renter', 'admin'].map(authId => ({ authId, displayName: authId,
    email: `${authId}@example.test`, roles: authId === 'admin' ? ['admin'] : ['renter', 'owner'],
    activeRole: authId === 'admin' ? 'admin' : 'owner',
    verification: { status: 'approved', documentType: 'mykad', documents: [{ documentType: 'mykad', status: 'approved' }] } })));
});
const listing = (extra = {}) => ListingModel.create({ publicId: 'l-delete', ownerId: 'owner', ownerName: 'Owner',
  title: 'Camera', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', status: 'active',
  condition: 'Good', dailyPrice: 40, fulfilmentMethods: ['pickup'], location: 'Kuala Lumpur',
  coordinates: { latitude: 3.12, longitude: 101.68 }, ...extra });

test('only the Owner and administrators can delete; inactive drafts can also be deleted', async () => {
  const row = await listing({ status: 'draft', title: '' });
  await request(app).post('/api/v1/listings/l-delete/delete').set(headers('renter')).expect(404);
  await request(app).post('/api/v1/admin/listings/l-delete/delete').set(headers('owner')).expect(403);
  await request(app).post('/api/v1/listings/l-delete/delete').set(headers('owner')).expect(200);
  assert.ok((await ListingModel.findById(row._id)).deletedAt);
  const repeated = await request(app).post('/api/v1/listings/l-delete/delete').set(headers('owner')).expect(200);
  assert.equal(repeated.body.data.alreadyDeleted, true);
});

for (const [model, states] of [
  [BookingModel, ['pending', 'approved', 'active', 'disputed']],
  [RentalModel, ['scheduled', 'active', 'overdue', 'return_submitted', 'completion_pending', 'disputed']],
  [DisputeModel, ['open', 'awaiting_response', 'under_review', 'more_evidence_required', 'escalated']],
]) {
  for (const status of states) test(`${model.modelName} ${status} blocks deletion for either role`, async () => {
    const row = await listing();
    // Minimal legacy records exercise the policy independently of display-state validation.
    await model.collection.insertOne({ publicId: `history-${status}`, listingId: row.publicId, status });
    const result = await request(app).post('/api/v1/listings/l-delete/delete').set(headers('owner')).expect(409);
    assert.equal(result.body.error.code, 'LISTING_HAS_OPEN_BOOKINGS');
    await request(app).post('/api/v1/admin/listings/l-delete/delete').set(headers('admin')).expect(409);
    assert.equal((await ListingModel.findById(row._id)).deletedAt, undefined);
    const detail = await request(app).get('/api/v1/listings/owner/l-delete').set(headers('owner')).expect(200);
    assert.equal(detail.body.data.deleteEligibility.allowed, false);
  });
}

test('closed history, photos and values survive while deleted listings leave lists and totals', async () => {
  const row = await listing();
  const history = { publicId: 'old-booking', listingId: row.publicId, status: 'completed', pricing: { total: 100 } };
  await BookingModel.collection.insertOne(history);
  await RentalModel.collection.insertOne({ publicId: 'old-rental', listingId: row.publicId, status: 'completed', handover: { evidence: ['upload://UPL-ABC'] } });
  await DisputeModel.collection.insertOne({ listingId: row.publicId, status: 'resolved' });
  assert.equal((await listingDeletionEligibility([row.publicId])).get(row.publicId).allowed, true);
  await request(app).post('/api/v1/admin/listings/l-delete/delete').set(headers('admin')).expect(200);
  assert.equal((await BookingModel.findOne({ publicId: history.publicId }).lean()).pricing.total, 100);
  assert.deepEqual((await RentalModel.findOne({ publicId: 'old-rental' }).lean()).handover.evidence, ['upload://UPL-ABC']);
  await request(app).get('/api/v1/listings/l-delete').expect(404);
  await request(app).get('/api/v1/listings/owner/l-delete').set(headers('owner')).expect(404);
  const mine = await request(app).get('/api/v1/listings/owner/mine').set(headers('owner')).expect(200);
  assert.equal(mine.body.meta.total, 0);
  const adminList = await request(app).get('/api/v1/admin/records/listings').set(headers('admin')).expect(200);
  assert.equal(adminList.body.meta.total, 0);
  const detail = await request(app).get('/api/v1/admin/records/listings/l-delete').set(headers('admin')).expect(200);
  assert.equal(detail.body.data.record.deleteEligibility.allowed, false);
  assert.equal(detail.body.data.record.deletedBy, undefined);
});

test('a stale save, moderation or direct edit cannot restore a deleted listing', async () => {
  const stale = await listing();
  await deleteListing(stale.publicId, owner);
  stale.status = 'active'; stale.title = 'Changed';
  await assert.rejects(stale.save(), error => error.code === 'LISTING_DELETED');
  assert.equal(await ListingModel.findOneAndUpdate({ _id: stale._id }, { $set: { status: 'active' } }), null);
  await request(app).patch('/api/v1/listings/l-delete').set(headers('owner')).send({ title: 'Reopened' }).expect(404);
  await request(app).post('/api/v1/listings/l-delete/submit').set(headers('owner')).expect(404);
  await assert.rejects(listingService.moderate('l-delete', 'active', '', owner), error => error.status === 404);
});

test('deletion waits for an in-flight lifecycle decision and sees its fresh booking', async () => {
  await listing();
  let release, entered;
  const gate = new Promise(resolve => { release = resolve; });
  const started = new Promise(resolve => { entered = resolve; });
  const decision = withOperationLock('listing-decision', 'l-delete', async () => {
    entered(); await gate;
    await BookingModel.collection.insertOne({ listingId: 'l-delete', status: 'approved' });
  });
  await started;
  const removal = deleteListing('l-delete', owner);
  release(); await decision;
  await assert.rejects(removal, error => error.code === 'LISTING_HAS_OPEN_BOOKINGS');
});

test('booking creation rechecks the listing after taking the lifecycle lock', async t => {
  await listing();
  let entered, release;
  const gate = new Promise(resolve => { release = resolve; });
  const waiting = new Promise(resolve => { entered = resolve; });
  // Pause creation after its first read while another operation removes the listing.
  const original = ListingModel.findOne.bind(ListingModel);
  let activeReads = 0;
  t.mock.method(ListingModel, 'findOne', function(filter, ...args) {
    const query = original(filter, ...args);
    if (filter.publicId === 'l-delete' && filter.status === 'active' && ++activeReads === 2) {
      const exec = query.exec.bind(query);
      query.exec = async () => { entered(); await gate; return exec(); };
    }
    return query;
  });
  const booking = request(app).post('/api/v1/bookings').set(headers('renter')).send({ listingId: 'l-delete',
    idempotencyKey: 'delete-race-booking', startDate: '2028-11-16', endDate: '2028-11-16',
    fulfilmentMethod: 'pickup', pickupTime: '09:00', returnTime: '18:00',
    agreementAccepted: true, agreementVersion: 'renthub-booking-v1' }).then(value => value);
  await waiting;
  await deleteListing('l-delete', owner);
  release();
  const result = await booking;
  assert.equal(result.status, 409, JSON.stringify(result.body));
  assert.equal(await BookingModel.countDocuments(), 0);
});
