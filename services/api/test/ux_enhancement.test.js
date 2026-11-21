import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { DisputeMessageModel } from '../src/modules/dispute/disputeMessage.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { notifyCaseAdmins } from '../src/modules/communication/notification.service.js';
import { rememberConfirmedLocation } from '../src/modules/user/recentLocations.js';
import { uniqueSavedPlaces } from '../src/modules/user/savedPlaceIdentity.js';
import { assertBookingTimeAvailable } from '../src/modules/booking/bookingTimePolicy.js';
import { availableDisputeCategories, assertDisputeCategory } from '../src/modules/dispute/disputeCategoryPolicy.js';

const who = (id) => ({ 'x-user-id': id, 'x-user-roles': id === 'admin' ? 'admin' : 'renter,owner' });
const place = { coordinates: { latitude: 5.414001, longitude: 100.328901 }, displayAddress: '1 Jalan Ujian, George Town',
  addressLine1: '1 Jalan Ujian', addressLine2: 'Unit 2', city: 'George Town', state: 'Penang', postcode: '10000' };
const models = [UserModel, ListingModel, DisputeModel, DisputeMessageModel, NotificationModel, RentalModel, BookingModel, PaymentModel];
let mongo;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(model => model.init())); });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(model => model.deleteMany({})));
  await UserModel.create(['renter', 'owner', 'foreign', 'admin'].map(authId => ({ authId, displayName: `Name ${authId}`, email: `${authId}@example.test`,
    roles: authId === 'admin' ? ['admin'] : ['renter', 'owner'], activeRole: authId === 'admin' ? 'admin' : authId === 'owner' ? 'owner' : 'renter' })));
});
function caseRow(n, foreign = false) { return { publicId: `RH-DSP-UX${n}`, rentalId: `RNT-UX${n}`, bookingId: `BKG-UX${n}`, listingId: `l-ux-${n}`,
  listingTitle: `Camera ${n}`, listingType: 'physical', raisedById: foreign ? 'foreign' : 'owner', raisedByName: 'Owner', raisedByRole: 'owner',
  respondentId: foreign ? 'foreign-other' : 'renter', respondentName: 'Renter', respondentRole: 'renter', category: 'communication',
  summary: 'Return arrangement', description: 'Please confirm the return arrangement.', status: 'under_review', previousRentalStatus: 'active', previousBookingStatus: 'active' }; }

test('recent selections deduplicate formatting and concurrent writes but preserve distinct units', async () => {
  await Promise.all([rememberConfirmedLocation('renter', place, 'Pickup'), rememberConfirmedLocation('renter', { ...place, displayAddress: 'Different formatted label' }, 'Booking location')]);
  assert.equal((await UserModel.findOne({ authId: 'renter' })).recentLocations.length, 1);
  await rememberConfirmedLocation('renter', { ...place, addressLine2: 'Unit 3' }, 'Pickup');
  assert.equal((await UserModel.findOne({ authId: 'renter' })).recentLocations.length, 2);
});
test('legacy duplicate places are hidden without deleting stored history or merging units', async () => {
  await UserModel.collection.updateOne({ authId: 'renter' }, { $set: { recentLocations: [
    { publicId: 'one', label: 'Pickup', location: place }, { publicId: 'two', label: 'Pickup', location: { ...place, displayAddress: 'Another label' } },
    { publicId: 'three', label: 'Pickup', location: { ...place, addressLine2: 'Unit 3' } },
  ] } });
  const user = await UserModel.findOne({ authId: 'renter' });
  assert.equal(user.toJSON().recentLocations.length, 2);
  assert.equal(user.recentLocations.length, 3);
  assert.equal(uniqueSavedPlaces([{ line1: 'Road', line2: 'Unit 1' }, { line1: 'road', line2: 'Unit 2' }]).length, 2);
});
test('same-day appointments enforce the Malaysian instant, including midnight and exact boundaries', () => {
  const physical = { listingType: 'physical' };
  const input = { startDate: '2026-11-20', endDate: '2026-11-21', pickupTime: '10:00', returnTime: '18:00' };
  assert.doesNotThrow(() => assertBookingTimeAvailable(physical, input, new Date('2026-11-20T01:59:59Z')));
  assert.throws(() => assertBookingTimeAvailable(physical, input, new Date('2026-11-20T02:00:00Z')), error => error.code === 'APPOINTMENT_TIME_PASSED');
  assert.throws(() => assertBookingTimeAvailable(physical, { ...input, startDate: '2026-11-21', pickupTime: '00:00' }, new Date('2026-11-20T16:00:00Z')));
  assert.doesNotThrow(() => assertBookingTimeAvailable(physical, { ...input, startDate: '2026-11-21', pickupTime: '00:01' }, new Date('2026-11-20T16:00:00Z')));
  assert.throws(() => assertBookingTimeAvailable({ listingType: 'service' }, { startDate: '2026-11-20T02:00:00Z' }, new Date('2026-11-20T02:00:01Z')));
});
test('Owner cannot report damage or non-return before receipt, while renter can report receipt problems', () => {
  const rental = { listingType: 'physical', status: 'scheduled', handover: { receiptStatus: 'pending' }, endDate: new Date('2026-11-19') };
  assert.deepEqual(availableDisputeCategories(rental, 'owner'), ['communication', 'other']);
  assert(availableDisputeCategories(rental, 'renter').includes('damaged_item'));
  assert.throws(() => assertDisputeCategory(rental, 'owner', 'missing_item'), error => error.code === 'DISPUTE_CATEGORY_UNAVAILABLE');
  assert.throws(() => assertDisputeCategory(rental, 'owner', 'late_return'), error => error.code === 'DISPUTE_CATEGORY_UNAVAILABLE');
});
test('late return uses the real deadline, not a forged displayed status or a calendar day alone', () => {
  const rental = { listingType: 'physical', status: 'overdue', endDate: new Date('2026-11-20'), handover: { receiptStatus: 'acknowledged' } };
  assert(!availableDisputeCategories(rental, 'owner', new Date('2026-11-20T01:00:00Z')).includes('late_return'));
  assert(availableDisputeCategories(rental, 'owner', new Date('2026-11-22T16:00:00Z')).includes('late_return'));
  assert(!availableDisputeCategories({ ...rental, returnSubmission: { recordedAt: new Date() } }, 'owner', new Date('2026-11-22T16:00:00Z')).includes('late_return'));
  assert(availableDisputeCategories({ ...rental, returnSubmission: { recordedAt: new Date() } }, 'owner').includes('return_condition'));
});
test('Messaging case inbox paginates before returning rows and isolates foreign cases', async () => {
  await DisputeModel.create([...Array.from({ length: 23 }, (_, n) => caseRow(n)), caseRow(99, true)]);
  const page = await request(app).get('/api/v1/messages/cases?page=2&limit=20').set(who('renter')).expect(200);
  assert.equal(page.body.meta.total, 23); assert.equal(page.body.data.length, 3);
  const admin = await request(app).get('/api/v1/messages/cases?limit=10').set(who('admin')).expect(200);
  assert.equal(admin.body.meta.total, 24); assert.equal(admin.body.data.length, 10);
  await request(app).get('/api/v1/messages/cases/RH-DSP-UX0/messages').set(who('foreign')).expect(404);
});
test('case messages share history between legacy and Messaging routes with protected permissions', async () => {
  await DisputeModel.create(caseRow(1));
  await request(app).post('/api/v1/messages/cases/RH-DSP-UX1/messages').set(who('renter')).send({ idempotencyKey: 'ux-message-key-01', text: 'I can return it today.' }).expect(201);
  const legacy = await request(app).get('/api/v1/disputes/RH-DSP-UX1/messages').set(who('owner')).expect(200);
  assert(legacy.body.data.some(row => row.text === 'I can return it today.'));
  const admin = await request(app).get('/api/v1/messages/cases/RH-DSP-UX1/messages').set(who('admin')).expect(200);
  assert(admin.body.data.some(row => row.text === 'I can return it today.'));
  await request(app).post('/api/v1/messages/cases/RH-DSP-UX1/messages').set(who('foreign')).send({ idempotencyKey: 'ux-message-key-02', text: 'Should fail' }).expect(404);
});
test('read receipts affect only the viewer and do not consume notifications arriving after the read cutoff', async () => {
  await DisputeModel.create(caseRow(1));
  const at = new Date();
  await NotificationModel.collection.insertMany([
    { publicId: 'NTF-OLD', userId: 'renter', type: 'dispute_message', entityType: 'dispute', entityId: 'RH-DSP-UX1', readAt: null, createdAt: new Date(+at - 1000) },
    { publicId: 'NTF-NEW', userId: 'renter', type: 'dispute_message', entityType: 'dispute', entityId: 'RH-DSP-UX1', readAt: null, createdAt: new Date(+at + 60000) },
    { publicId: 'NTF-OTHER', userId: 'owner', type: 'dispute_message', entityType: 'dispute', entityId: 'RH-DSP-UX1', readAt: null, createdAt: new Date(+at - 1000) },
  ]);
  await request(app).post('/api/v1/messages/cases/RH-DSP-UX1/read').set(who('renter')).send({ readThroughAt: at.toISOString() }).expect(200);
  assert((await NotificationModel.findOne({ publicId: 'NTF-OLD' })).readAt);
  assert.equal((await NotificationModel.findOne({ publicId: 'NTF-NEW' })).readAt, null);
  assert.equal((await NotificationModel.findOne({ publicId: 'NTF-OTHER' })).readAt, null);
});
test('admin case notifications deduplicate and deep link to the authorized case or conversation', async () => {
  const record = await DisputeModel.create(caseRow(1));
  const payload = { type: 'dispute_opened', title: 'New dispute', body: 'Please review the case.', dedupeKey: 'ux-case-open' };
  await notifyCaseAdmins(record, payload); await notifyCaseAdmins(record, payload);
  assert.equal(await NotificationModel.countDocuments({ userId: 'admin' }), 1);
  const note = await NotificationModel.findOne({ userId: 'admin' });
  const target = await request(app).get(`/api/v1/messages/notifications/${note.publicId}/target`).set(who('admin')).expect(200);
  assert.equal(target.body.data.kind, 'admin_case');
  await NotificationModel.updateOne({ _id: note._id }, { $set: { type: 'dispute_message' } });
  const message = await request(app).get(`/api/v1/messages/notifications/${note.publicId}/target`).set(who('admin')).expect(200);
  assert.equal(message.body.data.kind, 'case_chat');
});
test('Owner listing search and filters apply before pagination, counts and authorization', async () => {
  await ListingModel.collection.insertMany([...Array.from({ length: 27 }, (_, n) => ({ publicId: `l-ux-${n}`, ownerId: 'owner', title: `[UX] Camera ${n}`, brand: 'Canon', productModel: 'EOS R50',
    category: 'Devices', subcategory: 'Cameras', status: 'active', images: [], updatedAt: new Date() })),
    { publicId: 'l-ux-book', ownerId: 'owner', title: 'Canon guide', category: 'Books', status: 'draft', images: [] },
    { publicId: 'l-ux-private', ownerId: 'foreign', title: 'Canon camera', category: 'Devices', status: 'active', images: [] }]);
  const rows = await request(app).get('/api/v1/listings/owner/mine?search=Canon&category=Devices&status=active&page=2&limit=20').set(who('owner')).expect(200);
  assert.equal(rows.body.meta.total, 27); assert.equal(rows.body.data.length, 7);
  assert(rows.body.data.every(row => row.ownerId === 'owner' && row.category === 'Devices'));
  const literal = await request(app).get('/api/v1/listings/owner/mine?search=.*').set(who('owner')).expect(200);
  assert.equal(literal.body.meta.total, 0);
  await request(app).get('/api/v1/listings/owner/mine?category=Invalid').set(who('owner')).expect(422);
});

test('direct dispute submissions cannot bypass pending-receipt and actual-overdue restrictions', async () => {
  const rentalId = 'RH-RNT-2026-UX1';
  await RentalModel.collection.insertOne({ publicId: rentalId, bookingId: 'BKG-UX', listingId: 'l-ux', listingType: 'physical',
    ownerId: 'owner', renterId: 'renter', status: 'scheduled', endDate: new Date('2099-12-31'), handover: { receiptStatus: 'pending' } });
  await BookingModel.collection.insertOne({ publicId: 'BKG-UX', status: 'approved', listingTitle: 'Camera' });
  for (const category of ['damaged_item', 'missing_item', 'late_return', 'return_condition']) {
    const result = await request(app).post('/api/v1/disputes').set(who('owner')).send({ rentalId, category,
      summary: 'Issue reported', description: 'The Owner is reporting an issue with this item.', evidence: [] });
    assert.equal(result.status, 409);
    assert.equal(result.body.error.code, 'DISPUTE_CATEGORY_UNAVAILABLE');
  }
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'active', 'handover.receiptStatus': 'acknowledged' } });
  const late = await request(app).post('/api/v1/disputes').set(who('owner')).send({ rentalId, category: 'late_return',
    summary: 'Not returned', description: 'The date is still in the future but this is a direct request.', evidence: [] });
  assert.equal(late.status, 409);
  assert.equal(await DisputeModel.countDocuments(), 0);
  assert.equal(await PaymentModel.countDocuments(), 0);
  assert.equal(await NotificationModel.countDocuments(), 0);
  assert.equal((await BookingModel.findOne({ publicId: 'BKG-UX' })).status, 'approved');
});


test('expired booking archive is participant-scoped, idempotent, paginated and reversible without financial changes', async () => {
  const id = 'RH-BKG-2026-ARCHIVE';
  await BookingModel.collection.insertMany(Array.from({length:22}, (_,i) => ({publicId:i===0?id:`RH-BKG-2026-ARCH${i}`,listingId:'l-archive',listingTitle:'Archive camera',listingType:'physical',renterId:'renter',ownerId:'owner',status:'expired',paymentStatus:'voided',startDate:new Date('2026-01-01'),endDate:new Date('2026-01-01'),createdAt:new Date(2026,0,i+1)})));
  for (const user of ['foreign','admin']) await request(app).patch(`/api/v1/bookings/${id}/archive`).set(who(user)).send({archived:true}).expect(404);
  await request(app).patch(`/api/v1/bookings/${id}/archive`).set(who('renter')).send({archived:'false'}).expect(422);
  for(let i=0;i<2;i++) await request(app).patch(`/api/v1/bookings/${id}/archive`).set(who('renter')).send({archived:true}).expect(200);
  const list = await request(app).get('/api/v1/bookings/mine?limit=10&page=2').set(who('renter')).expect(200);
  assert.equal(list.body.meta.total,21); assert.equal(list.body.data.length,10);
  const archive = await request(app).get('/api/v1/bookings/mine?archived=true').set(who('renter')).expect(200);
  assert.equal(archive.body.meta.total,1); assert.equal(archive.body.data[0].publicId,id); assert.equal(archive.body.data[0].archivedBy,undefined);
  const owner = await request(app).get('/api/v1/bookings/owner').set(who('owner')).expect(200);
  assert.equal(owner.body.meta.total,22);
  await request(app).get(`/api/v1/bookings/${id}`).set(who('renter')).expect(200);
  await request(app).patch(`/api/v1/bookings/${id}/archive`).set(who('renter')).send({archived:false}).expect(200);
  assert.equal((await request(app).get('/api/v1/bookings/mine').set(who('renter'))).body.meta.total,22);
  assert.equal(await PaymentModel.countDocuments(),0); assert.equal(await NotificationModel.countDocuments(),0);
  for(const status of ['pending','approved','active','completed']) {
    await BookingModel.updateOne({publicId:id},{$set:{status}});
    await request(app).patch(`/api/v1/bookings/${id}/archive`).set(who('renter')).send({archived:true}).expect(409);
  }
});
