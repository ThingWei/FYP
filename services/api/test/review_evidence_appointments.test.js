import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { reviewPhoto } from './helpers/reviewPhoto.js';
import { validMykadFields } from './helpers/mykad.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';
import { bookingAppointments, agreementProof } from '../src/modules/booking/appointments.js';
import { needsVehicleGrant, requireVehicleGrant } from '../src/modules/listing/vehicleGrant.js';

const h = id => ({ 'x-user-id': id, 'x-user-name': `Test ${id}`, 'x-user-email': `${id}@example.invalid`, 'x-user-roles': id === 'admin' ? 'admin' : 'owner,renter' });
const owner = h('owner'), renter = h('renter'), admin = h('admin');
let mongo, sequence = 0;
const previousSecret = env.kycIdentityMatchSecret;
const models = [UserModel, ListingModel, BookingModel, RentalModel, PaymentModel, UploadAssetModel];
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(m => m.init())); env.kycIdentityMatchSecret = 'synthetic-review-test-key-not-a-production-secret-12345'; });
after(async () => { env.kycIdentityMatchSecret = previousSecret; await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(m => m.deleteMany({})));
  for (const actor of [owner, renter, admin, h('other')]) await request(app).post('/api/v1/users/session').set(actor).expect(201);
  await UserModel.updateMany({ authId: { $in: ['owner', 'renter'] } }, { $set: { 'verification.status': 'approved', 'verification.documentType': 'mykad', 'verification.documents': [{ documentType: 'mykad', status: 'approved' }] } });
});
const item = (extra = {}) => ({ title: 'Review test camera', description: 'Synthetic test listing for regression checks only.', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', dailyPrice: 50, condition: 'Good', fulfilmentMethods: ['pickup'], images: ['local://test/a.png', 'local://test/b.png', 'local://test/c.png'], location: 'Kuala Lumpur', coordinates: { latitude: 3.13, longitude: 101.68 }, ...extra });
async function activeItem() { return ListingModel.create({ ...item(), publicId: 'l-appointments', ownerId: 'owner', ownerName: 'Test Owner', status: 'active' }); }
const book = extra => ({ listingId: 'l-appointments', idempotencyKey: `review-booking-${++sequence}`, startDate: '2030-12-01', endDate: '2030-12-01', pickupTime: '09:00', returnTime: '18:00', fulfilmentMethod: 'pickup', agreementAccepted: true, agreementVersion: 'renthub-rental-v2', ...extra });

test('physical appointments are required, strict and same-day ordered without changing daily charges', async () => {
  await activeItem();
  for (const extra of [{ pickupTime: undefined }, { returnTime: undefined }, { pickupTime: '25:00' }, { pickupTime: 900 }, { returnTime: '09:00' }, { returnTime: '08:59' }]) {
    await request(app).post('/api/v1/bookings').set(renter).send(book(extra)).expect(422);
  }
  assert.equal(await BookingModel.countDocuments(), 0);
  const body = book();
  const first = await request(app).post('/api/v1/bookings').set(renter).send(body).expect(201);
  assert.equal(first.body.data.pickupTime, '09:00'); assert.equal(first.body.data.returnTime, '18:00');
  assert.equal(first.body.data.appointmentTimezone, 'Asia/Kuala_Lumpur'); assert.equal(first.body.data.pricing.baseAmount, 50);
  await request(app).post('/api/v1/bookings').set(renter).send({ ...body, returnTime: '19:00' }).expect(409);
  const id = first.body.data.id;
  await request(app).post('/api/v1/payments/authorizations').set(renter).send({ bookingId: id, method: 'card', idempotencyKey: 'review-payment-1' }).expect(201);
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId: id });
  assert.equal(rental.pickupTime, '09:00'); assert.equal(rental.returnTime, '18:00');
  const agreement = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(agreement.body.data.booking.returnTime, '18:00');
  await request(app).get(`/api/v1/bookings/${id}/agreement`).set(h('other')).expect(404);
});

test('services and historical date-only records do not acquire invented appointments', async () => {
  assert.deepEqual(bookingAppointments({ listingType: 'service' }, {}), {});
  const row = await BookingModel.collection.insertOne({ publicId: 'RH-BKG-2030-LEGACY', listingId: 'l-appointments', listingType: 'physical', renterId: 'renter', ownerId: 'owner', status: 'completed', startDate: new Date('2030-01-01'), endDate: new Date('2030-01-02') });
  assert.equal((await BookingModel.findById(row.insertedId)).pickupTime, undefined);
});

test('vehicle review requirements cannot be avoided using case, spaces or a missing specific category', () => {
  for (const subcategory of ['Cars', ' cars ', 'MOTORCYCLES']) {
    const listing = { listingType: 'physical', category: 'Vehicles', subcategory };
    assert.equal(needsVehicleGrant(listing), true);
    assert.throws(() => requireVehicleGrant(listing), { code: 'VEHICLE_GRANT_REQUIRED' });
  }
  assert.throws(() => requireVehicleGrant({ listingType: 'physical', category: 'Vehicles' }), { code: 'VEHICLE_CATEGORY_REQUIRED' });
  for (const subcategory of ['Bicycles', 'Other vehicles']) assert.doesNotThrow(() => requireVehicleGrant({ listingType: 'physical', category: 'Vehicles', subcategory }));
});

test('grant photos are private, correctly scoped, required at review and protected from deletion', async t => {
  t.mock.method(aiClient, 'verifyItem', async () => ({ outcome: 'manual_review', accepted: false }));
  const grant = await reviewPhoto('owner', 'vehicle_grant');
  const draft = await request(app).post('/api/v1/listings').set(owner).send(item({ category: 'Vehicles', subcategory: 'Cars' })).expect(201);
  const id = draft.body.data.id;
  await request(app).post(`/api/v1/listings/${id}/submit`).set(owner).expect(409);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ vehicleGrantRef: await reviewPhoto('other', 'vehicle_grant') }).expect(422);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ vehicleGrantRef: await reviewPhoto('owner') }).expect(422);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ vehicleGrantRef: grant }).expect(200);
  await request(app).delete(`/api/v1/uploads/${grant.slice(9)}`).set(owner).expect(409);
  await request(app).post(`/api/v1/listings/${id}/submit`).set(owner).expect(200);
  await request(app).patch(`/api/v1/listings/${id}/moderation`).set(admin).send({ status: 'active' }).expect(409);
  await request(app).patch(`/api/v1/listings/${id}/moderation`).set(admin).send({ status: 'active', vehicleGrantReviewed: true }).expect(200);
  const saved = await ListingModel.findOne({ publicId: id }); assert.equal(saved.vehicleGrantReview.reference, grant); assert.equal(saved.vehicleGrantReview.reviewedBy, 'admin');
  for (const url of [`/api/v1/listings/${id}`, '/api/v1/listings']) {
    const response = await request(app).get(url).expect(200); assert.ok(!JSON.stringify(response.body).includes(grant)); assert.ok(!JSON.stringify(response.body).includes('vehicleGrant'));
  }
  const mine = await request(app).get('/api/v1/listings/owner/mine').set(owner).expect(200); assert.equal(mine.body.data[0].vehicleGrantRef, grant);
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic private image'));
  // A stray/legacy reference in a participant record must not share a grant.
  await RentalModel.collection.insertOne({ publicId: 'PRIVATE-GRANT-LINK', renterId: 'renter', ownerId: 'owner', handover: { evidence: [grant] } });
  await request(app).get(`/api/v1/uploads/${grant.slice(9)}/content`).set(renter).expect(403);
  await request(app).get(`/api/v1/uploads/${grant.slice(9)}/content`).set(admin).expect(200);
  await request(app).get(`/api/v1/uploads/public/${grant.slice(9)}/content`).expect(404);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ vehicleGrantRef: await reviewPhoto('owner', 'vehicle_grant') }).expect(200);
  assert.equal((await ListingModel.findOne({ publicId: id })).vehicleGrantReview?.reference, undefined);
});

test('MyKad holder photos never enter OCR and require explicit review of the current attempt', async t => {
  await UserModel.updateOne({ authId: 'renter' }, { $set: { verification: { status: 'unverified' } } });
  const front = await reviewPhoto('renter', 'verification_document'), back = await reviewPhoto('renter', 'verification_document');
  const payload = { documentType: 'mykad', documentRefs: [front, back] };
  await request(app).post('/api/v1/users/me/verification').set(renter).send(payload).expect(422);
  await request(app).post('/api/v1/users/me/verification').set(renter).send({ ...payload, holderPhotoRef: await reviewPhoto('owner') }).expect(422);
  await request(app).post('/api/v1/users/me/verification').set(renter).send({ ...payload, holderPhotoRef: front }).expect(422);
  t.mock.method(storageAdapter, 'download', async path => Buffer.from(path));
  let calls = 0;
  t.mock.method(aiClient, 'verifyDocument', async value => { calls++; assert.equal(value.images.length, 2); return { accepted: false, outcome: 'manual_review', extracted_fields: validMykadFields(), confidence: .95 }; });
  const holder = await reviewPhoto('renter');
  const submitted = await request(app).post('/api/v1/users/me/verification').set(renter).send({ ...payload, holderPhotoRef: holder }).expect(200);
  assert.equal(calls, 1); assert.equal(submitted.body.data.verification.status, 'pending');
  const user = submitted.body.data, attempt = user.verification.history.at(-1);
  assert.equal(attempt.holderPhotoRef, holder); assert.equal(attempt.documentRefs.length, 2);
  await request(app).patch(`/api/v1/users/${user._id}/verification`).set(admin).send({ status: 'approved', attemptId: attempt.attemptId }).expect(409);
  await request(app).patch(`/api/v1/users/${user._id}/verification`).set(admin).send({ status: 'approved', attemptId: attempt.attemptId, holderPhotoReviewed: true }).expect(200);
  const saved = await UserModel.findById(user._id); assert.equal(saved.verification.history.at(-1).holderPhotoReview.reference, holder);
  await request(app).delete(`/api/v1/uploads/${holder.slice(9)}`).set(renter).expect(409);
  await request(app).get(`/api/v1/uploads/${holder.slice(9)}/content`).set(owner).expect(403);
});

test('saved proof is allowlisted and services never imply physical blockchain coverage', () => {
  const hash = '0x' + 'a'.repeat(64), address = '0x' + 'b'.repeat(40);
  const proof = agreementProof({ listingType: 'physical', blockchain: { status: 'confirmed', localPrototype: true, contractAddress: address, lastTransactionHash: hash, error: 'PRIVATE', rpcUrl: 'PRIVATE', signatureTransactionHashes: [hash, 'PRIVATE'], contractState: 'completed' } });
  assert.equal(proof.contractAddress, address); assert.deepEqual(proof.signatureTransactionHashes, [hash]); assert.ok(!JSON.stringify(proof).includes('PRIVATE'));
  assert.equal(agreementProof({ listingType: 'service' }), null);
});
