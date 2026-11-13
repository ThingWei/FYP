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
import { physicalRentalReturnDeadline } from '../src/core/calendarDate.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { OverdueDeliveryModel } from '../src/modules/rental/overdueDelivery.model.js';

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
    OverdueDeliveryModel.deleteMany({}),
    UserModel.deleteMany({}),
  ]);
  await UserModel.collection.insertMany(['renter', 'owner'].map(role => ({ authId: `u-${role}`, email: `${role}@example.test`,
    displayName: `Demo ${role}`, roles: [role], accountStatus: 'active', settings: { emailNotifications: true } })));
});

test('physical return deadlines use the entire inclusive Malaysia calendar day', () => {
  for (const [day, deadline] of [
    ['2026-11-02', '2026-11-02T16:00:00.000Z'],
    ['2026-12-31', '2026-12-31T16:00:00.000Z'],
    ['2028-02-29', '2028-02-29T16:00:00.000Z'],
  ]) {
    assert.equal(physicalRentalReturnDeadline(day).toISOString(), deadline);
  }
});

async function activeCalendarRental(endDate = '2026-11-02T00:00:00Z', listingType = 'physical') {
  await BookingModel.create(booking({ suffix: 'CALENDAR1', title: 'Demo item', startDate: new Date('2026-11-02T00:00:00Z'),
    endDate: new Date(endDate), status: 'active', paymentStatus: 'captured' }));
  return RentalModel.create({
    publicId: 'RH-RNT-2026-CALENDAR1',
    bookingId: 'RH-BKG-2026-CALENDAR1',
    listingId: 'calendar-demo',
    listingType,
    renterId: 'u-renter',
    ownerId: 'u-owner',
    startDate: new Date('2026-11-02T00:00:00Z'),
    endDate: new Date(endDate),
    status: 'active',
  });
}

test('same-day physical rental stays active through Malaysia 23:59:59 and is overdue after midnight', async () => {
  const rental = await activeCalendarRental();
  const before = await runLifecycleJobs({ now: new Date('2026-11-02T15:59:59Z'), graceHours: 0, reminderHours: 1 });
  assert.equal(before.overdueRentals, 0);
  assert.equal(before.dueReminders, 2);
  assert.equal((await RentalModel.findById(rental._id)).status, 'active');
  const after = await runLifecycleJobs({ now: new Date('2026-11-02T16:00:00Z'), graceHours: 0 });
  assert.equal(after.overdueRentals, 1);
  assert.equal((await RentalModel.findById(rental._id)).status, 'overdue');
  const replay = await runLifecycleJobs({ now: new Date('2026-11-02T16:01:00Z'), graceHours: 0 });
  assert.equal(replay.overdueRentals, 0);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_overdue' }), 2);
});

test('overdue grace starts at the end of the rental day, not stored UTC midnight', async () => {
  const rental = await activeCalendarRental();
  const before = await runLifecycleJobs({ now: new Date('2026-11-02T17:59:59Z'), graceHours: 2 });
  assert.equal(before.overdueRentals, 0);
  assert.equal((await RentalModel.findById(rental._id)).status, 'active');
  const after = await runLifecycleJobs({ now: new Date('2026-11-02T18:00:00Z'), graceHours: 2 });
  assert.equal(after.overdueRentals, 1);
});

test('return reminders respect their actual deadline window and legacy stored day', async () => {
  const rental = await activeCalendarRental('2026-11-02T12:00:00Z');
  const early = await runLifecycleJobs({ now: new Date('2026-11-02T08:00:00Z'), graceHours: 0, reminderHours: 1 });
  assert.equal(early.overdueRentals, 0);
  assert.equal(early.dueReminders, 0);
  const due = await runLifecycleJobs({ now: new Date('2026-11-02T15:30:00Z'), graceHours: 0, reminderHours: 1 });
  assert.equal(due.dueReminders, 2);
  assert.equal((await RentalModel.findById(rental._id)).status, 'active');
});

test('service deadlines remain timestamps and never become physical overdue rentals', async () => {
  const rental = await activeCalendarRental('2026-11-02T01:00:00Z', 'service');
  const result = await runLifecycleJobs({ now: new Date('2026-11-02T08:00:00Z'), graceHours: 0 });
  assert.equal(result.overdueRentals, 0);
  assert.equal(result.dueReminders, 0);
  assert.equal(result.serviceReminders, 1);
  assert.equal((await RentalModel.findById(rental._id)).status, 'active');
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

test('expires an authorized request when the Owner does not respond and releases its hold', async () => {
  const now = new Date('2026-10-15T12:00:00Z');
  await BookingModel.create(booking({ suffix: 'PAIDWAIT', title: 'Paid request waiting for Owner',
    startDate: new Date('2026-10-22T00:00:00Z'), endDate: new Date('2026-10-24T00:00:00Z'),
    status: 'pending', paymentStatus: 'authorized', expiresAt: new Date('2026-10-14T00:00:00Z') }));
  await PaymentModel.create({
    publicId: 'RH-TXN-PAIDWAIT', bookingId: 'RH-BKG-2026-PAIDWAIT',
    payerId: 'u-renter', payeeId: 'u-owner', type: 'authorization', amount: 150,
    method: 'card', status: 'authorized', gatewayReference: 'demo-paidwait',
    idempotencyKey: 'paidwait-authorization', authorizationSlot: 'RH-BKG-2026-PAIDWAIT',
  });
  const result = await runLifecycleJobs({ now });
  assert.equal(result.expiredBookings, 1);
  const saved = await BookingModel.findOne({ publicId: 'RH-BKG-2026-PAIDWAIT' });
  assert.equal(saved.status, 'expired');
  assert.equal(saved.paymentStatus, 'voided');
  assert.equal((await PaymentModel.findOne({ publicId: 'RH-TXN-PAIDWAIT' })).status, 'voided');
  assert.equal(await NotificationModel.countDocuments({ type: 'booking_expired' }), 2);
});
