import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { LISTING_CATEGORIES, ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { PlatformSettingModel } from '../src/modules/admin/platformSetting.model.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { assertMarketplaceIdentity, resolveKycRequirement } from '../src/modules/user/kycRequirements.js';

let mongodb;
const headers = (id, roles = 'renter,owner') => ({
  'x-user-id': id, 'x-user-email': `${id}@example.com`, 'x-user-name': 'Synthetic User', 'x-user-roles': roles,
});
const member = headers('u-member');
const admin = headers('u-admin', 'admin');

async function setIdentity(status, documentType = 'mykad') {
  await UserModel.updateOne({ authId: 'u-member' }, { $set: {
    'verification.status': status, 'verification.documentType': documentType,
    'verification.documents': [{ documentType, status }],
  } });
}

function listingInput(category) {
  return { title: `Synthetic ${category} listing`, category, dailyPrice: 10, location: 'Kuala Lumpur',
    ...(category === 'Services' ? { listingType: 'service', serviceDetails: {
      packageName: 'Synthetic service', durationMinutes: 60, venueMode: 'flexible',
    } } : { listingType: 'physical', condition: 'Good', fulfilmentMethods: ['pickup'],
      requiredLicenceClass: category === 'Vehicles' ? 'D' : '',
      images: ['local://listing/front.jpg', 'local://listing/back.jpg', 'local://listing/side.jpg'],
    }),
  };
}

before(async () => {
  mongodb = await MongoMemoryServer.create({ instance: { dbName: 'identity_access_test' } });
  await connectDatabase(mongodb.getUri());
  await Promise.all([UserModel.init(), ListingModel.init(), BookingModel.init(), PlatformSettingModel.init()]);
});
beforeEach(async () => {
  await Promise.all([UserModel, ListingModel, BookingModel, PaymentModel, ThreadModel, NotificationModel,
    PlatformSettingModel].map((model) => model.deleteMany({})));
  const memberSession = await request(app).post('/api/v1/users/session').set(member);
  const adminSession = await request(app).post('/api/v1/users/session').set(admin);
  assert.equal(memberSession.status, 201, JSON.stringify(memberSession.body));
  assert.equal(adminSession.status, 201, JSON.stringify(adminSession.body));
});
after(async () => { await disconnectDatabase(); await mongodb.stop(); });

test('every category and unknown future category retain the mandatory baseline under legacy settings', () => {
  const settings = { highValueKycEnabled: false, highValueThreshold: 1_000_000,
    kycRequirements: LISTING_CATEGORIES.map((category) => ({ category, documentTypes: [], highValueOnly: true })) };
  for (const category of [...LISTING_CATEGORIES, 'Future Category']) {
    const requirement = resolveKycRequirement(settings, { category, dailyPrice: 1 });
    assert.equal(requirement.required, true);
    assert.equal(requirement.highValueOnly, false);
    assert.ok(requirement.requiredDocumentTypes.includes('mykad'));
  }
});

test('passport-only, licence-only and stale aggregate approval cannot bypass MyKad approval', () => {
  for (const documentType of ['passport', 'driving_licence']) {
    assert.throws(() => assertMarketplaceIdentity({ verification: { status: 'approved', documentType,
      documents: [{ documentType, status: 'approved' }] } }, 'create_booking'), { code: 'KYC_REQUIRED' });
  }
  assert.throws(() => assertMarketplaceIdentity({ verification: { status: 'approved', documentType: 'mykad',
    documents: [{ documentType: 'mykad', status: 'pending' }] } }, 'submit_listing'), { code: 'KYC_REQUIRED' });
  assert.doesNotThrow(() => assertMarketplaceIdentity({ verification: { status: 'approved', documentType: 'mykad' } }, 'submit_listing'));
});

for (const category of LISTING_CATEGORIES) {
  test(`${category}: unapproved renters cannot book, Owners can draft but not submit/publish`, async (t) => {
    let inspections = 0;
    t.mock.method(aiClient, 'verifyItem', async () => { inspections++; return { outcome: 'approved' }; });
    const publicListing = await ListingModel.create({ ...listingInput(category), publicId: 'l-public',
      ownerId: 'u-other-owner', ownerName: 'Other Owner', status: 'active' });
    const draft = await request(app).post('/api/v1/listings').set(member).send(listingInput(category));
    assert.equal(draft.status, 201, JSON.stringify(draft.body));
    assert.equal(draft.body.data.status, 'draft');
    assert.equal((await request(app).get(`/api/v1/listings/${publicListing.publicId}`)).status, 200);
    for (const status of ['unverified', 'pending', 'rejected', 'resubmission_required', 'expired']) {
      await setIdentity(status);
      const booking = await request(app).post('/api/v1/bookings').set(member).send({
        listingId: publicListing.publicId, startDate: '2027-01-10', endDate: '2027-01-10',
        idempotencyKey: `identity-test:${category}:${status}`,
        fulfilmentMethod: 'pickup', serviceVenue: 'Kuala Lumpur',
        agreementAccepted: true, agreementVersion: 'renthub-booking-v1',
      });
      assert.equal(booking.status, 403, `${status}: ${JSON.stringify(booking.body)}`);
      assert.equal(booking.body.error.code, category === 'Vehicles' ? 'MYKAD_REQUIRED' : 'KYC_REQUIRED');
      const edited = await request(app).patch(`/api/v1/listings/${draft.body.data.id}`).set(member).send({ dailyPrice: 11 });
      assert.equal(edited.status, 200);
      const submit = await request(app).post(`/api/v1/listings/${draft.body.data.id}/submit`).set(member);
      assert.equal(submit.status, 403);
      assert.equal(submit.body.error.code, 'KYC_REQUIRED');
      assert.equal((await ListingModel.findOne({ publicId: draft.body.data.id })).status, 'draft');
      // A direct admin request must not publish a stale/legacy pending listing.
      await ListingModel.updateOne({ publicId: draft.body.data.id }, { $set: { status: 'pending_review' } });
      const publication = await request(app).patch(`/api/v1/listings/${draft.body.data.id}/moderation`).set(admin)
        .send({ status: 'active' });
      assert.equal(publication.status, 403);
      assert.equal(publication.body.error.code, 'KYC_REQUIRED');
      assert.equal((await ListingModel.findOne({ publicId: draft.body.data.id })).status, 'pending_review');
      await ListingModel.updateOne({ publicId: draft.body.data.id }, { $set: { status: 'draft' } });
    }
    assert.equal(inspections, 0);
    for (const model of [BookingModel, PaymentModel, ThreadModel, NotificationModel]) {
      assert.equal(await model.countDocuments({}), 0);
    }
    await setIdentity('approved');
    const submitted = await request(app).post(`/api/v1/listings/${draft.body.data.id}/submit`).set(member);
    assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
    const published = await request(app).patch(`/api/v1/listings/${draft.body.data.id}/moderation`).set(admin)
      .send({ status: 'active' });
    assert.equal(published.status, 200, JSON.stringify(published.body));
    assert.equal(published.body.data.verified, true);
    if (category === 'Vehicles') await UserModel.updateOne({ authId: 'u-member' }, { $set: { drivingEligibility: {
      status: 'approved', licenceClasses: ['D'], expiresAt: new Date('2035-01-01'),
      identityMatchConfirmed: true, classReviewConfirmed: true,
    } } });
    const booking = await request(app).post('/api/v1/bookings').set(member).send({
      listingId: publicListing.publicId, startDate: '2027-01-10', endDate: '2027-01-10',
      idempotencyKey: `identity-test:${category}:approved`,
      fulfilmentMethod: 'pickup', serviceVenue: 'Kuala Lumpur',
      agreementAccepted: true, agreementVersion: 'renthub-booking-v1',
    });
    assert.equal(booking.status, 201, JSON.stringify(booking.body));
  });
}
