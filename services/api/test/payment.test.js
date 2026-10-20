import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

let mongodb;

const renter = {
  'x-user-id': 'u-renter',
  'x-user-email': 'renter@renthub.my',
  'x-user-name': 'Alex Tan',
  'x-user-roles': 'renter',
};
const owner = {
  'x-user-id': 'u-owner',
  'x-user-email': 'owner@renthub.my',
  'x-user-name': 'Sarah J.',
  'x-user-roles': 'owner',
};
const admin = {
  'x-user-id': 'u-admin',
  'x-user-email': 'admin@renthub.my',
  'x-user-name': 'Admin Farah',
  'x-user-roles': 'admin',
};

async function setupBooking() {
  for (const headers of [renter, owner, admin]) {
    await request(app).post('/api/v1/users/session').set(headers);
  }
  await UserModel.updateOne({ authId: 'u-renter' }, { $set: {
    'verification.documentType': 'mykad', 'verification.status': 'approved',
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
  } });
  await ListingModel.create({
    publicId: 'l-camera',
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    title: 'Sony Alpha a7S III Mirrorless Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 85,
    condition: 'Excellent',
    securityDeposit: 300,
    damageWaiverAvailable: true,
    damageWaiverFee: 15,
    fulfilmentMethods: ['pickup'],
    location: 'Bukit Bintang, Kuala Lumpur',
    status: 'active',
  });
  return request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'payment-booking-test',
      startDate: '2026-11-20',
      endDate: '2026-11-22',
      fulfilmentMethod: 'pickup',
      damageWaiverSelected: true,
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
}

async function authorize(bookingId, key = 'payment-test-key') {
  return request(app)
    .post('/api/v1/payments/authorizations')
    .set(renter)
    .send({
      bookingId,
      method: 'card',
      idempotencyKey: key,
      amount: 1,
    });
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    BookingModel.init(),
    RentalModel.init(),
    PaymentModel.init(),
    NotificationModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    BookingModel.deleteMany({}),
    RentalModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    NotificationModel.deleteMany({}),
  ]);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

async function createCapture() {
  const booking = await setupBooking();
  const bookingId = booking.body.data.id;
  await authorize(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: ['local://handover/camera.jpg'] }).expect(200);
  return PaymentModel.findOne({ bookingId, type: 'capture' });
}

test('concurrent refunds cannot exceed the captured amount', async () => {
  const capture = await createCapture();
  const results = await Promise.all(['first', 'second'].map((key) => request(app)
    .post(`/api/v1/payments/${capture.publicId}/refunds`).set(admin)
    .send({ amount: 400, reason: 'Reviewed refund request', idempotencyKey: `concurrent-refund-${key}` })));
  assert.deepEqual(results.map((r) => r.status).sort(), [201, 400]);
  const refunds = await PaymentModel.find({ parentTransactionId: capture.publicId, type: 'refund', status: 'succeeded' });
  assert.equal(refunds.reduce((sum, r) => sum + r.amount, 0), 400);
});

test('refund replay rejects a changed amount rather than silently returning the old payment', async () => {
  const capture = await createCapture();
  const endpoint = `/api/v1/payments/${capture.publicId}/refunds`;
  await request(app).post(endpoint).set(admin)
    .send({ amount: 100, reason: 'Reviewed refund request', idempotencyKey: 'refund-fingerprint-key' }).expect(201);
  const changed = await request(app).post(endpoint).set(admin)
    .send({ amount: 200, reason: 'Reviewed refund request', idempotencyKey: 'refund-fingerprint-key' });
  assert.equal(changed.status, 409);
  assert.equal(changed.body.error.code, 'IDEMPOTENCY_CONFLICT');
});

test('same refund retry reconciles an interrupted booking update without another refund or notification', async () => {
  const capture = await createCapture();
  const input = { amount: 100, reason: 'Reviewed refund request', idempotencyKey: 'refund-recovery-key' };
  const endpoint = `/api/v1/payments/${capture.publicId}/refunds`;
  const first = await request(app).post(endpoint).set(admin).send(input).expect(201);
  await BookingModel.updateOne({ publicId: capture.bookingId }, { $set: { paymentStatus: 'captured' } });
  const retried = await request(app).post(endpoint).set(admin).send(input).expect(201);
  assert.equal(retried.body.data.id, first.body.data.id);
  assert.equal((await BookingModel.findOne({ publicId: capture.bookingId })).paymentStatus, 'partially_refunded');
  assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 1);
  assert.equal(await NotificationModel.countDocuments({ type: 'payment_refunded' }), 1);
});

test('concurrent identical refunds produce one record and replay the same result', async () => {
  const capture = await createCapture();
  const input = { amount: 100, reason: 'Reviewed refund request', idempotencyKey: 'refund-double-tap-key' };
  const results = await Promise.all([1, 2].map(() => request(app)
    .post(`/api/v1/payments/${capture.publicId}/refunds`).set(admin).send(input)));
  assert.ok(results.every((r) => r.status === 201));
  assert.equal(results[0].body.data.id, results[1].body.data.id);
  assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 1);
});

test('refund balance uses cents and remains administrator-only', async () => {
  const capture = await createCapture();
  const endpoint = `/api/v1/payments/${capture.publicId}/refunds`;
  const input = { amount: 569.7, reason: 'Reviewed refund request', idempotencyKey: 'refund-cents-first' };
  await request(app).post(endpoint).set(renter).send(input).expect(403);
  await request(app).post(endpoint).set(owner).send(input).expect(403);
  await request(app).post(endpoint).set(admin).send(input).expect(201);
  await request(app).post(endpoint).set(admin).send({ ...input, amount: 0.1, idempotencyKey: 'refund-cents-second' }).expect(201);
  await request(app).post(endpoint).set(admin).send({ ...input, amount: 0.2, idempotencyKey: 'refund-cents-third' }).expect(201);
  assert.equal((await BookingModel.findOne({ publicId: capture.bookingId })).paymentStatus, 'refunded');
  await request(app).post(endpoint).set(admin).send({ ...input, amount: 0.01, idempotencyKey: 'refund-cents-excess' }).expect(400);
});

test('authorizes the server total and handles retries idempotently', async () => {
  const booking = await setupBooking();
  const bookingId = booking.body.data.id;

  const first = await authorize(bookingId);
  const retry = await authorize(bookingId);
  assert.equal(first.status, 201);
  assert.equal(first.body.data.amount, 570);
  assert.equal(first.body.data.status, 'authorized');
  assert.equal(first.body.data.id, retry.body.data.id);
  assert.equal(await PaymentModel.countDocuments(), 1);

  const storedBooking = await BookingModel.findOne({ publicId: bookingId }).lean();
  assert.equal(storedBooking.paymentStatus, 'authorized');
  assert.equal(storedBooking.paymentAuthorizationId, first.body.data.id);

  const adminAttempt = await request(app)
    .post('/api/v1/payments/authorizations')
    .set(admin)
    .send({ bookingId, method: 'card', idempotencyKey: 'admin-payment-key' });
  assert.equal(adminAttempt.status, 403);
});

test('prevents Owner approval without payment authorization', async () => {
  const booking = await setupBooking();
  const response = await request(app)
    .patch(`/api/v1/bookings/${booking.body.data.id}/decision`)
    .set(owner)
    .send({ status: 'approved' });

  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'PAYMENT_NOT_AUTHORIZED');
});

test('captures on handover and supports monitored partial and full refunds', async () => {
  const booking = await setupBooking();
  const bookingId = booking.body.data.id;
  await authorize(bookingId);
  await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  const rental = await RentalModel.findOne({ bookingId }).lean();
  await request(app)
    .post(`/api/v1/rentals/${rental.publicId}/handover`)
    .set(owner)
    .send({
      condition: 'Excellent',
      evidence: ['local://handover/camera.jpg'],
    });

  const history = await request(app)
    .get(`/api/v1/payments/booking/${bookingId}`)
    .set(renter);
  assert.equal(history.status, 200);
  assert.deepEqual(
    history.body.data.map((item) => item.type),
    ['authorization', 'capture'],
  );
  const capture = history.body.data.find((item) => item.type === 'capture');

  const monitored = await request(app)
    .get('/api/v1/payments?type=capture&status=succeeded')
    .set(admin);
  assert.equal(monitored.status, 200);
  assert.equal(monitored.body.meta.total, 1);

  const partial = await request(app)
    .post(`/api/v1/payments/${capture.id}/refunds`)
    .set(admin)
    .send({
      amount: 100,
      reason: 'Approved partial refund',
      idempotencyKey: 'refund-partial-key',
    });
  assert.equal(partial.status, 201);
  assert.equal(partial.body.data.amount, 100);
  let storedBooking = await BookingModel.findOne({ publicId: bookingId }).lean();
  assert.equal(storedBooking.paymentStatus, 'partially_refunded');

  const retry = await request(app)
    .post(`/api/v1/payments/${capture.id}/refunds`)
    .set(admin)
    .send({
      amount: 100,
      reason: 'Approved partial refund',
      idempotencyKey: 'refund-partial-key',
    });
  assert.equal(retry.body.data.id, partial.body.data.id);

  const full = await request(app)
    .post(`/api/v1/payments/${capture.id}/refunds`)
    .set(admin)
    .send({
      amount: 470,
      reason: 'Approved remaining refund',
      idempotencyKey: 'refund-remaining-key',
    });
  assert.equal(full.status, 201);
  storedBooking = await BookingModel.findOne({ publicId: bookingId }).lean();
  assert.equal(storedBooking.paymentStatus, 'refunded');

  const excessive = await request(app)
    .post(`/api/v1/payments/${capture.id}/refunds`)
    .set(admin)
    .send({
      amount: 1,
      reason: 'No balance remains',
      idempotencyKey: 'refund-excessive-key',
    });
  assert.equal(excessive.status, 400);
  assert.equal(excessive.body.error.code, 'INVALID_REFUND');

  const completedRetry = await request(app)
    .post(`/api/v1/payments/${capture.id}/refunds`)
    .set(admin)
    .send({
      amount: 100,
      reason: 'Approved partial refund',
      idempotencyKey: 'refund-partial-key',
    });
  assert.equal(completedRetry.status, 201);
  assert.equal(completedRetry.body.data.id, partial.body.data.id);
  assert.equal(
    await NotificationModel.countDocuments({
      userId: 'u-renter',
      type: 'payment_refunded',
    }),
    2,
  );
});
