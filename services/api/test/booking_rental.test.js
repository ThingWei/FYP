import test, { after, afterEach, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { LifecycleOperationModel } from '../src/operations/lifecycleJournal.js';
import { BookingRequestLockModel, withBookingRequestLock } from '../src/modules/booking/bookingRequestLock.js';
import { AvailabilityModel } from '../src/modules/listing/availability.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from '../src/modules/loyalty/loyalty.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { uploadService } from '../src/modules/upload/upload.service.js';
import { physicalRentalDate } from '../src/core/calendarDate.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { runPaymentDeadlineJobs } from '../src/operations/lifecycleJobs.js';
import { paymentAdapter } from '../src/integrations/paymentAdapter.js';
import { blockchainAdapter } from '../src/integrations/blockchainAdapter.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { env } from '../src/config/env.js';

let mongodb;
let bookingSequence = 0;

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
const admin = {
  'x-user-id': 'u-admin',
  'x-user-email': 'admin@renthub.my',
  'x-user-name': 'Admin Farah',
  'x-user-roles': 'admin',
};

async function startProfiles() {
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(owner);
  await request(app).post('/api/v1/users/session').set(serviceOwner);
  await approveTestIdentity('u-renter');
}

async function approveTestIdentity(authId) {
  await UserModel.updateOne(
    { authId },
    {
      $set: {
        'verification.status': 'approved',
        'verification.tier': 'basic',
        'verification.documentType': 'mykad',
        'verification.documents': [{
          documentType: 'mykad',
          status: 'approved',
          latestAttemptId: 'KYC-000000000000000000000001',
        }],
      },
    },
  );
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

async function createCameraBooking({ idempotencyKey, headers = renter, listingId = 'l-camera',
  startDate = '2026-09-20T00:00:00.000Z', endDate = '2026-09-22T00:00:00.000Z' } = {}) {
  bookingSequence += 1;
  return request(app)
    .post('/api/v1/bookings')
    .set(headers)
    .send({
      listingId,
      idempotencyKey: idempotencyKey ?? `booking-test:${bookingSequence}`,
      startDate,
      endDate,
      fulfilmentMethod: 'pickup',
      damageWaiverSelected: true,
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
}

async function authorizeBooking(bookingId, headers = renter) {
  const response = await request(app)
    .post('/api/v1/payments/authorizations')
    .set(headers)
    .send({
      bookingId,
      method: 'card',
      idempotencyKey: `authorize:${bookingId}`,
    });
  assert.equal(response.status, 201, JSON.stringify(response.body));
  return response;
}

async function acknowledgeHandover(rentalId) {
  const saved = await RentalModel.findOne({ publicId: rentalId });
  return request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter)
    .send({ handoverId: saved.handover.handoverId }).expect(200);
}

async function applyReferral(referrerHeaders) {
  const summary = await request(app)
    .get('/api/v1/rewards/summary')
    .set(referrerHeaders);
  assert.equal(summary.status, 200);
  const applied = await request(app)
    .post('/api/v1/rewards/referrals/apply')
    .set(renter)
    .send({ referralCode: summary.body.data.referralCode });
  assert.equal(applied.status, 201, JSON.stringify(applied.body));
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    AvailabilityModel.init(),
    BookingModel.init(),
    BookingRequestLockModel.init(),
    PaymentModel.init(),
    NotificationModel.init(),
    ThreadModel.init(),
    RentalModel.init(),
    DisputeModel.init(),
    ReviewModel.init(),
    LoyaltyAccountModel.init(),
    LoyaltyConfigModel.init(),
    ReferralModel.init(),
    RewardLedgerModel.init(),
  ]);
});

beforeEach(async () => {
  bookingSequence = 0;
  await Promise.all([
    LifecycleOperationModel.deleteMany({}),
    UploadAssetModel.deleteMany({}),
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    AvailabilityModel.deleteMany({}),
    BookingModel.deleteMany({}),
    BookingRequestLockModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    ThreadModel.deleteMany({}),
    RentalModel.deleteMany({}),
    DisputeModel.deleteMany({}),
    ReviewModel.deleteMany({}),
    LoyaltyAccountModel.deleteMany({}),
    LoyaltyConfigModel.deleteMany({}),
    ReferralModel.deleteMany({}),
    RewardLedgerModel.deleteMany({}),
  ]);
  await startProfiles();
  await createCatalog();
});

afterEach(t => { t.mock.timers.reset(); });

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
}, { timeout: 15000 });

test('overdue unreturned item blocks direct new bookings and unpaid authorization while preserving replays and access', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-13T01:00:00Z') });
  const pending = await createCameraBooking({ startDate: '2026-11-20', endDate: '2026-11-21', idempotencyKey: 'overdue-original' });
  assert.equal(pending.status, 201);
  await RentalModel.create({ publicId: 'RH-RNT-2026-PAST', bookingId: 'RH-BKG-2026-PAST', listingId: 'past-item',
    renterId: 'u-renter', ownerId: 'u-owner', listingType: 'physical', status: 'active',
    startDate: new Date('2026-11-01'), endDate: new Date('2026-11-02') });
  const blocked = await createCameraBooking({ startDate: '2026-11-25', endDate: '2026-11-26' });
  assert.equal(blocked.status, 409); assert.equal(blocked.body.error.code, 'OVERDUE_RETURN_REQUIRED');
  const pay = await request(app).post('/api/v1/payments/authorizations').set(renter).send({ bookingId: pending.body.data.id,
    method: 'card', idempotencyKey: 'overdue-pay' });
  assert.equal(pay.status, 409); assert.equal(pay.body.error.code, 'OVERDUE_RETURN_REQUIRED');
  assert.equal(await PaymentModel.countDocuments(), 0); assert.equal(await BookingModel.countDocuments(), 1);
  const replay = await createCameraBooking({ startDate: '2026-11-20', endDate: '2026-11-21', idempotencyKey: 'overdue-original' });
  assert.equal(replay.body.data.id, pending.body.data.id);
  await request(app).get('/api/v1/bookings/mine').set(renter).expect(200);
  await request(app).post(`/api/v1/messages/threads/from-booking/${pending.body.data.id}`).set(renter).expect(200);
  await RentalModel.updateOne({ publicId: 'RH-RNT-2026-PAST' }, { $set: { status: 'disputed' } });
  const disputed = await createCameraBooking({ startDate: '2026-11-25', endDate: '2026-11-26' });
  assert.equal(disputed.body.error.code, 'OVERDUE_RETURN_REQUIRED');
  await RentalModel.updateOne({ publicId: 'RH-RNT-2026-PAST' }, { $set: { status: 'return_submitted',
    'returnSubmission.recordedAt': new Date() } });
  await authorizeBooking(pending.body.data.id);
  // Existing durable authorization remains replayable even if another item later becomes overdue.
  await RentalModel.updateOne({ publicId: 'RH-RNT-2026-PAST' }, { $unset: { returnSubmission: 1 }, $set: { status: 'overdue' } });
  await authorizeBooking(pending.body.data.id);
  assert.equal(await PaymentModel.countDocuments({ type: 'authorization', status: 'authorized' }), 1);
  assert.equal((await UserModel.findOne({ authId: 'u-renter' })).accountStatus, 'active');
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
  assert.equal(response.body.data.pricingEvidenceSnapshot, undefined);
  const savedEvidence = await BookingModel.findOne({ publicId: response.body.data.id }).lean();
  assert.equal(savedEvidence.pricingEvidenceSnapshot.dailyPrice, 85);
  assert.equal(savedEvidence.pricingEvidenceSnapshot.priceProvenance.origin, 'unknown');
  await ListingModel.updateOne({ publicId: 'l-camera' }, { $set: { dailyPrice: 120 } });
  assert.equal((await BookingModel.findOne({ publicId: response.body.data.id }).lean()).pricingEvidenceSnapshot.dailyPrice, 85);
  assert.equal(
    response.body.data.agreement.version,
    'renthub-booking-v1',
  );
  assert.ok(response.body.data.agreement.acceptedAt);

  const renterBookings = await request(app)
    .get('/api/v1/bookings/mine?status=pending')
    .set(renter);
  const ownerRequests = await request(app)
    .get('/api/v1/bookings/owner?status=pending')
    .set(owner);
  assert.equal(renterBookings.body.meta.total, 1);
  assert.equal(ownerRequests.body.meta.total, 1);
  assert.equal(ownerRequests.status, 200);
  assert.equal(ownerRequests.body.meta.summary.pending, 0);

  const adminBookings = await request(app)
    .get('/api/v1/bookings/admin?status=pending')
    .set(admin);
  assert.equal(adminBookings.status, 200);
  assert.equal(adminBookings.body.data.length, 1);
  assert.equal(adminBookings.body.data[0].id, response.body.data.id);
  assert.equal(adminBookings.body.meta.total, 1);
});

test('bookings of a demo listing retain demo provenance', async () => {
  await ListingModel.updateOne({ publicId: 'l-camera' }, { $set: { sourceType: 'demo_seed' } });
  const response = await createCameraBooking();
  assert.equal(response.status, 201, JSON.stringify(response.body));
  const stored = await BookingModel.findOne({ publicId: response.body.data.id }).lean();
  assert.equal(stored.sourceType, 'demo_seed');
  assert.equal(stored.pricingEvidenceSnapshot.sourceType, 'demo_seed');
  assert.equal(stored.status, 'pending');
});

test('an available 16 November 2027 one-day rental keeps both dates and charges one day', async () => {
  const response = await createCameraBooking({
    startDate: '2027-11-16', endDate: '2027-11-16',
    idempotencyKey: 'one-day:2027-11-16',
  });
  assert.equal(response.status, 201, JSON.stringify(response.body));
  const row = response.body.data;
  assert.equal(row.startDate, '2027-11-16T00:00:00.000Z');
  assert.equal(row.endDate, '2027-11-16T00:00:00.000Z');
  assert.equal(row.pricing.originalRentalDays, 1);
  assert.equal(row.pricing.baseAmount, row.pricing.originalDailyRate);
  assert.equal(row.status, 'pending');
  assert.equal(row.paymentStatus, 'unpaid');
  const reopened = await request(app).get(`/api/v1/bookings/${row.id}`).set(renter).expect(200);
  assert.equal(reopened.body.data.startDate, row.startDate);
  assert.equal(reopened.body.data.endDate, row.endDate);
  assert.equal(reopened.body.data.paymentStatus, 'unpaid');
});

test('normalizes physical rental input to Malaysian calendar dates without a one-day shift', async () => {
  const dateOnly = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:date-only',
      startDate: '2026-10-05',
      endDate: '2026-10-05',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(dateOnly.status, 201, JSON.stringify(dateOnly.body));
  assert.equal(dateOnly.body.data.startDate, '2026-10-05T00:00:00.000Z');
  assert.equal(dateOnly.body.data.endDate, '2026-10-05T00:00:00.000Z');
  assert.equal(dateOnly.body.data.pricing.baseAmount, 85);

  const legacyTimestamp = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:legacy-malaysia-midnight',
      startDate: '2026-10-05T16:00:00.000Z',
      endDate: '2026-10-05T16:00:00.000Z',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(legacyTimestamp.status, 201, JSON.stringify(legacyTimestamp.body));
  assert.equal(
    legacyTimestamp.body.data.startDate,
    '2026-10-06T00:00:00.000Z',
  );
  assert.equal(legacyTimestamp.body.data.endDate, '2026-10-06T00:00:00.000Z');
});

test('vehicle bookings require approved MyKad and Driving Licence evidence', async () => {
  await ListingModel.create({
    publicId: 'l-vehicle-kyc',
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    title: 'Toyota Vios',
    category: 'Vehicles',
    listingType: 'physical',
    dailyPrice: 180,
    condition: 'Good',
    securityDeposit: 800,
    fulfilmentMethods: ['pickup'],
    location: 'Petaling Jaya, Selangor',
    verified: true,
    status: 'active',
  });
  const missingLicence = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-vehicle-kyc',
      idempotencyKey: 'booking-test:vehicle-missing-licence',
      startDate: '2026-11-10',
      endDate: '2026-11-10',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(missingLicence.status, 403);
  assert.equal(missingLicence.body.error.code, 'DRIVING_ELIGIBILITY_REQUIRED');
  assert.deepEqual(missingLicence.body.error.details.missingDocumentTypes, [
    'driving_licence',
  ]);

  await UserModel.updateOne(
    { authId: 'u-renter' },
    {
      $set: { drivingEligibility: {
        status: 'approved', licenceClasses: ['D'], expiresAt: new Date('2035-01-01'),
        identityMatchConfirmed: true, classReviewConfirmed: true,
      } },
      $push: {
        'verification.documents': {
          documentType: 'driving_licence',
          status: 'approved',
          latestAttemptId: 'KYC-000000000000000000000002',
        },
      },
    },
  );
  const eligible = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-vehicle-kyc',
      idempotencyKey: 'booking-test:vehicle-eligible',
      startDate: '2026-11-10',
      endDate: '2026-11-10',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(eligible.status, 201, JSON.stringify(eligible.body));
});

test('vehicle requests enforce MyKad, independent eligibility, validity through rental and exact required class', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-09T04:00:00Z') });
  await ListingModel.create({ publicId: 'l-driving-check', ownerId: 'u-owner', ownerName: 'Synthetic Owner',
    title: 'Synthetic vehicle', category: 'Vehicles', subcategory: 'Cars', requiredLicenceClass: 'D',
    listingType: 'physical', condition: 'Good', dailyPrice: 100, fulfilmentMethods: ['pickup'], location: 'Kuala Lumpur', status: 'active' });
  const validDriving = { status: 'approved', licenceClasses: ['D'], expiresAt: new Date('2035-01-01'),
    identityMatchConfirmed: true, classReviewConfirmed: true };
  const cases = [
    { mykad: 'unverified', driving: validDriving, code: 'MYKAD_REQUIRED' },
    { mykad: 'pending', driving: validDriving, code: 'MYKAD_REQUIRED' },
    { mykad: 'rejected', driving: validDriving, code: 'MYKAD_REQUIRED' },
    { mykad: 'approved', driving: { status: 'unverified' }, code: 'DRIVING_ELIGIBILITY_REQUIRED' },
    { mykad: 'approved', driving: { status: 'pending' }, code: 'DRIVING_ELIGIBILITY_REQUIRED' },
    { mykad: 'approved', driving: { status: 'rejected' }, code: 'DRIVING_ELIGIBILITY_REQUIRED' },
    { mykad: 'approved', driving: { ...validDriving, expiresAt: new Date('2000-01-01') }, code: 'DRIVING_ELIGIBILITY_EXPIRED' },
    { mykad: 'approved', driving: { ...validDriving, expiresAt: new Date('2026-11-09') }, code: 'DRIVING_ELIGIBILITY_EXPIRED' },
    { mykad: 'approved', driving: { ...validDriving, licenceClasses: ['B2'] }, code: 'DRIVING_LICENCE_CLASS_REQUIRED' },
    { mykad: 'approved', driving: { ...validDriving, identityMatchConfirmed: false }, code: 'DRIVING_ELIGIBILITY_REVIEW_REQUIRED' },
  ];
  const payload = { listingId: 'l-driving-check', startDate: '2026-11-10', endDate: '2026-11-10',
    fulfilmentMethod: 'pickup', agreementAccepted: true, agreementVersion: 'renthub-booking-v1' };
  for (const [index, fixture] of cases.entries()) {
    await UserModel.updateOne({ authId: 'u-renter' }, { $set: {
      'verification.documents': [{ documentType: 'mykad', status: fixture.mykad }],
      drivingEligibility: fixture.driving,
    } });
    const blocked = await request(app).post('/api/v1/bookings').set(renter)
      .send({ ...payload, idempotencyKey: `driving-case:${index}` });
    assert.equal(blocked.status, 403, JSON.stringify(blocked.body));
    assert.equal(blocked.body.error.code, fixture.code);
  }
  await UserModel.updateOne({ authId: 'u-renter' }, { $set: {
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }], drivingEligibility: validDriving,
  } });
  const allowed = await request(app).post('/api/v1/bookings').set(renter)
    .send({ ...payload, idempotencyKey: 'driving-case:allowed' });
  assert.equal(allowed.status, 201, JSON.stringify(allowed.body));
  assert.equal((await authorizeBooking(allowed.body.data.id)).status, 201);
  const approved = await request(app).patch(`/api/v1/bookings/${allowed.body.data.id}/decision`).set(owner)
    .send({ status: 'approved' });
  assert.equal(approved.status, 200, JSON.stringify(approved.body));
  await UserModel.updateOne({ authId: 'u-renter' }, { $set: { 'drivingEligibility.expiresAt': new Date('2000-01-01') } });
  const rental = await RentalModel.findOne({ bookingId: allowed.body.data.id });
  assert.equal(rental.category, 'Vehicles');
  assert.equal(rental.requiredLicenceClass, 'D');
  await ListingModel.updateOne({ publicId: 'l-driving-check' }, { $set: { category: 'Devices', requiredLicenceClass: '' } });
  const handover = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Good', notes: 'Synthetic handover', evidence: ['local://handover/test.jpg'] });
  assert.equal(handover.status, 403);
  assert.equal(handover.body.error.code, 'DRIVING_ELIGIBILITY_EXPIRED');
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
  await UserModel.updateOne({ authId: 'u-renter' }, { $set: { 'drivingEligibility.expiresAt': new Date('2035-01-01') } });
  // The credential test hands over on a reached start day; future handover has
  // its own independent regression below.
  rental.startDate = physicalRentalDate(new Date());
  await rental.save();
  const validHandover = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Good', notes: 'Synthetic handover', evidence: ['local://handover/test.jpg'] });
  assert.equal(validHandover.status, 200);
  await acknowledgeHandover(rental.publicId);
  await UserModel.updateOne({ authId: 'u-renter' }, { $set: { 'drivingEligibility.expiresAt': new Date('2026-11-10T15:59:59.999Z') } });
  const extension = await request(app).post(`/api/v1/rentals/${rental.publicId}/extensions`).set(renter)
    .send({ requestedEndDate: '2026-11-11', reason: 'Synthetic additional rental day' });
  assert.equal(extension.status, 403);
  assert.equal(extension.body.error.code, 'DRIVING_ELIGIBILITY_EXPIRED');
});

test('requires the current booking agreement before creating a request', async () => {
  const response = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:missing-agreement',
      startDate: '2026-09-20T00:00:00.000Z',
      endDate: '2026-09-22T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
    });

  assert.equal(response.status, 422);
  assert.equal(await BookingModel.countDocuments(), 0);
});

test('uses an active Owner promotion in authoritative booking pricing', async () => {
  await ListingModel.updateOne(
    { publicId: 'l-camera' },
    {
      promotion: {
        enabled: true,
        label: 'Production Week Deal',
        discountPercent: 20,
        startsAt: new Date('2020-01-01T00:00:00.000Z'),
        endsAt: new Date('2035-01-01T00:00:00.000Z'),
      },
      promoted: true,
    },
  );

  const response = await createCameraBooking({
    idempotencyKey: 'checkout:promotion-pricing',
  });

  assert.equal(response.status, 201);
  assert.equal(response.body.data.pricing.baseAmount, 204);
  assert.equal(response.body.data.pricing.total, 519);
});

test('replays a booking request without duplicating records or side effects', async () => {
  const idempotencyKey = 'checkout:sequential-retry';
  const first = await createCameraBooking({ idempotencyKey });
  const replay = await createCameraBooking({ idempotencyKey });

  assert.equal(first.status, 201);
  assert.equal(replay.status, 201);
  assert.equal(replay.body.data.id, first.body.data.id);
  assert.equal(await BookingModel.countDocuments(), 1);
  assert.equal(await ThreadModel.countDocuments(), 1);
  assert.equal(
    await NotificationModel.countDocuments({ type: 'booking_created' }),
    1,
  );
});

test('deduplicates concurrent booking requests', async () => {
  const idempotencyKey = 'checkout:concurrent-retry';
  const [first, replay] = await Promise.all([
    createCameraBooking({ idempotencyKey }),
    createCameraBooking({ idempotencyKey }),
  ]);

  assert.equal(first.status, 201);
  assert.equal(replay.status, 201);
  assert.equal(replay.body.data.id, first.body.data.id);
  assert.equal(await BookingModel.countDocuments(), 1);
  assert.equal(await ThreadModel.countDocuments(), 1);
  assert.equal(
    await NotificationModel.countDocuments({ type: 'booking_created' }),
    1,
  );
});

for (const paid of [false, true]) {
  test(`rejects fresh-key overlapping pending requests for the same renter (paid=${paid})`, async () => {
    const first = await createCameraBooking();
    assert.equal(first.status, 201);
    if (paid) await authorizeBooking(first.body.data.id);
    for (const [startDate, endDate] of [
      ['2026-09-20', '2026-09-22'], ['2026-09-19', '2026-09-20'],
      ['2026-09-22', '2026-09-24'], ['2026-09-21', '2026-09-21'],
      ['2026-09-19', '2026-09-24'],
    ]) {
      const duplicate = await createCameraBooking({ startDate, endDate });
      assert.equal(duplicate.status, 409, JSON.stringify(duplicate.body));
      assert.equal(duplicate.body.error.code, 'DUPLICATE_PENDING_BOOKING');
      assert.deepEqual(duplicate.body.error.details, { bookingId: first.body.data.id });
    }
    assert.equal(await BookingModel.countDocuments(), 1);
    assert.equal(await ThreadModel.countDocuments(), 1);
    assert.equal(await NotificationModel.countDocuments({ type: 'booking_created' }), 1);
    assert.equal(await PaymentModel.countDocuments(), paid ? 1 : 0);
    const original = await BookingModel.findOne({ publicId: first.body.data.id }).lean();
    assert.equal(original.status, 'pending');
    assert.equal(original.paymentStatus, paid ? 'authorized' : 'unpaid');
  });
}

test('same renter can request non-overlapping dates or another item without hard-holding other renters', async () => {
  await createCameraBooking();
  const next = await createCameraBooking({ startDate: '2026-09-23', endDate: '2026-09-24' });
  assert.equal(next.status, 201);
  const original = (await ListingModel.findOne({ publicId: 'l-camera' })).toObject();
  delete original._id;
  await ListingModel.create({ ...original, publicId: 'l-camera-two' });
  assert.equal((await createCameraBooking({ listingId: 'l-camera-two' })).status, 201);
  const other = { ...renter, 'x-user-id': 'u-renter-two', 'x-user-email': 'two@renthub.my' };
  await request(app).post('/api/v1/users/session').set(other);
  await approveTestIdentity('u-renter-two');
  assert.equal((await createCameraBooking({ headers: other })).status, 201);
});

for (const status of ['cancelled', 'rejected', 'expired', 'completed']) {
  test(`a ${status} request does not prevent a new request for the same dates`, async () => {
    const first = await createCameraBooking();
    await BookingModel.updateOne({ publicId: first.body.data.id }, { $set: { status } });
    assert.equal((await createCameraBooking()).status, 201);
  });
}

test('elapsed pending expiry is not a duplicate, while legacy undated expiry still is', async () => {
  const first = await createCameraBooking();
  await BookingModel.updateOne({ publicId: first.body.data.id }, { $unset: { expiresAt: 1 } });
  assert.equal((await createCameraBooking()).body.error.code, 'DUPLICATE_PENDING_BOOKING');
  await BookingModel.updateOne({ publicId: first.body.data.id }, { $set: { expiresAt: new Date(Date.now() - 1000) } });
  assert.equal((await createCameraBooking()).status, 201);
});

test('legacy paid pending requests block duplicates after payment time, before the Owner deadline', async () => {
  const first = await createCameraBooking();
  const id = first.body.data.id;
  await authorizeBooking(id);
  // Legacy rows have no explicit paymentDueAt. Paid requests use the independent
  // Owner deadline, even when creation + ten minutes has elapsed.
  await BookingModel.collection.updateOne({ publicId: id }, {
    $unset: { paymentDueAt: 1 },
    $set: { createdAt: new Date(Date.now() - 11 * 60_000), expiresAt: new Date(Date.now() + 60_000) },
  });
  let duplicate = await createCameraBooking();
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error.details.bookingId, id);
  const legacy = (await BookingModel.findOne({ publicId: id })).toObject();
  delete legacy._id;
  await BookingModel.create({ ...legacy, publicId: 'RH-BKG-2026-LEGACYDUP', paymentStatus: 'unpaid',
    expiresAt: new Date(Date.now() + 60_000), createdAt: new Date(Date.now() + 1000) });
  duplicate = await createCameraBooking();
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error.details.bookingId, id);
  assert.equal(await BookingModel.countDocuments(), 2);
});

test('paid pending requests expire at the Owner deadline and release their hold before a fresh request', async () => {
  const first = await createCameraBooking();
  const id = first.body.data.id;
  await authorizeBooking(id);
  await BookingModel.updateOne({ publicId: id }, { $set: { expiresAt: new Date(Date.now() - 1000) } });
  await request(app).get(`/api/v1/bookings/${id}`).set(renter).expect(200);
  const next = await createCameraBooking();
  assert.equal(next.status, 201, JSON.stringify(next.body));
  assert.notEqual(next.body.data.id, id);
  const expired = await BookingModel.findOne({ publicId: id });
  assert.equal(expired.status, 'expired');
  assert.equal(expired.paymentStatus, 'voided');
  assert.equal((await PaymentModel.findOne({ bookingId: id, type: 'authorization' })).status, 'voided');
  assert.equal(await PaymentModel.countDocuments({ bookingId: id }), 1);
});

for (const partial of [false, true]) {
  test(`simultaneous fresh-key requests cannot both create overlapping pending bookings (partial=${partial})`, async () => {
    const results = await Promise.all([
      createCameraBooking({ idempotencyKey: 'checkout:parallel-one' }),
      createCameraBooking({ idempotencyKey: 'checkout:parallel-two',
        ...(partial && { startDate: '2026-09-22', endDate: '2026-09-24' }) }),
    ]);
    assert.deepEqual(results.map((result) => result.status).sort(), [201, 409]);
    const winner = results.find((result) => result.status === 201);
    const duplicate = results.find((result) => result.status === 409);
    assert.equal(duplicate.body.error.code, 'DUPLICATE_PENDING_BOOKING');
    assert.equal(duplicate.body.error.details.bookingId, winner.body.data.id);
    assert.equal(await BookingModel.countDocuments(), 1);
    assert.equal(await NotificationModel.countDocuments({ type: 'booking_created' }), 1);
  });
}

test('request mutex releases on failure, recovers expired locks and refuses lost ownership', async () => {
  await assert.rejects(withBookingRequestLock('test-renter', 'test-listing', async () => {
    throw new Error('Controlled test failure');
  }), /Controlled test failure/);
  assert.equal(await BookingRequestLockModel.countDocuments(), 0);
  await withBookingRequestLock('test-renter', 'test-listing', async (ensureOwned) => {
    await ensureOwned();
    await BookingRequestLockModel.updateOne({}, { $set: { expiresAt: new Date(Date.now() - 1000) } });
    await withBookingRequestLock('test-renter', 'test-listing', async (newOwner) => {
      await newOwner();
      await assert.rejects(ensureOwned(), (error) => error.code === 'BOOKING_REQUEST_IN_PROGRESS');
    });
  });
  assert.equal(await BookingRequestLockModel.countDocuments(), 0);
});

test('rejects reuse of a booking idempotency key for changed input', async () => {
  const idempotencyKey = 'checkout:changed-request';
  const first = await createCameraBooking({ idempotencyKey });
  const conflict = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey,
      startDate: '2026-09-20T00:00:00.000Z',
      endDate: '2026-09-23T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
      damageWaiverSelected: true,
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });

  assert.equal(first.status, 201);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error.code, 'IDEMPOTENCY_CONFLICT');
  assert.equal(await BookingModel.countDocuments(), 1);
});

test('dual-role renter cannot decide their outgoing request; only the actual Owner can', async () => {
  const dual = { ...renter, 'x-user-roles': 'renter,owner' };
  await request(app).post('/api/v1/users/session').set(dual).expect(200);
  const created = await createCameraBooking();
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId, dual);
  const mine = await request(app).get('/api/v1/bookings/mine').set(dual).expect(200);
  const incoming = await request(app).get('/api/v1/bookings/owner').set(dual).expect(200);
  assert.equal(mine.body.data.length, 1);
  assert.equal(incoming.body.data.length, 0);
  for (const status of ['approved', 'rejected']) {
    await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(dual)
      .send({ status, reason: 'Cannot decide my outgoing rental' }).expect(404);
    const unchanged = await BookingModel.findOne({ publicId: bookingId }).lean();
    assert.equal(unchanged.status, 'pending');
    assert.equal(unchanged.paymentStatus, 'authorized');
    assert.equal(await RentalModel.countDocuments({ bookingId }), 0);
  }
  const approved = await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner)
    .send({ status: 'approved' }).expect(200);
  assert.equal(approved.body.data.status, 'approved');
  assert.equal(await RentalModel.countDocuments({ bookingId }), 1);
});

test('self-booking remains prohibited and malformed legacy self-requests cannot be decided', async () => {
  const dual = { ...renter, 'x-user-roles': 'renter,owner' };
  await request(app).post('/api/v1/users/session').set(dual).expect(200);
  await ListingModel.updateOne({ publicId: 'l-camera' }, { $set: { ownerId: 'u-renter' } });
  const selfBooking = await createCameraBooking();
  assert.equal(selfBooking.status, 400);
  assert.equal(selfBooking.body.error.code, 'OWN_LISTING');
  await ListingModel.updateOne({ publicId: 'l-camera' }, { $set: { ownerId: 'u-owner' } });
  const created = await createCameraBooking();
  assert.equal(created.status, 201);
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId, dual);
  // A historical malformed record must not grant approval to its own renter.
  await BookingModel.updateOne({ publicId: bookingId }, { $set: { ownerId: 'u-renter' } });
  for (const status of ['approved', 'rejected']) {
    await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(dual)
      .send({ status, reason: 'Invalid self-request' }).expect(404);
  }
  assert.equal((await BookingModel.findOne({ publicId: bookingId }).lean()).status, 'pending');
});

test('runs physical approval, handover, extension and return lifecycle', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-20T04:00:00Z') });
  await applyReferral(owner);
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

  const adminRentals = await request(app)
    .get('/api/v1/rentals/admin?status=scheduled')
    .set(admin);
  assert.equal(adminRentals.status, 200);
  assert.equal(adminRentals.body.data.length, 1);
  assert.equal(adminRentals.body.data[0].id, rentalRecord.publicId);
  assert.equal(adminRentals.body.meta.total, 1);

  const handover = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/handover`)
    .set(owner)
    .send({
      condition: 'Excellent',
      notes: 'Body and lens checked together',
      evidence: ['local://handover/front.jpg'],
    });
  assert.equal(handover.status, 200);
  assert.equal(handover.body.data.status, 'scheduled');
  await acknowledgeHandover(rentalRecord.publicId);
  t.mock.timers.reset(); // Completion/reward timestamps use the real test time.

  const extension = await request(app)
    .post(`/api/v1/rentals/${rentalRecord.publicId}/extensions`)
    .set(renter)
    .send({
      requestedEndDate: '2026-09-24T00:00:00.000Z',
      reason: 'Production schedule was extended',
    });
  assert.equal(extension.status, 200);
  assert.equal(extension.body.data.extension.status, 'pending');
  const extensionId = extension.body.data.extension.id;
  assert.equal(extension.body.data.extension.amount, 170);
  await request(app).post(`/api/v1/rentals/${rentalRecord.publicId}/extensions/payment`).set(renter)
    .send({ extensionId, method: 'card', simulationOutcome: 'success', idempotencyKey: 'extension-lifecycle-payment' }).expect(200);

  const extensionDecision = await request(app)
    .patch(`/api/v1/rentals/${rentalRecord.publicId}/extensions/decision`)
    .set(owner)
    .send({ status: 'approved', extensionId });
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
  const trust = (await UserModel.findOne({ authId: 'u-owner' }).lean()).trustProfile;
  assert.equal(trust.version, 'renthub-trust-v1');
  assert.equal(trust.owner.marketplace.score, null);
  assert.equal(trust.owner.demo.completedRentals, 1);
  const paymentTypes = (
    await PaymentModel.find({ bookingId }).sort({ createdAt: 1 }).lean()
  ).map((payment) => payment.type);
  assert.deepEqual(paymentTypes, [
    'authorization',
    'capture',
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
  const referral = await ReferralModel.findOne({ refereeId: 'u-renter' }).lean();
  assert.equal(referral.status, 'rewarded');
  assert.equal(referral.qualifyingBookingId, bookingId);
  assert.equal(
    await RewardLedgerModel.countDocuments({ sourceId: referral.publicId }),
    2,
  );
  assert.equal((await LoyaltyAccountModel.findOne({ userId: 'u-owner' })).points, 250);
});

test('concurrent Owner approvals cannot confirm overlapping requests from different renters', async () => {
  const secondRenter = { ...renter, 'x-user-id': 'u-second-renter', 'x-user-email': 'second@renthub.my' };
  await request(app).post('/api/v1/users/session').set(secondRenter).expect(201);
  await approveTestIdentity('u-second-renter');
  const first = await createCameraBooking();
  const second = await createCameraBooking({ headers: secondRenter });
  assert.equal(first.status, 201); assert.equal(second.status, 201);
  const ids = [first.body.data.id, second.body.data.id];
  await authorizeBooking(ids[0]); await authorizeBooking(ids[1], secondRenter);
  const original = blockchainAdapter.createAgreement;
  blockchainAdapter.createAgreement = async (...args) => {
    await new Promise((resolve) => setTimeout(resolve, 75));
    return original(...args);
  };
  try {
    const responses = await Promise.all(ids.map((id) => request(app)
      .patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' })));
    assert.deepEqual(responses.map((r) => r.status).sort(), [200, 409]);
    assert.equal(await BookingModel.countDocuments({ publicId: { $in: ids }, status: 'approved' }), 1);
    assert.equal(await BookingModel.countDocuments({ publicId: { $in: ids }, status: 'expired' }), 1);
    assert.equal(await RentalModel.countDocuments({ bookingId: { $in: ids } }), 1);
  } finally { blockchainAdapter.createAgreement = original; }
});

test('cancellation racing approval leaves no active scheduled rental or payment hold', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  const original = blockchainAdapter.createAgreement;
  blockchainAdapter.createAgreement = async (...args) => {
    await new Promise((resolve) => setTimeout(resolve, 75));
    return original(...args);
  };
  try {
    const results = await Promise.all([
      request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }),
      request(app).post(`/api/v1/bookings/${bookingId}/cancel`).set(renter).send({ reason: 'Schedule changed' }),
    ]);
    assert.equal(results[1].status, 200);
    assert.ok([200, 409].includes(results[0].status));
    const booking = await BookingModel.findOne({ publicId: bookingId });
    assert.equal(booking.status, 'cancelled');
    assert.equal(booking.paymentStatus, 'voided');
    assert.equal(await RentalModel.countDocuments({ bookingId, status: { $ne: 'cancelled' } }), 0);
  } finally { blockchainAdapter.createAgreement = original; }
});

test('double handover and double return confirmation do not duplicate captures or settlements', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-20T04:00:00Z') });
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  const handovers = await Promise.all([1, 2].map(() => request(app)
    .post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: ['local://handover/front.jpg'] })));
  assert.deepEqual(handovers.map((r) => r.status).sort(), [200, 200]);
  assert.equal(handovers[0].body.data.handover.handoverId, handovers[1].body.data.handover.handoverId);
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 0);
  await Promise.all([1, 2].map(() => acknowledgeHandover(rental.publicId)));
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 1);
  await request(app).post(`/api/v1/rentals/${rental.publicId}/return`).set(renter)
    .send({ condition: 'Excellent', evidence: ['local://return/front.jpg'] }).expect(200);
  const returns = await Promise.all([1, 2].map(() => request(app)
    .post(`/api/v1/rentals/${rental.publicId}/return/confirm`).set(owner)
    .send({ condition: 'Excellent', depositDeduction: 0 })));
  assert.deepEqual(returns.map((r) => r.status).sort(), [200, 409]);
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'owner_settlement' }), 1);
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'deposit_release' }), 1);
});

test('extension cannot overlap an unresolved disputed rental or be approved after return submission', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-20T04:00:00Z') });
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: ['local://handover/front.jpg'] }).expect(200);
  await acknowledgeHandover(rental.publicId);
  const original = await BookingModel.findOne({ publicId: bookingId }).lean();
  const { _id, __v, ...conflict } = original;
  await BookingModel.create({ ...conflict, publicId: 'RH-BKG-2026-DISPUTED', renterId: 'another-renter',
    status: 'disputed', startDate: '2026-09-23', endDate: '2026-09-24', idempotencyKey: undefined });
  const input = { requestedEndDate: '2026-09-24', reason: 'Production needs more time' };
  const blocked = await request(app).post(`/api/v1/rentals/${rental.publicId}/extensions`).set(renter).send(input).expect(409);
  assert.equal(blocked.body.error.code, 'AVAILABILITY_CONFLICT');
  await BookingModel.updateOne({ publicId: 'RH-BKG-2026-DISPUTED' }, { status: 'completed' });
  await request(app).post(`/api/v1/rentals/${rental.publicId}/extensions`).set(renter).send(input).expect(200);
  await request(app).post(`/api/v1/rentals/${rental.publicId}/return`).set(renter)
    .send({ condition: 'Excellent', evidence: ['local://return/front.jpg'] }).expect(200);
  await request(app).patch(`/api/v1/rentals/${rental.publicId}/extensions/decision`).set(owner)
    .send({ status: 'approved' }).expect(409);
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
  await approveTestIdentity('u-renter-two');
  const conflict = await request(app)
    .post('/api/v1/bookings')
    .set({ ...renter, 'x-user-id': 'u-renter-two' })
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:availability-conflict',
      startDate: '2026-09-22T00:00:00.000Z',
      endDate: '2026-09-23T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });

  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error.code, 'AVAILABILITY_CONFLICT');

  await AvailabilityModel.create({
    listingId: 'l-camera',
    ownerId: 'u-owner',
    unavailableRanges: [{
      start: new Date('2026-11-01T00:00:00.000Z'),
      end: new Date('2026-11-03T00:00:00.000Z'),
      reason: 'Maintenance',
    }],
  });

  const availability = await request(app)
    .get('/api/v1/listings/l-camera/availability');
  assert.equal(availability.status, 200);
  assert.equal(availability.body.data.unavailableRanges.length, 2);
  assert.equal(availability.body.data.manualUnavailableRanges.length, 1);
  const bookingRange = availability.body.data.unavailableRanges.find(
    (range) => range.source === 'booking',
  );
  assert.ok(bookingRange);
  assert.equal(
    bookingRange.end,
    '2026-09-23T00:00:00.000Z',
  );

  const unavailableInExplore = await request(app).get(
    '/api/v1/listings?availableFrom=2026-09-22T00:00:00.000Z&availableTo=2026-09-23T00:00:00.000Z',
  );
  assert.equal(
    unavailableInExplore.body.data.some((item) => item.id === 'l-camera'),
    false,
  );

  const adjacentFuture = await request(app)
    .post('/api/v1/bookings')
    .set({ ...renter, 'x-user-id': 'u-renter-two' })
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:adjacent-future',
      startDate: '2026-09-23T00:00:00.000Z',
      endDate: '2026-09-25T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(adjacentFuture.status, 201, JSON.stringify(adjacentFuture.body));
});

test('released booking states do not occupy listing availability', async () => {
  const releasedStatuses = ['completed', 'cancelled', 'rejected', 'expired'];
  await BookingModel.insertMany(releasedStatuses.map((status, index) => ({
    publicId: `RH-BKG-2026-RELEASE${index}`,
    listingId: 'l-camera',
    listingTitle: 'Sony Alpha Camera',
    listingType: 'physical',
    renterId: `u-released-${index}`,
    renterName: `Released ${index}`,
    ownerId: 'u-owner',
    startDate: new Date('2026-10-10T00:00:00.000Z'),
    endDate: new Date('2026-10-15T00:00:00.000Z'),
    fulfilmentMethod: 'pickup',
    pricing: {
      baseAmount: 510,
      securityDeposit: 300,
      damageWaiverFee: 0,
      platformFee: 0,
      total: 810,
      currency: 'MYR',
    },
    status,
  })));

  const availability = await request(app)
    .get('/api/v1/listings/l-camera/availability');
  assert.equal(availability.status, 200);
  assert.equal(availability.body.data.unavailableRanges.length, 0);

  const explore = await request(app).get(
    '/api/v1/listings?availableFrom=2026-10-10T00:00:00.000Z&availableTo=2026-10-16T00:00:00.000Z',
  );
  assert.equal(
    explore.body.data.some((item) => item.id === 'l-camera'),
    true,
  );
});

test('active and unresolved disputed physical rentals occupy dates', async () => {
  for (const status of ['active', 'disputed']) {
    const booking = await BookingModel.create({
      publicId: `RH-BKG-2026-${status.toUpperCase()}`,
      listingId: 'l-camera',
      listingTitle: 'Sony Alpha Camera',
      listingType: 'physical',
      renterId: `u-${status}`,
      renterName: status,
      ownerId: 'u-owner',
      startDate: new Date('2026-10-10T00:00:00.000Z'),
      endDate: new Date('2026-10-15T00:00:00.000Z'),
      fulfilmentMethod: 'pickup',
      pricing: {
        baseAmount: 510,
        securityDeposit: 300,
        damageWaiverFee: 0,
        platformFee: 0,
        total: 810,
        currency: 'MYR',
      },
      status,
    });
    const explore = await request(app).get(
      '/api/v1/listings?availableFrom=2026-10-12T00:00:00.000Z&availableTo=2026-10-15T00:00:00.000Z',
    );
    assert.equal(
      explore.body.data.some((item) => item.id === 'l-camera'),
      false,
      status,
    );
    await BookingModel.deleteOne({ publicId: booking.publicId });
  }
});

test('approval expires only competing pending physical requests and releases authorization', async () => {
  await request(app)
    .post('/api/v1/users/session')
    .set({
      ...renter,
      'x-user-id': 'u-renter-two',
      'x-user-email': 'renter2@renthub.my',
      'x-user-name': 'Mei Ling',
    });
  await approveTestIdentity('u-renter-two');
  const first = await createCameraBooking({
    idempotencyKey: 'booking-test:approval-race-a',
  });
  const second = await request(app)
    .post('/api/v1/bookings')
    .set({ ...renter, 'x-user-id': 'u-renter-two' })
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:approval-race-b',
      startDate: '2026-09-20T00:00:00.000Z',
      endDate: '2026-09-22T00:00:00.000Z',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  const nonOverlapping = await request(app)
    .post('/api/v1/bookings')
    .set({ ...renter, 'x-user-id': 'u-renter-two' })
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'booking-test:approval-race-non-overlap',
      startDate: '2026-09-23',
      endDate: '2026-09-24',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.equal(nonOverlapping.status, 201);
  await authorizeBooking(first.body.data.id);
  await authorizeBooking(second.body.data.id, {
    ...renter,
    'x-user-id': 'u-renter-two',
  });
  const firstApproval = await request(app)
    .patch(`/api/v1/bookings/${first.body.data.id}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  assert.equal(firstApproval.status, 200);
  const competing = await BookingModel.findOne({
    publicId: second.body.data.id,
  }).lean();
  const unaffected = await BookingModel.findOne({
    publicId: nonOverlapping.body.data.id,
  }).lean();
  assert.equal(competing.status, 'expired');
  assert.equal(competing.paymentStatus, 'voided');
  assert.match(competing.cancellationReason, /another overlapping request/i);
  assert.ok(competing.expiredAt);
  assert.equal(unaffected.status, 'pending');
  const authorization = await PaymentModel.findOne({
    bookingId: second.body.data.id,
    type: 'authorization',
  }).lean();
  assert.equal(authorization.status, 'voided');
  const notification = await NotificationModel.findOne({
    userId: 'u-renter-two',
    entityId: second.body.data.id,
    type: 'booking_dates_unavailable',
  }).lean();
  assert.ok(notification);
  const secondApproval = await request(app)
    .patch(`/api/v1/bookings/${second.body.data.id}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  assert.equal(secondApproval.status, 409);
  assert.equal(secondApproval.body.error.code, 'INVALID_BOOKING_STATE');
});

test('runs service approval, delivery and renter completion lifecycle', async () => {
  await applyReferral(serviceOwner);
  const created = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-photo',
      idempotencyKey: 'booking-test:service-lifecycle',
      startDate: '2026-10-03T14:00:00.000Z',
      endDate: '2026-10-03T14:00:00.000Z',
      serviceVenue: 'Glasshouse Seputeh, Kuala Lumpur',
      serviceLocation: { displayAddress: 'Glasshouse Seputeh, Kuala Lumpur', coordinates: { latitude: 3.11, longitude: 101.68 } },
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
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
    'platform_retention',
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
  const referral = await ReferralModel.findOne({ refereeId: 'u-renter' }).lean();
  assert.equal(referral.status, 'rewarded');
  assert.equal(referral.qualifyingBookingId, bookingId);
  assert.equal(
    await RewardLedgerModel.countDocuments({ sourceId: referral.publicId }),
    2,
  );
  assert.equal((await LoyaltyAccountModel.findOne({ userId: 'u-aina' })).points, 250);
});

test('publishes, edits, flags and moderates participant reviews', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app)
    .patch(`/api/v1/bookings/${bookingId}/decision`)
    .set(owner)
    .send({ status: 'approved' });
  const rental = await RentalModel.findOne({ bookingId });

  const tooEarly = await request(app)
    .post('/api/v1/reviews')
    .set(renter)
    .send({
      rentalId: rental.publicId,
      overallRating: 5,
      communicationRating: 5,
      text: 'A review cannot be submitted before this rental is completed.',
    });
  assert.equal(tooEarly.status, 409);
  assert.equal(tooEarly.body.error.code, 'REVIEW_NOT_AVAILABLE');

  rental.status = 'completed';
  await rental.save();

  const outsider = await request(app)
    .post('/api/v1/reviews')
    .set(serviceOwner)
    .send({
      rentalId: rental.publicId,
      overallRating: 5,
      communicationRating: 5,
      text: 'A non-participant must not be able to review this rental.',
    });
  assert.equal(outsider.status, 404);

  const submitted = await request(app)
    .post('/api/v1/reviews')
    .set(renter)
    .send({
      rentalId: rental.publicId,
      overallRating: 5,
      conditionRating: 5,
      communicationRating: 4,
      valueRating: 5,
      text: 'The camera was excellent and the Owner communicated clearly.',
    });
  assert.equal(submitted.status, 201, JSON.stringify(submitted.body));
  assert.equal(submitted.body.data.subjectId, 'u-owner');
  assert.equal(submitted.body.data.canEdit, true);
  const reviewId = submitted.body.data.id;

  const duplicate = await request(app)
    .post('/api/v1/reviews')
    .set(renter)
    .send({
      rentalId: rental.publicId,
      overallRating: 5,
      communicationRating: 5,
      text: 'This duplicate review must not be accepted by the API.',
    });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error.code, 'REVIEW_ALREADY_EXISTS');

  const edited = await request(app)
    .patch(`/api/v1/reviews/${reviewId}`)
    .set(renter)
    .send({
      overallRating: 4,
      conditionRating: 5,
      communicationRating: 4,
      valueRating: 4,
      text: 'The camera remained excellent and collection was straightforward.',
    });
  assert.equal(edited.status, 200);
  assert.equal(edited.body.data.overallRating, 4);
  assert.ok(edited.body.data.editedAt);

  await ReviewModel.collection.updateOne(
    { publicId: reviewId },
    { $set: { createdAt: new Date(Date.now() - 25 * 60 * 60 * 1000) } },
  );
  const lateEdit = await request(app)
    .patch(`/api/v1/reviews/${reviewId}`)
    .set(renter)
    .send({
      overallRating: 5,
      conditionRating: 5,
      communicationRating: 5,
      valueRating: 5,
      text: 'This edit is outside the permitted twenty-four hour window.',
    });
  assert.equal(lateEdit.status, 409);
  assert.equal(lateEdit.body.error.code, 'EDIT_WINDOW_ENDED');

  const ownerReview = await request(app)
    .post('/api/v1/reviews')
    .set(owner)
    .send({
      rentalId: rental.publicId,
      overallRating: 5,
      conditionRating: 1,
      communicationRating: 5,
      valueRating: 1,
      text: 'Alex coordinated collection and returned the full kit on time.',
    });
  assert.equal(ownerReview.status, 201);
  assert.equal(ownerReview.body.data.subjectId, 'u-renter');
  assert.equal(ownerReview.body.data.conditionRating, undefined);
  assert.equal(ownerReview.body.data.valueRating, undefined);

  const renterReceived = await request(app)
    .get('/api/v1/reviews/received')
    .set(renter);
  assert.equal(renterReceived.body.meta.total, 1);
  assert.equal(renterReceived.body.data[0].id, ownerReview.body.data.id);

  const publicReviews = await request(app).get('/api/v1/reviews/listing/l-camera');
  assert.equal(publicReviews.status, 200);
  assert.equal(publicReviews.body.meta.total, 1);
  assert.equal(publicReviews.body.data[0].id, reviewId);

  const summary = await request(app).get('/api/v1/reviews/subjects/u-owner/summary');
  assert.equal(summary.body.data.averageRating, 4);
  assert.equal(summary.body.data.reviewCount, 1);

  const flagged = await request(app)
    .post(`/api/v1/reviews/${reviewId}/flag`)
    .set(owner)
    .send({ reason: 'This review requires a factual moderation check.' });
  assert.equal(flagged.status, 200);
  assert.ok(flagged.body.data.flag.flaggedAt);

  const queue = await request(app)
    .get('/api/v1/reviews/admin?flagged=true')
    .set(admin);
  assert.equal(queue.status, 200);
  assert.equal(queue.body.meta.total, 1);

  const hidden = await request(app)
    .patch(`/api/v1/reviews/${reviewId}/moderation`)
    .set(admin)
    .send({ status: 'hidden', reason: 'Hidden while evidence is reviewed.' });
  assert.equal(hidden.status, 200);
  assert.equal(hidden.body.data.status, 'hidden');

  const hiddenPublic = await request(app).get('/api/v1/reviews/listing/l-camera');
  assert.equal(hiddenPublic.body.meta.total, 0);
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


test('future approval waits for the Malaysian start day and does not capture payment early', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  rental.startDate = new Date('2099-01-01T00:00:00Z');
  rental.endDate = new Date('2099-01-02T00:00:00Z');
  await rental.save();
  const response = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Good', notes: 'A small mark on the base', evidence: ['local://handover/future.jpg'] });
  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'HANDOVER_TOO_EARLY');
  assert.equal((await RentalModel.findOne({ bookingId })).status, 'scheduled');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 0);
  rental.startDate = physicalRentalDate(new Date());
  await rental.save();
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Good', notes: 'A small mark on the base', evidence: ['local://handover/future.jpg'] }).expect(200);
});

test('handover requires owned photo evidence and preserves the actual condition for both parties', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-20T04:00:00Z') });
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  async function asset(id, overrides = {}) {
    await UploadAssetModel.create({ publicId: `UPL-${id}`, uploadedBy: 'u-owner', purpose: 'handover_evidence',
      visibility: 'private', originalName: 'condition.jpg', contentType: 'image/jpeg', size: 100,
      storageProvider: 'local', storagePath: `private/test-${id}`, sha256: 'a'.repeat(64), ...overrides });
    return `upload://UPL-${id}`;
  }
  const foreign = await asset('FOREIGN', { uploadedBy: 'u-renter' });
  const wrongPurpose = await asset('PURPOSE', { purpose: 'listing_image' });
  const pdf = await asset('PDF', { contentType: 'application/pdf', originalName: 'file.pdf' });
  const photo = await asset('PHOTO');
  for (const evidence of [[], [foreign], [wrongPurpose], [pdf], [photo, photo]]) {
    const response = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
      .send({ condition: 'Fair', notes: 'Visible scratch on the base', evidence });
    assert.ok([400, 422].includes(response.status), JSON.stringify(response.body));
    assert.equal((await RentalModel.findOne({ bookingId })).status, 'scheduled');
  }
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(renter)
    .send({ condition: 'Fair', evidence: [photo] }).expect(404);
  const response = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Fair', notes: 'Visible scratch on the base', evidence: [photo] }).expect(200);
  assert.equal(response.body.data.handover.condition, 'Fair');
  assert.equal(response.body.data.handover.notes, 'Visible scratch on the base');
  assert.ok(response.body.data.handover.recordedAt);
  for (const headers of [renter, owner]) {
    const record = await request(app).get(`/api/v1/rentals/${rental.publicId}`).set(headers).expect(200);
    assert.deepEqual(record.body.data.handover.evidence, [photo]);
  }
  await request(app).get(`/api/v1/rentals/${rental.publicId}`).set(serviceOwner).expect(404);
  const photoId = photo.split('://')[1];
  await uploadService.getPrivate({ authId: 'u-renter', roles: ['renter'] }, photoId);
  await assert.rejects(() => uploadService.getPrivate({ authId: 'u-aina', roles: ['owner'] }, photoId),
    (error) => error.code === 'FORBIDDEN');
  await assert.rejects(() => uploadService.remove({ authId: 'u-owner', roles: ['owner'] }, photoId),
    (error) => error.code === 'UPLOAD_IN_USE');
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: [photo] }).expect(409);
  assert.equal((await RentalModel.findOne({ bookingId })).handover.condition, 'Fair');
});


test('booking search and filters apply before pagination/counting and retain participant isolation', async () => {
  const first = await createCameraBooking();
  const template = (await BookingModel.findOne({ publicId: first.body.data.id })).toObject();
  delete template._id;
  delete template.__v;
  const rows = Array.from({ length: 34 }, (_, i) => ({ ...template,
    publicId: `RH-BKG-2026-FILTER${String(i).padStart(3, '0')}`, listingTitle: `Filter camera ${i}`,
    status: i % 2 ? 'completed' : 'approved', paymentStatus: i % 2 ? 'captured' : 'authorized',
    category: i % 2 ? 'Equipment' : 'Devices',
    startDate: new Date('2026-11-20T00:00:00Z'), endDate: new Date('2026-11-24T00:00:00Z'),
    createdAt: new Date(Date.UTC(2026, 10, 1, 0, i)),
  }));
  rows[33].listingTitle = 'Needle [Pro]+ camera';
  rows.push({ ...rows[33], publicId: 'RH-BKG-2026-FOREIGN01', renterId: 'someone-else', ownerId: 'another-owner' });
  await BookingModel.create(rows);
  const second = await request(app).get('/api/v1/bookings/mine?q=Filter&limit=10&page=2&sort=oldest').set(renter).expect(200);
  assert.equal(second.body.meta.total, 34);
  assert.equal(second.body.data.length, 10);
  assert.equal(second.body.data[0].id, 'RH-BKG-2026-FILTER010');
  const literalSearch = await request(app).get('/api/v1/bookings/mine').query({ q: '[Pro]+', limit: 10 }).set(renter).expect(200);
  assert.equal(literalSearch.body.meta.total, 1);
  assert.equal(literalSearch.body.data[0].id, 'RH-BKG-2026-FILTER033');
  const filtered = await request(app).get('/api/v1/bookings/owner').query({ q: 'Filter', status: 'approved', category: 'Devices', listingType: 'physical', paymentStatus: 'authorized', fromDate: '2026-11-22', toDate: '2026-11-22', limit: 10 }).set(owner).expect(200);
  assert.equal(filtered.body.meta.total, 17);
  assert.ok(filtered.body.data.every((row) => row.ownerId === 'u-owner' && row.status === 'approved'));
  const absent = await request(app).get('/api/v1/bookings/mine?fromDate=2026-11-25&toDate=2026-11-26&q=Filter').set(renter).expect(200);
  assert.equal(absent.body.meta.total, 0);
  for (const query of [{ q: 'a'.repeat(101) }, { status: 'wrong' }, { listingType: 'wrong' }, { sort: 'wrong' },
    { fromDate: '2026-02-30' }, { fromDate: '2026-12-01', toDate: '2026-11-01' }, { paymentStatus: 'wrong' }, { q: { $ne: '' } }]) {
    await request(app).get('/api/v1/bookings/mine').query(query).set(renter).expect(422);
  }
});


test('unpaid checkout has one fixed ten-minute window, initial notice and one reminder', async () => {
  const created = await createCameraBooking();
  assert.equal(created.status, 201);
  const id = created.body.data.id;
  const booking = await BookingModel.findOne({ publicId: id });
  const remaining = booking.paymentDueAt - booking.createdAt;
  assert.ok(remaining > 599_000 && remaining <= 600_100);
  assert.ok(created.body.data.serverNow);
  assert.equal(await NotificationModel.countDocuments({ userId: 'u-renter', type: 'booking_payment_due' }), 1);
  const oldDue = booking.paymentDueAt.toISOString();
  await request(app).get(`/api/v1/bookings/${id}`).set(renter).expect(200);
  assert.equal((await BookingModel.findOne({ publicId: id })).paymentDueAt.toISOString(), oldDue);
  const reminderTime = new Date(booking.paymentDueAt.getTime() - 120_000);
  await runPaymentDeadlineJobs({ now: reminderTime });
  await runPaymentDeadlineJobs({ now: reminderTime });
  assert.equal(await NotificationModel.countDocuments({ type: 'booking_payment_reminder' }), 1);
  assert.equal((await BookingModel.findOne({ publicId: id })).status, 'pending');
  await authorizeBooking(id);
  const ownerRequests = await request(app).get('/api/v1/bookings/owner').set(owner).expect(200);
  assert.equal(ownerRequests.body.meta.summary.pending, 1);
  await runPaymentDeadlineJobs({ now: new Date(booking.paymentDueAt.getTime() + 1) });
  const paid = await BookingModel.findOne({ publicId: id });
  assert.equal(paid.status, 'pending');
  assert.equal(paid.paymentStatus, 'authorized');
});

test('unpaid checkout expires at ten minutes and cannot be paid or revived by reopening', async () => {
  const created = await createCameraBooking();
  const id = created.body.data.id;
  const booking = await BookingModel.findOne({ publicId: id });
  const due = booking.paymentDueAt;
  await runPaymentDeadlineJobs({ now: new Date(due.getTime() - 1) });
  assert.equal((await BookingModel.findOne({ publicId: id })).status, 'pending');
  await runPaymentDeadlineJobs({ now: due });
  await runPaymentDeadlineJobs({ now: new Date(due.getTime() + 1) });
  const expired = await BookingModel.findOne({ publicId: id });
  assert.equal(expired.status, 'expired');
  assert.equal(expired.paymentStatus, 'unpaid');
  assert.match(expired.cancellationReason, /10 minutes/);
  assert.equal(await PaymentModel.countDocuments({ bookingId: id }), 0);
  assert.equal(await NotificationModel.countDocuments({ userId: 'u-renter', type: 'booking_expired' }), 1);
  const attempt = await request(app).post('/api/v1/payments/authorizations').set(renter)
    .send({ bookingId: id, method: 'card', idempotencyKey: `authorize:${id}` });
  assert.equal(attempt.status, 409);
  assert.equal(attempt.body.error.code, 'PAYMENT_WINDOW_EXPIRED');
  const reopened = await request(app).get(`/api/v1/bookings/${id}`).set(renter).expect(200);
  assert.equal(reopened.body.data.status, 'expired');
  assert.equal(reopened.body.data.paymentDueAt, due.toISOString());
});

test('legacy unpaid deadlines derive from original creation, with lazy expiry on read', async () => {
  const created = await createCameraBooking();
  const id = created.body.data.id;
  const old = new Date(Date.now() - 11 * 60_000);
  await BookingModel.collection.updateOne({ publicId: id }, { $unset: { paymentDueAt: 1 }, $set: { createdAt: old } });
  const response = await request(app).get(`/api/v1/bookings/${id}`).set(renter).expect(200);
  assert.equal(response.body.data.status, 'expired');
  assert.equal(new Date(response.body.data.paymentDueAt).getTime(), old.getTime() + 600_000);
});

test('payment crossing its deadline cannot commit an authorization', async () => {
  const created = await createCameraBooking();
  const id = created.body.data.id;
  const original = paymentAdapter.authorize;
  try {
    paymentAdapter.authorize = async (input) => {
      const result = await original.call(paymentAdapter, input);
      await BookingModel.updateOne({ publicId: id }, { $set: { paymentDueAt: new Date(Date.now() - 1) } });
      return result;
    };
    const response = await request(app).post('/api/v1/payments/authorizations').set(renter)
      .send({ bookingId: id, method: 'card', idempotencyKey: `authorize:${id}` });
    assert.equal(response.status, 409);
    assert.equal((await BookingModel.findOne({ publicId: id })).status, 'expired');
    assert.equal(await PaymentModel.countDocuments({ bookingId: id, status: 'authorized' }), 0);
  } finally { paymentAdapter.authorize = original; }
});

test('a durable timely payment is recovered instead of expiring as unpaid', async () => {
  const created = await createCameraBooking();
  const id = created.body.data.id;
  await authorizeBooking(id);
  const payment = await PaymentModel.findOne({ bookingId: id, type: 'authorization' });
  const due = new Date(payment.createdAt.getTime() + 1000);
  await BookingModel.updateOne({ publicId: id }, { $set: { paymentStatus: 'unpaid', paymentDueAt: due }, $unset: { paymentAuthorizationId: 1 } });
  await runPaymentDeadlineJobs({ now: new Date(due.getTime() + 1) });
  const recovered = await BookingModel.findOne({ publicId: id });
  assert.equal(recovered.status, 'pending');
  assert.equal(recovered.paymentStatus, 'authorized');
  assert.equal(recovered.paymentAuthorizationId, payment.publicId);
  assert.equal(await NotificationModel.countDocuments({ type: 'payment_authorized' }), 1);
});

async function submittedReceipt(t) {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-20T04:00:00Z') });
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  const input = { condition: 'Fair', notes: 'Existing mark on the base', evidence: ['local://handover/receipt.jpg'] };
  const response = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner).send(input).expect(200);
  return { bookingId, rentalId: rental.publicId, handoverId: response.body.data.handover.handoverId, input };
}

test('Owner submission is immutable, keeps the hold and dates, and cannot bypass renter receipt', async t => {
  const { bookingId, rentalId, handoverId, input } = await submittedReceipt(t);
  const rental = await RentalModel.findOne({ publicId: rentalId }), booking = await BookingModel.findOne({ publicId: bookingId });
  assert.equal(rental.status, 'scheduled'); assert.equal(booking.status, 'approved');
  assert.equal(booking.paymentStatus, 'authorized'); assert.equal(rental.handover.receiptStatus, 'pending');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 0);
  assert.equal(await RewardLedgerModel.countDocuments({ type: 'rental_completed' }), 0);
  const again = await request(app).post(`/api/v1/rentals/${rentalId}/handover`).set(owner).send(input).expect(200);
  assert.equal(again.body.data.handover.handoverId, handoverId);
  await request(app).post(`/api/v1/rentals/${rentalId}/handover`).set(owner).send({ ...input, condition: 'Excellent' }).expect(409);
  const blocked = await request(app).post(`/api/v1/bookings/${bookingId}/cancel`).set(renter).send({ reason: 'Changed my mind' }).expect(409);
  assert.equal(blocked.body.error.code, 'HANDOVER_CANCELLATION_BLOCKED');
  await request(app).post(`/api/v1/rentals/${rentalId}/return`).set(renter).send(input).expect(409);
  await request(app).post(`/api/v1/rentals/${rentalId}/extensions`).set(renter).send({ requestedEndDate: '2026-09-25', reason: 'More project time' }).expect(409);
  const authMode = env.authMode;
  try {
    env.authMode = 'local';
    await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).send({ handoverId }).expect(401);
  } finally { env.authMode = authMode; }
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(owner).send({ handoverId }).expect(404);
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId: 'bad' }).expect(422);
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId: '00000000-0000-4000-8000-000000000001' }).expect(409);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_handover' }), 1);
  assert.equal((await RentalModel.findById(rental._id)).endDate.getTime(), rental.endDate.getTime());
});

test('only the actual renter can acknowledge, and concurrent retries capture once', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  const stranger = { ...renter, 'x-user-id': 'receipt-stranger', 'x-user-email': 'stranger@example.test' };
  await request(app).post('/api/v1/users/session').set(stranger).expect(201);
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(stranger).send({ handoverId }).expect(404);
  const results = await Promise.all([1, 2].map(() => acknowledgeHandover(rentalId)));
  assert.ok(results.every(r => r.body.data.status === 'active'));
  const rental = await RentalModel.findOne({ publicId: rentalId }), booking = await BookingModel.findOne({ publicId: bookingId });
  assert.equal(rental.handover.receiptStatus, 'acknowledged'); assert.equal(rental.handover.acknowledgedBy, 'u-renter');
  assert.ok(rental.handover.acceptedAt); assert.ok(rental.handover.acknowledgedAt);
  assert.equal(booking.status, 'active'); assert.equal(booking.paymentStatus, 'captured');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 1);
  assert.equal(await NotificationModel.countDocuments({ type: 'handover_acknowledged' }), 2);
});

test('missing authorization blocks receipt before a financial intent is created', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  await PaymentModel.updateMany({ bookingId, type: 'authorization' }, { $set: { status: 'voided' } });
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }).expect(409);
  assert.equal(await LifecycleOperationModel.countDocuments({ _id: `handover-receipt:${handoverId}` }), 0);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'scheduled');
});

test('a durable timely receipt recovers capture after a failure and after the booked dates end', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  const capture = paymentAdapter.capture;
  let calls = 0;
  t.mock.method(paymentAdapter, 'capture', async input => { if (++calls === 1) throw new Error('Disposable capture failure'); return capture(input); });
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }).expect(500);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).handover.receiptStatus, 'processing');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'approved');
  t.mock.timers.tick(5 * 86400000);
  const recovered = await request(app).get(`/api/v1/rentals/${rentalId}`).set(renter).expect(200);
  assert.equal(recovered.body.data.status, 'active');
  assert.equal(recovered.body.data.handover.receiptStatus, 'acknowledged');
  await acknowledgeHandover(rentalId);
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 1);
  assert.equal((await LifecycleOperationModel.findById(`handover-receipt:${handoverId}`)).status, 'done');
});

test('a handover issue blocks acknowledgement without automatically capturing or cancelling', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  await request(app).post('/api/v1/disputes').set(renter).send({ rentalId, category: 'damaged_item',
    summary: 'Condition differs', description: 'The item has a damaged corner that is not described in the handover record.' }).expect(201);
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }).expect(409);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'disputed');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: { $in: ['capture', 'refund'] } }), 0);
});

test('capture followed by an interrupted state write is recovered without a second capture', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  const update = RentalModel.updateOne.bind(RentalModel);
  let interrupted = false;
  t.mock.method(RentalModel, 'updateOne', async (...args) => {
    if (!interrupted && args[1]?.$set?.status === 'active') { interrupted = true; throw new Error('Disposable state interruption'); }
    return update(...args);
  });
  await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }).expect(500);
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 1);
  await request(app).get(`/api/v1/rentals/${rentalId}`).set(renter).expect(200);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'active');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).paymentStatus, 'captured');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 1);
});

test('a new late receipt is blocked and does not release its payment hold', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  t.mock.timers.tick(5 * 86400000);
  await request(app).get(`/api/v1/rentals/${rentalId}`).set(renter).expect(200);
  const late = await request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }).expect(409);
  assert.equal(late.body.error.code, 'HANDOVER_WINDOW_CLOSED');
  assert.ok((await RentalModel.findOne({ publicId: rentalId })).handover.reviewNeededAt);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).paymentStatus, 'authorized');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), 0);
});

test('receipt racing cancellation and an issue cannot bypass lifecycle locks', async t => {
  const { bookingId, rentalId, handoverId } = await submittedReceipt(t);
  const [ack, cancel, issue] = await Promise.all([
    request(app).post(`/api/v1/rentals/${rentalId}/handover/acknowledge`).set(renter).send({ handoverId }),
    request(app).post(`/api/v1/bookings/${bookingId}/cancel`).set(renter).send({ reason: 'Concurrent cancellation' }),
    request(app).post('/api/v1/disputes').set(renter).send({ rentalId, category: 'damaged_item', summary: 'Condition concern',
      description: 'The received item differs from the condition recorded in the handover photos.' }),
  ]);
  assert.equal(cancel.status, 409); assert.equal(issue.status, 201);
  assert.ok([200, 409].includes(ack.status));
  const rental = await RentalModel.findOne({ publicId: rentalId });
  assert.equal(rental.status, 'disputed');
  assert.equal(await PaymentModel.countDocuments({ bookingId, type: 'capture' }), rental.handover.receiptStatus === 'acknowledged' ? 1 : 0);
  assert.equal(await PaymentModel.countDocuments({ bookingId, status: 'voided' }), 0);
});
