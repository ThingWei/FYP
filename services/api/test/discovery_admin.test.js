import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { adminModule } from '../src/modules/admin/index.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

let mongodb;

const renterHeaders = {
  'x-user-id': 'u-renter',
  'x-user-email': 'renter@renthub.my',
  'x-user-name': 'Alex Tan',
  'x-user-roles': 'renter',
};
const ownerHeaders = {
  'x-user-id': 'u-owner',
  'x-user-email': 'owner@renthub.my',
  'x-user-name': 'Sarah J.',
  'x-user-roles': 'owner',
};
const adminHeaders = {
  'x-user-id': 'u-admin',
  'x-user-email': 'admin@renthub.my',
  'x-user-name': 'Admin Farah',
  'x-user-roles': 'admin',
};

async function createListing({
  id,
  title,
  price,
  verified = true,
  trust = 80,
  promotion,
}) {
  return ListingModel.create({
    publicId: id,
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    ownerTrustScore: trust,
    title,
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: price,
    condition: 'Excellent',
    fulfilmentMethods: ['pickup'],
    location: 'Kuala Lumpur',
    verified,
    status: 'active',
    promotion,
    promoted: Boolean(promotion),
  });
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    adminModule.Model.init(),
    adminModule.ModerationReportModel.init(),
    adminModule.PlatformSettingModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    adminModule.Model.deleteMany({}),
    adminModule.ModerationReportModel.deleteMany({}),
    adminModule.PlatformSettingModel.deleteMany({}),
  ]);
  await Promise.all([
    request(app).post('/api/v1/users/session').set(renterHeaders),
    request(app).post('/api/v1/users/session').set(ownerHeaders),
    request(app).post('/api/v1/users/session').set(adminHeaders),
  ]);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('persists wishlist and comparison selections for active listings', async () => {
  await Promise.all([
    createListing({ id: 'l-camera', title: 'Camera Kit', price: 85 }),
    createListing({ id: 'l-lens', title: 'Portrait Lens', price: 45 }),
  ]);

  const saved = await request(app)
    .put('/api/v1/users/me/saved-listings/l-camera')
    .set(renterHeaders);
  assert.equal(saved.status, 200);
  assert.equal(saved.body.data.publicId, 'l-camera');

  const compared = await request(app)
    .put('/api/v1/users/me/comparison')
    .set(renterHeaders)
    .send({ listingIds: ['l-camera', 'l-lens'] });
  assert.equal(compared.status, 200);
  assert.deepEqual(
    compared.body.data.map((item) => item.publicId),
    ['l-camera', 'l-lens'],
  );

  const [wishlist, comparison] = await Promise.all([
    request(app).get('/api/v1/users/me/saved-listings').set(renterHeaders),
    request(app).get('/api/v1/users/me/comparison').set(renterHeaders),
  ]);
  assert.deepEqual(wishlist.body.data.map((item) => item.publicId), ['l-camera']);
  assert.equal(comparison.body.data.length, 2);

  const stored = await UserModel.findOne({ authId: 'u-renter' }).lean();
  assert.deepEqual(stored.savedListingIds, ['l-camera']);
  assert.deepEqual(stored.comparisonListingIds, ['l-camera', 'l-lens']);
});

test('filters active promotions and sorts live discovery results', async () => {
  const now = Date.now();
  await Promise.all([
    createListing({
      id: 'l-promoted-low',
      title: 'Promoted Camera',
      price: 60,
      trust: 75,
      promotion: {
        enabled: true,
        label: 'Weekend Deal',
        discountPercent: 20,
        startsAt: new Date(now - 60_000),
        endsAt: new Date(now + 86_400_000),
      },
    }),
    createListing({
      id: 'l-promoted-high',
      title: 'Premium Camera',
      price: 120,
      trust: 95,
      promotion: {
        enabled: true,
        label: 'Launch Deal',
        discountPercent: 10,
        startsAt: new Date(now - 60_000),
        endsAt: new Date(now + 86_400_000),
      },
    }),
    createListing({
      id: 'l-standard',
      title: 'Standard Camera',
      price: 40,
      verified: false,
    }),
  ]);

  const response = await request(app).get(
    '/api/v1/listings?type=physical&verified=true&promoted=true&sort=price_asc',
  );
  assert.equal(response.status, 200);
  assert.deepEqual(
    response.body.data.map((item) => item.publicId),
    ['l-promoted-low', 'l-promoted-high'],
  );
  assert.equal(response.body.data[0].promotionActive, true);
  assert.equal(response.body.data[0].effectiveDailyPrice, 48);
});

test('stores and resolves safety reports and audits platform settings', async () => {
  await createListing({ id: 'l-reported', title: 'Reported Camera', price: 90 });

  const submitted = await request(app)
    .post('/api/v1/admin/reports')
    .set(renterHeaders)
    .send({
      targetType: 'listing',
      targetId: 'l-reported',
      reason: 'misleading',
      details: 'The description does not match the displayed item.',
    });
  assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
  assert.equal(submitted.body.data.status, 'open');

  const reports = await request(app)
    .get('/api/v1/admin/reports?status=open')
    .set(adminHeaders);
  assert.equal(reports.status, 200);
  assert.equal(reports.body.data.length, 1);
  assert.equal(reports.body.data[0].targetType, 'listing');

  const resolved = await request(app)
    .patch(`/api/v1/admin/reports/${submitted.body.data.publicId}`)
    .set(adminHeaders)
    .send({
      status: 'resolved',
      resolution: 'Listing evidence reviewed and moderation action recorded.',
    });
  assert.equal(resolved.status, 200);
  assert.equal(resolved.body.data.status, 'resolved');

  const initialSettings = await request(app)
    .get('/api/v1/admin/settings')
    .set(adminHeaders);
  assert.equal(initialSettings.status, 200);
  assert.equal(initialSettings.body.data.categories.length, 6);

  const updatedSettings = await request(app)
    .put('/api/v1/admin/settings')
    .set(adminHeaders)
    .send({
      marketplaceFeePercent: 6.5,
      maintenanceMode: false,
      highValueKycEnabled: true,
      highValueThreshold: 1500,
      reportAutoHideThreshold: 4,
      verificationOcrThreshold: 85,
      supportEmail: 'help@renthub.my',
      bookingPolicy: 'Owners must approve pending bookings before fulfilment.',
      contentPolicy: 'Listings must be lawful, accurate, safe, and available.',
      notificationTemplates: {
        bookingApproved: 'Your booking was approved by the Owner.',
        verificationUpdate: 'Your verification status was updated.',
        reportResolved: 'Your safety report has been reviewed.',
      },
      categories: initialSettings.body.data.categories.map((category) => ({
        name: category.name,
        active: category.name !== 'Books',
      })),
    });
  assert.equal(updatedSettings.status, 200);
  assert.equal(updatedSettings.body.data.marketplaceFeePercent, 6.5);
  assert.equal(updatedSettings.body.data.reportAutoHideThreshold, 4);
  assert.equal(
    updatedSettings.body.data.categories.find((item) => item.name === 'Books')
      .active,
    false,
  );
  assert.equal(
    await adminModule.Model.countDocuments({
      action: { $in: ['report.resolved', 'platform.settings_updated'] },
    }),
    2,
  );
});
