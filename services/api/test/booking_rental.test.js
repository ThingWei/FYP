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
import { AvailabilityModel } from '../src/modules/listing/availability.model.js';
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
const serviceOwner = {
  'x-user-id': 'u-aina',
  'x-user-email': 'aina@renthub.my',
  'x-user-name': 'Aina Rahman',
  'x-user-roles': 'owner',
};

async function startProfiles() {
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(owner);
  await request(app).post('/api/v1/users/session').set(serviceOwner);
}

async function createCatalog() {
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
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Bukit Bintang, Kuala Lumpur',
    verified: true,
    status: 'active',
  });
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
      venueMode: 'renter_location',
    },
    location: 'Kuala Lumpur',
    verified: true,
    status: 'active',
  });
}

async function createCameraBooking() {
  return request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      startDate: '2026-09-20T00:00:00.000Z',
      endDate: '2026-09-22T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
      damageWaiverSelected: true,
    });
}

async function authorizeBooking(bookingId, headers = renter) {
  return request(app)
    .post('/api/v1/payments/authorizations')
    .set(headers)
    .send({
      bookingId,
      method: 'card',
      idempotencyKey: `authorize:${bookingId}`,
    });
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    AvailabilityModel.init(),
    BookingModel.init(),
    PaymentModel.init(),
    NotificationModel.init(),
    RentalModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    AvailabilityModel.deleteMany({}),
    BookingModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    RentalModel.deleteMany({}),
  ]);
  await startProfiles();
  await createCatalog();
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('calculates the authoritative camera total and exposes both participant views', async () => {
  const response = await createCameraBooking();

  assert.equal(response.status, 201);
  assert.match(response.body.data.id, /^RH-BKG-2026-/);
  assert.equal(response.body.data.pricing.baseAmount, 255);
  assert.equal(response.body.data.pricing.securityDeposit, 300);
  assert.equal(response.body.data.pricing.damageWaiverFee, 15);
  assert.equal(response.body.data.pricing.total, 570);
  assert.equal(response.body.data.status, 'pending');

  const renterBookings = await request(app)
    .get('/api/v1/bookings/mine?status=pending')
    .set(renter);
  const ownerRequests = await request(app)
    .get('/api/v1/bookings/owner?status=pending')
    .set(owner);
  assert.equal(renterBookings.body.meta.total, 1);
  assert.equal(ownerRequests.body.meta.total, 1);
});

test('runs physical approval, handover, extension and return lifecycle', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  const approved = await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  assert.equal(approved.status, 200);
  assert.equal(approved.body.data.status, 'approved');

  const rentalRecord = await RentalModel.findOne({ bookingId }).lean();
  assert.equal(rentalRecord.status, 'scheduled');

  const handover = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/handover`)
    .set(owner)
    .send({
      condition: 'Excellent',
      notes: 'Body and lens checked together',
      evidence: ['local://handover/front.jpg'],
    });
  assert.equal(handover.status, 200);
  assert.equal(handover.body.data.status, 'active');

  const extension = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/extensions`)
    .set(renter)
    .send({
      requestedEndDate: '2026-09-24T00:00:00.000Z',
      reason: 'Production schedule was extended',
    });
  assert.equal(extension.status, 200);
  assert.equal(extension.body.data.extension.status, 'pending');

  const extensionDecision = await request(app)
    .patch(`/api/v1/rentals/${rentalRecord.publicId}/extensions/decision`)
    .set(owner)
    .send({ status: 'approved' });
  assert.equal(extensionDecision.status, 200);
  assert.equal(
    extensionDecision.body.data.endDate,
    '2026-09-24T00:00:00.000Z',
  );

  const submittedReturn = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/return`)
    .set(renter)
    .send({
      condition: 'Excellent',
      notes: 'Returned with all accessories',
      evidence: ['local://return/front.jpg'],
    });
  assert.equal(submittedReturn.status, 200);
  assert.equal(submittedReturn.body.data.status, 'return_submitted');

  const invalidDeduction = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/return/confirm`)
    .set(owner)
    .send({ condition: 'Good', depositDeduction: 301 });
  assert.equal(invalidDeduction.status, 400);
  assert.equal(invalidDeduction.body.error.code, 'INVALID_DEDUCTION');

  const completed = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/return/confirm`)
    .set(owner)
    .send({ condition: 'Excellent', depositDeduction: 0 });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.data.status, 'completed');
  const booking = await BookingModel.findOne({ publicId: bookingId }).lean();
  assert.equal(booking.status, 'completed');
  assert.equal(booking.paymentStatus, 'settled');
  const paymentTypes = (
    await PaymentModel.find({ bookingId }).sort({ createdAt: 1 }).lean()
  ).map((payment) => payment.type);
  assert.deepEqual(paymentTypes, [
    'authorization',
    'capture',
    'deposit_release',
    'owner_settlement',
  ]);
  const notificationTypes = (
    await NotificationModel.find({
      userId: { $in: ['u-renter', 'u-owner'] },
    }).lean()
  ).map((notification) => notification.type);
  for (const expected of [
    'booking_created',
    'payment_authorized',
    'booking_approved',
    'rental_handover',
    'extension_requested',
    'extension_approved',
    'return_submitted',
    'rental_completed',
  ]) {
    assert.ok(notificationTypes.includes(expected), expected);
  }
});

test('locks approved dates against another booking', async () => {
  const first = await createCameraBooking();
  await authorizeBooking(first.body.data.id);
  await request(app)
    .patch(`/api/v1/bookings/${first.body.data.id}/decision`)
    .set(owner)
    .send({ status: 'approved' });

  await request(app)
    .post('/api/v1/users/session')
    .set({
      ...renter,
      'x-user-id': 'u-renter-two',
      'x-user-email': 'renter2@renthub.my',
      'x-user-name': 'Mei Ling',
    });
  const conflict = await request(app)
    .post('/api/v1/bookings')
    .set({ ...renter, 'x-user-id': 'u-renter-two' })
    .send({
      listingId: 'l-camera',
      startDate: '2026-09-22T00:00:00.000Z',
      endDate: '2026-09-23T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
    });

  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error.code, 'AVAILABILITY_CONFLICT');
});

test('runs service approval, delivery and renter completion lifecycle', async () => {
  const created = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-photo',
      startDate: '2026-10-03T14:00:00.000Z',
      endDate: '2026-10-03T14:00:00.000Z',
      serviceVenue: 'Glasshouse Seputeh, Kuala Lumpur',
    });
  assert.equal(created.status, 201);
  assert.match(created.body.data.id, /^RH-SVC-2026-/);
  assert.equal(created.body.data.pricing.baseAmount, 450);
  assert.equal(created.body.data.pricing.platformFee, 22.5);
  assert.equal(created.body.data.pricing.total, 472.5);
  assert.equal(created.body.data.endDate, '2026-10-03T17:00:00.000Z');

  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(serviceOwner)
    .send({ status: 'approved' });
  const rental = await RentalModel.findOne({ bookingId }).lean();

  const started = await request(app)
    .post(`/api/v1/rentals/${rental.publicId}/start-service`)
    .set(serviceOwner);
  assert.equal(started.body.data.status, 'active');

  const delivered = await request(app)
    .post(`/api/v1/rentals/${rental.publicId}/service-delivered`)
    .set(serviceOwner);
  assert.equal(delivered.body.data.status, 'completion_pending');

  const completed = await request(app)
    .post(`/api/v1/rentals/${rental.publicId}/service-completion`)
    .set(renter);
  assert.equal(completed.body.data.status, 'completed');
  assert.equal(completed.body.data.handover, undefined);
  assert.equal(completed.body.data.returnSubmission, undefined);
  const completedBooking = await BookingModel.findOne({
    publicId: bookingId,
  }).lean();
  assert.equal(completedBooking.paymentStatus, 'settled');
  const paymentTypes = (
    await PaymentModel.find({ bookingId }).sort({ createdAt: 1 }).lean()
  ).map((payment) => payment.type);
  assert.deepEqual(paymentTypes, [
    'authorization',
    'capture',
    'owner_settlement',
  ]);
  const notificationTypes = (
    await NotificationModel.find({
      userId: { $in: ['u-renter', 'u-aina'] },
    }).lean()
  ).map((notification) => notification.type);
  for (const expected of [
    'booking_created',
    'payment_authorized',
    'booking_approved',
    'service_started',
    'service_delivered',
    'service_completed',
  ]) {
    assert.ok(notificationTypes.includes(expected), expected);
  }
});

test('supports cancellation and requires a rejection reason', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;

  const missingReason = await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(owner)
    .send({ status: 'rejected' });
  assert.equal(missingReason.status, 400);
  assert.equal(missingReason.body.error.code, 'REASON_REQUIRED');

  const authorization = await authorizeBooking(bookingId);
  assert.equal(authorization.status, 201);

  const cancelled = await request(app)
    .post(`/api/v1/bookings/${bookingId}/cancel`)
    .set(renter)
    .send({ reason: 'My production dates changed' });
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.equal(cancelled.body.data.status, 'cancelled');
  assert.equal(cancelled.body.data.paymentStatus, 'voided');

  const lateDecision = await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  assert.equal(lateDecision.status, 409);
});

test('rejects booking dates blocked by Owner availability', async () => {
  await AvailabilityModel.create({
    listingId: 'l-camera',
    ownerId: 'u-owner',
    unavailableRanges: [
      {
        start: new Date('2026-09-20T00:00:00.000Z'),
        end: new Date('2026-09-23T00:00:00.000Z'),
        reason: 'Maintenance',
      },
    ],
  });

  const response = await createCameraBooking();
  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'AVAILABILITY_CONFLICT');
});
