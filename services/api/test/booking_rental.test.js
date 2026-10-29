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
import { ReviewModel } from '../src/modules/review/review.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { blockchainAdapter } from '../src/integrations/blockchainAdapter.js';

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
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    AvailabilityModel.deleteMany({}),
    BookingModel.deleteMany({}),
    BookingRequestLockModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    ThreadModel.deleteMany({}),
    RentalModel.deleteMany({}),
    ReviewModel.deleteMany({}),
    LoyaltyAccountModel.deleteMany({}),
    LoyaltyConfigModel.deleteMany({}),
    ReferralModel.deleteMany({}),
    RewardLedgerModel.deleteMany({}),
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
  assert.equal(ownerRequests.body.meta.summary.pending, 1);

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

test('vehicle requests enforce MyKad, independent eligibility, validity through rental and exact required class', async () => {
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
  const validHandover = await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Good', notes: 'Synthetic handover', evidence: ['local://handover/test.jpg'] });
  assert.equal(validHandover.status, 200);
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

test('legacy paid pending requests block duplicates after their payment timer, ahead of newer unpaid duplicates', async () => {
  const first = await createCameraBooking();
  const id = first.body.data.id;
  await authorizeBooking(id);
  await BookingModel.updateOne({ publicId: id }, { $set: { expiresAt: new Date(Date.now() - 1000) } });
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

test('runs physical approval, handover, extension and return lifecycle', async () => {
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

test('double handover and double return confirmation do not duplicate captures or settlements', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  const handovers = await Promise.all([1, 2].map(() => request(app)
    .post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: ['local://handover/front.jpg'] })));
  assert.deepEqual(handovers.map((r) => r.status).sort(), [200, 409]);
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

test('extension cannot overlap an unresolved disputed rental or be approved after return submission', async () => {
  const created = await createCameraBooking();
  const bookingId = created.body.data.id;
  await authorizeBooking(bookingId);
  await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const rental = await RentalModel.findOne({ bookingId });
  await request(app).post(`/api/v1/rentals/${rental.publicId}/handover`).set(owner)
    .send({ condition: 'Excellent', evidence: ['local://handover/front.jpg'] }).expect(200);
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
