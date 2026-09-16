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
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from '../src/modules/loyalty/loyalty.model.js';
import { awardRentalCompletion } from '../src/modules/loyalty/loyalty.service.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { UserModel } from '../src/modules/user/user.model.js';

let mongodb;

const identity = (id, roles, name) => ({
  'x-user-id': id,
  'x-user-email': `${id}@renthub.my`,
  'x-user-name': name,
  'x-user-roles': roles,
});

const renter = identity('u-renter', 'renter', 'Alex Tan');
const referrer = identity('u-referrer', 'renter,owner', 'Sarah Lim');
const admin = identity('u-admin', 'admin', 'Admin Farah');

async function profiles() {
  for (const headers of [renter, referrer, admin]) {
    const response = await request(app).post('/api/v1/users/session').set(headers);
    assert.equal(response.status, 201);
  }
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    BookingModel.init(),
    RentalModel.init(),
    LoyaltyAccountModel.init(),
    RewardLedgerModel.init(),
    ReferralModel.init(),
    LoyaltyConfigModel.init(),
    NotificationModel.init(),
    adminModule.Model.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    BookingModel.deleteMany({}),
    RentalModel.deleteMany({}),
    LoyaltyAccountModel.deleteMany({}),
    RewardLedgerModel.deleteMany({}),
    ReferralModel.deleteMany({}),
    LoyaltyConfigModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    adminModule.Model.deleteMany({}),
  ]);
  await profiles();
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('awards completion and first-booking referral rewards idempotently', async () => {
  const referrerSummary = await request(app)
    .get('/api/v1/rewards/summary')
    .set(referrer);
  assert.equal(referrerSummary.status, 200);
  const code = referrerSummary.body.data.referralCode;

  const applied = await request(app)
    .post('/api/v1/rewards/referrals/apply')
    .set(renter)
    .send({ referralCode: code.toLowerCase() });
  assert.equal(applied.status, 201, JSON.stringify(applied.body));
  assert.equal(applied.body.data.status, 'pending');

  const booking = await BookingModel.create({
    publicId: 'RH-SVC-2026-LOYAL001',
    listingId: 'l-photo',
    listingTitle: 'Event Photography Package',
    listingType: 'service',
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-referrer',
    startDate: new Date('2026-10-01T10:00:00Z'),
    endDate: new Date('2026-10-01T13:00:00Z'),
    serviceVenue: 'Kuala Lumpur',
    pricing: {
      baseAmount: 450,
      securityDeposit: 0,
      damageWaiverFee: 0,
      platformFee: 0,
      total: 450,
      currency: 'MYR',
    },
    paymentStatus: 'settled',
    status: 'completed',
  });
  const rental = await RentalModel.create({
    publicId: 'RH-RNT-2026-LOYAL001',
    bookingId: booking.publicId,
    listingId: 'l-photo',
    listingType: 'service',
    renterId: 'u-renter',
    ownerId: 'u-referrer',
    startDate: booking.startDate,
    endDate: booking.endDate,
    status: 'completed',
  });

  await awardRentalCompletion(rental, booking);
  await awardRentalCompletion(rental, booking);

  const renterSummary = await request(app)
    .get('/api/v1/rewards/summary')
    .set(renter);
  const updatedReferrer = await request(app)
    .get('/api/v1/rewards/summary')
    .set(referrer);
  assert.equal(renterSummary.body.data.points, 100);
  assert.equal(updatedReferrer.body.data.points, 250);
  assert.equal(renterSummary.body.data.referral.status, 'rewarded');
  assert.equal(
    renterSummary.body.data.ledger.filter(
      (entry) => entry.type === 'service_completed',
    ).length,
    1,
  );
  const welcome = renterSummary.body.data.ledger.find(
    (entry) => entry.type === 'referral_welcome',
  );
  assert.equal(welcome.reward.discountAmount, 5);
  assert.equal(await NotificationModel.countDocuments({ category: 'loyalty' }), 3);
});

test('redeems configured rewards and audits administrator rule changes', async () => {
  const forbidden = await request(app)
    .get('/api/v1/rewards/admin/config')
    .set(renter);
  assert.equal(forbidden.status, 403);

  const updated = await request(app)
    .put('/api/v1/rewards/admin/config')
    .set(admin)
    .send({
      enabled: true,
      physicalCompletionPoints: 600,
      serviceCompletionPoints: 400,
      referralRewardPoints: 300,
      refereeDiscountAmount: 8,
      redemptionOptions: [
        { points: 500, discountAmount: 5 },
        { points: 1000, discountAmount: 12 },
      ],
    });
  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.data.referralRewardPoints, 300);
  assert.equal(await adminModule.Model.countDocuments(), 1);

  await BookingModel.create({
    publicId: 'RH-BKG-2026-LOYAL002',
    listingId: 'l-camera',
    listingTitle: 'Sony Alpha Camera',
    listingType: 'physical',
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-referrer',
    startDate: new Date('2026-10-02T00:00:00Z'),
    endDate: new Date('2026-10-03T00:00:00Z'),
    fulfilmentMethod: 'pickup',
    pricing: {
      baseAmount: 170,
      securityDeposit: 300,
      damageWaiverFee: 0,
      platformFee: 0,
      total: 470,
      currency: 'MYR',
    },
    paymentStatus: 'settled',
    status: 'completed',
  });
  const rental = await RentalModel.create({
    publicId: 'RH-RNT-2026-LOYAL002',
    bookingId: 'RH-BKG-2026-LOYAL002',
    listingId: 'l-camera',
    listingType: 'physical',
    renterId: 'u-renter',
    ownerId: 'u-referrer',
    startDate: new Date('2026-10-02T00:00:00Z'),
    endDate: new Date('2026-10-03T00:00:00Z'),
    status: 'completed',
  });
  await awardRentalCompletion(
    rental,
    await BookingModel.findOne({ publicId: rental.bookingId }),
  );

  const redeemed = await request(app)
    .post('/api/v1/rewards/redeem')
    .set(renter)
    .send({ points: 500 });
  assert.equal(redeemed.status, 201, JSON.stringify(redeemed.body));
  assert.equal(redeemed.body.data.points, 100);
  assert.equal(redeemed.body.data.totalRedeemed, 500);
  const reward = redeemed.body.data.ledger.find(
    (entry) => entry.type === 'redemption',
  );
  assert.equal(reward.reward.discountAmount, 5);
  assert.match(reward.reward.code, /^RH-RDM-/);

  const insufficient = await request(app)
    .post('/api/v1/rewards/redeem')
    .set(renter)
    .send({ points: 500 });
  assert.equal(insufficient.status, 409);

  const ledger = await request(app)
    .get('/api/v1/rewards/admin/ledger?type=redemption')
    .set(admin);
  assert.equal(ledger.status, 200);
  assert.equal(ledger.body.meta.total, 1);
});

test('rejects self-referrals and duplicate redemption costs', async () => {
  const summary = await request(app)
    .get('/api/v1/rewards/summary')
    .set(renter);
  const selfReferral = await request(app)
    .post('/api/v1/rewards/referrals/apply')
    .set(renter)
    .send({ referralCode: summary.body.data.referralCode });
  assert.equal(selfReferral.status, 400);
  assert.equal(selfReferral.body.error.code, 'SELF_REFERRAL');

  const invalidConfig = await request(app)
    .put('/api/v1/rewards/admin/config')
    .set(admin)
    .send({
      enabled: true,
      physicalCompletionPoints: 120,
      serviceCompletionPoints: 100,
      referralRewardPoints: 250,
      refereeDiscountAmount: 5,
      redemptionOptions: [
        { points: 500, discountAmount: 5 },
        { points: 500, discountAmount: 10 },
      ],
    });
  assert.equal(invalidConfig.status, 422);
});
