import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { runLifecycleJobs } from '../src/operations/lifecycleJobs.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { adminModule } from '../src/modules/admin/index.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';

let mongodb;

function booking(overrides) {
  return {
    publicId: `RH-BKG-2026-${overrides.suffix}`,
    listingId: `listing-${overrides.suffix}`,
    listingTitle: overrides.title,
    listingType: 'physical',
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-owner',
    startDate: overrides.startDate,
    endDate: overrides.endDate,
    fulfilmentMethod: 'pickup',
    pricing: {
      baseAmount: 100,
      securityDeposit: 50,
      damageWaiverFee: 0,
      platformFee: 0,
      total: 150,
      currency: 'MYR',
    },
    paymentStatus: overrides.paymentStatus,
    status: overrides.status,
    expiresAt: overrides.expiresAt,
  };
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    BookingModel.init(),
    RentalModel.init(),
    NotificationModel.init(),
    PaymentModel.init(),
    adminModule.Model.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    BookingModel.deleteMany({}),
    RentalModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    adminModule.Model.deleteMany({}),
  ]);
});

test('exposes technology health and a guarded manual run to administrators', async () => {
  const headers = {
    'x-user-id': 'u-admin',
    'x-user-email': 'admin@renthub.my',
    'x-user-name': 'Admin Farah',
    'x-user-roles': 'admin',
  };
  const health = await request(app)
    .get('/api/v1/admin/technology-health')
    .set(headers);
  assert.equal(health.status, 200);
  assert.equal(health.body.data.components.database.status, 'up');
  assert.ok(health.body.data.components.lifecycle);

  const run = await request(app)
    .post('/api/v1/admin/lifecycle/run')
    .set(headers);
  assert.equal(run.status, 200);
  assert.equal(run.body.data.result.expiredBookings, 0);
  assert.equal(await adminModule.Model.countDocuments(), 1);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('expires abandoned bookings and marks physical rentals overdue once', async () => {
  const now = new Date('2026-09-30T12:00:00.000Z');
  await BookingModel.create([
    booking({
      suffix: 'EXPIRED1',
      title: 'Unpaid camera booking',
      startDate: new Date('2026-10-02T12:00:00.000Z'),
      endDate: new Date('2026-10-03T12:00:00.000Z'),
      status: 'pending',
      paymentStatus: 'unpaid',
      expiresAt: new Date('2026-09-30T11:00:00.000Z'),
    }),
    booking({
      suffix: 'ACTIVE01',
      title: 'Overdue camera rental',
      startDate: new Date('2026-09-25T12:00:00.000Z'),
      endDate: new Date('2026-09-29T12:00:00.000Z'),
      status: 'active',
      paymentStatus: 'captured',
    }),
  ]);
  await RentalModel.create({
    publicId: 'RH-RNT-2026-OVERDUE1',
    bookingId: 'RH-BKG-2026-ACTIVE01',
    listingId: 'listing-ACTIVE01',
    listingType: 'physical',
    renterId: 'u-renter',
    ownerId: 'u-owner',
    startDate: new Date('2026-09-25T12:00:00.000Z'),
    endDate: new Date('2026-09-29T12:00:00.000Z'),
    status: 'active',
  });

  const first = await runLifecycleJobs({ now });
  assert.equal(first.expiredBookings, 1);
  assert.equal(first.overdueRentals, 1);
  assert.equal(
    (await BookingModel.findOne({ publicId: 'RH-BKG-2026-EXPIRED1' })).status,
    'expired',
  );
  assert.equal(
    (await RentalModel.findOne({ publicId: 'RH-RNT-2026-OVERDUE1' })).status,
    'overdue',
  );
  assert.equal(await NotificationModel.countDocuments(), 4);

  const second = await runLifecycleJobs({ now });
  assert.equal(second.expiredBookings, 0);
  assert.equal(second.overdueRentals, 0);
  assert.equal(await NotificationModel.countDocuments(), 4);
});
