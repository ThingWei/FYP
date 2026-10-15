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
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { paymentAdapter } from '../src/integrations/paymentAdapter.js';
import { agreementTerms } from '../src/modules/booking/agreementTerms.js';
import { bookingAgreementTermsHash } from '../src/modules/booking/booking.service.js';

const renter = { 'x-user-id': 'checkout-renter', 'x-user-roles': 'renter' };
const owner = { 'x-user-id': 'checkout-owner', 'x-user-roles': 'owner' };
const other = { 'x-user-id': 'checkout-other', 'x-user-roles': 'renter' };
const admin = { 'x-user-id': 'checkout-admin', 'x-user-roles': 'admin' };
let mongo, id;
const originalAuthorize = paymentAdapter.authorize;
const input = { listingId: 'l-checkout', startDate: '2026-12-20', endDate: '2026-12-20', fulfilmentMethod: 'pickup', agreementAccepted: true, agreementVersion: 'renthub-rental-v2', idempotencyKey: 'booking-checkout-v2' };
const pay = (key, extra = {}, headers = renter) => request(app).post('/api/v1/payments/authorizations').set(headers).send({ bookingId: id, method: 'card', idempotencyKey: key, ...extra });
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all([BookingModel.init(), PaymentModel.init()]); });
after(async () => { paymentAdapter.authorize = originalAuthorize; await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  paymentAdapter.authorize = originalAuthorize;
  await Promise.all([UserModel.deleteMany({}), ListingModel.deleteMany({}), BookingModel.deleteMany({}), RentalModel.deleteMany({}), PaymentModel.deleteMany({}), NotificationModel.deleteMany({})]);
  for (const [authId, role, displayName] of [['checkout-renter', 'renter', 'Renter Name'], ['checkout-owner', 'owner', 'Original Owner'], ['checkout-other', 'renter', 'Other'], ['checkout-admin', 'admin', 'Admin']]) {
    await UserModel.create({ authId, roles: role === 'admin' ? ['admin'] : ['renter', 'owner'], activeRole: role, displayName, email: `${authId}@example.my`, verification: { documentType: 'mykad', status: 'approved', documents: [{ documentType: 'mykad', status: 'approved' }] } });
  }
  await ListingModel.create({ publicId: 'l-checkout', ownerId: 'checkout-owner', ownerName: 'Original Owner', title: 'Checkout camera', category: 'Devices', listingType: 'physical', condition: 'Good', dailyPrice: 100, securityDeposit: 30, fulfilmentMethods: ['pickup'], location: 'Public area', coordinates: { latitude: 3.14, longitude: 101.71 }, locationDetails: { displayAddress: 'Private entrance 12', coordinates: { latitude: 3.14, longitude: 101.71 }, city: 'Kuala Lumpur' }, status: 'active' });
  const created = await request(app).post('/api/v1/bookings').set(renter).send(input).expect(201);
  id = created.body.data.publicId;
});

test('terms are authenticated, versioned, type-specific and retain the original legacy hash', async () => {
  const previous = env.authMode; env.authMode = 'local';
  try {
    await request(app).get('/api/v1/bookings/agreement-terms?listingType=physical').expect(401);
    await request(app).get(`/api/v1/bookings/${id}/agreement`).expect(401);
    await pay('anonymous-key', {}, {}).expect(401);
  } finally { env.authMode = previous; }
  await request(app).get('/api/v1/bookings/agreement-terms?listingType=unknown').set(renter).expect(422);
  const rental = await request(app).get('/api/v1/bookings/agreement-terms?listingType=physical').set(renter).expect(200);
  const service = await request(app).get('/api/v1/bookings/agreement-terms?listingType=service').set(renter).expect(200);
  assert.equal(rental.body.data.version, 'renthub-rental-v2'); assert.equal(service.body.data.version, 'renthub-service-v2');
  assert.ok(!service.body.data.sections.some((section) => section.title === 'Care, return and extensions'));
  assert.equal(agreementTerms('renthub-booking-v1').termsHash, bookingAgreementTermsHash);
  await request(app).post('/api/v1/bookings').set(renter).send({ ...input, idempotencyKey: 'wrong-terms-type', agreementVersion: 'renthub-service-v2' }).expect(422);
});

test('agreement snapshots names, charges and acceptance; pending pickup stays private', async () => {
  await UserModel.updateOne({ authId: 'checkout-owner' }, { displayName: 'Changed Owner' });
  await ListingModel.updateOne({ publicId: 'l-checkout' }, { dailyPrice: 999, title: 'Changed title' });
  const result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(result.body.data.booking.ownerName, 'Original Owner');
  assert.equal(result.body.data.booking.listingTitle, 'Checkout camera');
  assert.equal(result.body.data.booking.pricing.total, 130);
  assert.ok(result.body.data.history.renterAcceptedAt); assert.equal(result.body.data.history.ownerApprovedAt, null);
  assert.equal(result.body.data.record.status, 'awaiting_approval');
  assert.equal(result.body.data.booking.pickupLocationSnapshot, null);
  assert.ok(!JSON.stringify(result.body).includes('Private entrance'));
  await request(app).get(`/api/v1/bookings/${id}/agreement`).set(other).expect(404);
  const own = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(owner).expect(200);
  assert.equal(own.body.data.booking.pickupLocationSnapshot.displayAddress, 'Private entrance 12');
  await request(app).get(`/api/v1/bookings/${id}/agreement`).set(admin).expect(200);
});

test('legacy or missing accepted wording is not replaced with the new terms', async () => {
  await BookingModel.updateOne({ publicId: id }, { 'agreement.version': 'renthub-booking-v1', 'agreement.termsHash': bookingAgreementTermsHash, ownerName: '' });
  let result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(result.body.data.terms.sections.length, 4); assert.equal(result.body.data.booking.ownerName, '');
  await BookingModel.updateOne({ publicId: id }, { 'agreement.version': 'missing-old-version' });
  result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(result.body.data.terms, null);
});

test('decline is durable/idempotent and cannot approve; explicit retry can authorize without confirming booking', async () => {
  const first = await pay('decline-attempt', { simulationOutcome: 'declined', method: 'fpx' }).expect(201);
  const repeat = await pay('decline-attempt', { simulationOutcome: 'declined', method: 'fpx' }).expect(201);
  assert.equal(first.body.data.status, 'failed'); assert.equal(first.body.data.publicId, repeat.body.data.publicId);
  assert.equal((await BookingModel.findOne({ publicId: id })).paymentStatus, 'unpaid');
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' }).expect(409);
  const success = await pay('retry-attempt', { method: 'wallet', amount: 1 }).expect(201);
  assert.equal(success.body.data.amount, 130); assert.equal(success.body.data.status, 'authorized'); assert.equal(success.body.data.simulated, true);
  const booking = await BookingModel.findOne({ publicId: id }); assert.equal(booking.status, 'pending'); assert.equal(booking.paymentStatus, 'authorized');
  assert.equal(await PaymentModel.countDocuments({}), 2); assert.equal(await RentalModel.countDocuments({}), 0);
  const overlapping = await request(app).post('/api/v1/bookings').set(other).send({ ...input, idempotencyKey: 'another-soft-hold' }).expect(201);
  assert.equal(overlapping.body.data.status, 'pending');
});

test('payment validates outcome, ownership, account and terminal/expired states', async () => {
  await pay('foreign-attempt', {}, other).expect(404);
  await pay('bad-outcome', { simulationOutcome: 'anything' }).expect(422);
  await pay('bad-method', { method: 'cash' }).expect(422);
  for (const status of ['cancelled', 'expired', 'rejected', 'approved', 'active', 'completed']) {
    await BookingModel.updateOne({ publicId: id }, { status }); await pay(`status-${status}`).expect(409);
  }
  await BookingModel.updateOne({ publicId: id }, { status: 'pending', expiresAt: new Date(Date.now() - 1) });
  await pay('expired-deadline').expect(409);
  assert.equal(await PaymentModel.countDocuments({}), 0);
});

test('changing method/outcome on an existing attempt conflicts and partial booking writes recover', async () => {
  const paid = await pay('stable-success-key').expect(201);
  await pay('stable-success-key', { method: 'wallet' }).expect(409);
  await pay('stable-success-key', { simulationOutcome: 'declined' }).expect(409);
  await BookingModel.updateOne({ publicId: id }, { paymentStatus: 'unpaid', paymentAuthorizationId: '' });
  const restored = await pay('stable-success-key').expect(201);
  assert.equal(restored.body.data.publicId, paid.body.data.publicId);
  assert.equal((await BookingModel.findOne({ publicId: id })).paymentStatus, 'authorized');
  assert.equal(await PaymentModel.countDocuments({}), 1);
});

test('simultaneous payment attempts use one booking lease and one successful authorization', async () => {
  let release, started; const waiting = new Promise((resolve) => { release = resolve; });
  const entered = new Promise((resolve) => { started = resolve; }); let calls = 0;
  paymentAdapter.authorize = async (value) => { calls++; started(); await waiting; return originalAuthorize(value); };
  const first = pay('concurrent-first').then((response) => response);
  await entered;
  await pay('concurrent-second').expect(409);
  release(); const done = await first; assert.equal(done.status, 201);
  assert.equal(calls, 1); assert.equal(await PaymentModel.countDocuments({ status: 'authorized' }), 1);
  const repeated = await pay('concurrent-second').expect(201); assert.equal(repeated.body.data.publicId, done.body.data.publicId);
  const visible = await request(app).get(`/api/v1/bookings/${id}`).set(renter).expect(200);
  assert.ok(!JSON.stringify(visible.body).includes('paymentLease'));
});

test('stale leases recover and a request cancelled during payment never becomes authorized', async () => {
  await BookingModel.updateOne({ publicId: id }, { paymentLeaseToken: 'old-lease', paymentLeaseUntil: new Date(Date.now() - 1000) });
  let release, started; const waiting = new Promise((resolve) => { release = resolve; }); const entered = new Promise((resolve) => { started = resolve; });
  paymentAdapter.authorize = async (value) => { started(); await waiting; return originalAuthorize(value); };
  const attempt = pay('cancelled-inflight').then((response) => response);
  await entered;
  await request(app).post(`/api/v1/bookings/${id}/cancel`).set(renter).send({ reason: 'Changed plans' }).expect(200);
  release(); assert.equal((await attempt).status, 409);
  assert.equal((await BookingModel.findOne({ publicId: id })).status, 'cancelled');
  assert.equal(await PaymentModel.countDocuments({ status: 'authorized' }), 0);
});

test('approval and record status remain distinct; normal rejection releases demo authorization', async () => {
  await pay('approve-payment').expect(201);
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  let result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.ok(result.body.data.history.ownerApprovedAt); assert.equal(result.body.data.record.status, 'unavailable');
  for (const status of ['confirmed', 'failed', 'unavailable']) {
    await RentalModel.updateOne({ bookingId: id }, { blockchain: { status, mode: 'ganache', network: 'ganache-local', localPrototype: true, contractAddress: 'private-contract', error: 'raw-provider-error' } });
    result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
    assert.equal(result.body.data.booking.status, 'approved'); assert.equal(result.body.data.record.status, status === 'confirmed' ? 'saved' : 'unavailable');
    assert.ok(!JSON.stringify(result.body).includes('private-contract')); assert.ok(!JSON.stringify(result.body).includes('raw-provider-error'));
  }
});

test('service agreement omits physical duties and uses a normal booking record', async () => {
  await ListingModel.create({ publicId: 'l-checkout-service', ownerId: 'checkout-owner', ownerName: 'Original Owner', title: 'Online tuition', category: 'Services', listingType: 'service', dailyPrice: 100, location: 'Online', serviceDetails: { packageName: 'Tuition session', venueMode: 'online', durationMinutes: 60 }, status: 'active' });
  const created = await request(app).post('/api/v1/bookings').set(renter).send({ ...input, listingId: 'l-checkout-service', idempotencyKey: 'service-terms-booking', fulfilmentMethod: undefined, serviceVenue: 'Online', startDate: '2026-12-20T10:00:00+08:00', endDate: '2026-12-20T11:00:00+08:00', agreementVersion: 'renthub-service-v2' }).expect(201);
  const result = await request(app).get(`/api/v1/bookings/${created.body.data.publicId}/agreement`).set(renter).expect(200);
  assert.equal(result.body.data.record.status, 'booking_record'); assert.equal(result.body.data.booking.pricing.securityDeposit, 0);
  assert.equal(result.body.data.terms.version, 'renthub-service-v2');
});

test('rejection voids the simulated hold and preserves accepted agreement history', async () => {
  await pay('rejected-payment').expect(201);
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'rejected', reason: 'Not available' }).expect(200);
  assert.equal((await BookingModel.findOne({ publicId: id })).paymentStatus, 'voided');
  const result = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(result.body.data.history.ownerApprovedAt, null); assert.ok(result.body.data.history.renterAcceptedAt);
});

test('a paid pending request remains approvable after its old payment deadline', async () => {
  await pay('paid-before-expiry').expect(201);
  await BookingModel.updateOne({ publicId: id }, { expiresAt: new Date(Date.now() - 1) });
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  assert.equal(await RentalModel.countDocuments({}), 1);
});

test('successful payment clears its deadline; a durable in-time authorization can recover after that deadline', async () => {
  const success = await pay('deadline-success').expect(201);
  const saved = await BookingModel.findOne({ publicId: id });
  assert.equal(saved.expiresAt, undefined);
  const future = new Date(Date.now() + 1000);
  await PaymentModel.collection.updateOne({ publicId: success.body.data.publicId }, { $set: { createdAt: new Date(Date.now() - 10_000) } });
  await BookingModel.updateOne({ publicId: id }, { $set: { paymentStatus: 'unpaid', paymentAuthorizationId: '', expiresAt: new Date(future.getTime() - 2000) } });
  await pay('deadline-success').expect(201);
  const restored = await BookingModel.findOne({ publicId: id });
  assert.equal(restored.paymentStatus, 'authorized');
  assert.equal(restored.expiresAt, undefined);
  assert.equal(await PaymentModel.countDocuments({}), 1);
});

test('concurrent key collision across bookings cannot return another booking payment', async () => {
  const second = await request(app).post('/api/v1/bookings').set(renter).send({ ...input,
    startDate: '2026-12-21', endDate: '2026-12-21', idempotencyKey: 'key-collision-booking' }).expect(201);
  let entered = 0, signalBoth, release;
  const both = new Promise(resolve => { signalBoth = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  paymentAdapter.authorize = async args => {
    if (++entered === 2) signalBoth();
    await gate;
    return originalAuthorize(args);
  };
  const firstPayment = pay('same-key-two-bookings').then(result => result);
  const secondPayment = pay('same-key-two-bookings', { bookingId: second.body.data.publicId }).then(result => result);
  await both; release();
  const results = await Promise.all([firstPayment, secondPayment]);
  assert.deepEqual(results.map(result => result.status).sort(), [201, 409]);
  assert.equal(await PaymentModel.countDocuments({}), 1);
  assert.equal(await BookingModel.countDocuments({ paymentStatus: 'authorized' }), 1);
});
