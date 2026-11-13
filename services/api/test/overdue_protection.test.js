import test, { before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { OverdueDeliveryModel as Delivery } from '../src/modules/rental/overdueDelivery.model.js';
import { overdueSummary } from '../src/modules/rental/overduePolicy.js';
import { assertNoOverdueReturn } from '../src/modules/rental/overdueEligibility.js';
import { runOverdueReminders, deliveryFailure } from '../src/modules/rental/overdueReminders.js';
import { createAdminRecordsService } from '../src/modules/admin/adminRecords.service.js';
import { adminModule } from '../src/modules/admin/index.js';
import { withOperationLock } from '../src/modules/booking/bookingRequestLock.js';

let mongo;
const originalMode = env.emailMode;
const instant = new Date('2026-11-01T16:00:00Z');
const afterDay = new Date('2026-11-02T16:00:00Z');
const sent = [];
const sendEmail = async input => { sent.push(input); return { accepted: [input.email] }; };
const run = overrides => runOverdueReminders({ now: instant, sendEmail, ...overrides });
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  await Promise.all([RentalModel, BookingModel, UserModel, PaymentModel, NotificationModel, Delivery].map(m => m.init()));
});
beforeEach(async () => {
  sent.length = 0; env.emailMode = 'smtp';
  await Promise.all([RentalModel, BookingModel, UserModel, PaymentModel, NotificationModel, Delivery].map(m => m.deleteMany({})));
  await UserModel.collection.insertMany(['renter', 'owner', 'admin'].map(role => ({ authId: role,
    email: `${role}@example.test`, displayName: `Demo ${role}`, roles: [role], accountStatus: 'active', settings: { emailNotifications: true } })));
});
afterEach(() => { env.emailMode = originalMode; });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
async function fixture(overrides = {}) {
  await BookingModel.collection.insertOne({ publicId: 'RH-BKG-2026-LATE', listingTitle: 'Demo camera', renterId: 'renter', ownerId: 'owner',
    listingId: 'late-item', listingType: 'physical', status: 'active', paymentStatus: 'captured',
    pricing: { total: 150, securityDeposit: 50, currency: 'MYR' } });
  return RentalModel.create({ publicId: 'RH-RNT-2026-LATE', bookingId: 'RH-BKG-2026-LATE', listingId: 'late-item',
    listingType: 'physical', renterId: 'renter', ownerId: 'owner', startDate: new Date('2026-11-01'), endDate: new Date('2026-11-01'), status: 'overdue', ...overrides });
}

test('Malaysia inclusive deadlines, grace, 24h boundary, services and completed records', () => {
  for (const [endDate, at] of [['2026-11-01', '2026-11-01T16:00:00Z'], ['2028-02-29', '2028-02-29T16:00:00Z'], ['2026-12-31', '2026-12-31T16:00:00Z']]) {
    const r = { listingType: 'physical', status: 'active', endDate: new Date(endDate) };
    const now = new Date(at);
    assert.equal(overdueSummary(r, new Date(now - 1), 0).isOverdue, false);
    assert.equal(overdueSummary(r, now, 0).isOverdue, true);
    assert.equal(overdueSummary(r, now, 2).isOverdue, false);
    assert.equal(overdueSummary(r, new Date(+now + 7200000), 2).isOverdue, true);
    assert.equal(overdueSummary(r, new Date(+now + 86400000 - 1)).needsAttention, false);
    assert.equal(overdueSummary(r, new Date(+now + 86400000)).needsAttention, true);
    for (const change of [{ status: 'completed' }, { listingType: 'service' }, { status: 'scheduled' }, { returnSubmission: { recordedAt: now } }]) {
      assert.equal(overdueSummary({ ...r, ...change }, new Date(+now + 86400000)).isOverdue, false);
    }
  }
});

test('initial email and notification, 24h follow-up and one admin alert preserve all money/statuses', async () => {
  const r = await fixture();
  await run();
  assert.equal(sent.length, 2); assert.equal(await NotificationModel.countDocuments(), 2);
  assert.ok(sent.every(m => !m.followup && m.bookingReference === r.bookingId));
  assert.equal(await Delivery.countDocuments({ status: 'sent' }), 4);
  await run(); assert.equal(sent.length, 2);
  await run({ now: afterDay });
  assert.equal(sent.length, 4); assert.equal(await NotificationModel.countDocuments(), 5);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_overdue_attention' }), 1);
  await run({ now: new Date(+afterDay + 86400000) }); assert.equal(sent.length, 4);
  const stored = await RentalModel.findById(r._id);
  assert.equal(stored.status, 'overdue'); assert.ok(stored.automation.overdueEscalatedAt);
  assert.equal((await BookingModel.findOne()).paymentStatus, 'captured');
  assert.equal(await PaymentModel.countDocuments(), 0);
});

test('late startup sends only the latest stage for existing overdue records', async () => {
  await fixture(); await run({ now: afterDay });
  assert.equal(sent.length, 2); assert.ok(sent.every(m => m.followup));
  assert.equal(await Delivery.countDocuments({ stage: 'initial' }), 0);
});

test('missing uniqueness index fails before queuing or sending', async () => {
  await fixture(); await Delivery.collection.dropIndex('key_1');
  try {
    await assert.rejects(run(), /uniqueness index/);
    assert.equal(sent.length, 0); assert.equal(await Delivery.countDocuments(), 0);
  } finally { await Delivery.createIndexes(); }
});

test('concurrent laptop workers deduplicate email, notification and escalation', async () => {
  await fixture(); await Promise.all([run({ now: afterDay }), run({ now: afterDay })]);
  assert.equal(sent.length, 2); assert.equal(await NotificationModel.countDocuments(), 3);
  assert.equal(await Delivery.countDocuments(), 5);
});

for (const status of ['return_submitted', 'completed', 'cancelled', 'disputed']) {
  test(`queued reminders stop when lifecycle becomes ${status}`, async () => {
    const r = await fixture(); await run({ limit: 0 });
    await RentalModel.updateOne({ _id: r._id }, { $set: { status } });
    await run(); assert.equal(sent.length, 0);
    assert.equal(await Delivery.countDocuments({ status: 'cancelled' }), 4);
  });
}

test('return before queued delivery cancels it after re-reading under the lock', async () => {
  const r = await fixture(); await run({ limit: 0 });
  await withOperationLock('listing-decision', r.listingId, async () => {
    await RentalModel.updateOne({ _id: r._id }, { $set: { status: 'return_submitted', 'returnSubmission.recordedAt': instant } });
  });
  await run(); assert.equal(sent.length, 0);
});

test('email preference and disabled provider do not suppress in-app alerts', async () => {
  await fixture(); env.emailMode = 'disabled';
  await UserModel.updateOne({ authId: 'renter' }, { $set: { 'settings.emailNotifications': false } });
  await run();
  assert.equal(sent.length, 0); assert.equal(await NotificationModel.countDocuments(), 2);
  assert.equal(await Delivery.countDocuments({ result: 'opted_out' }), 1);
  assert.equal(await Delivery.countDocuments({ result: 'disabled' }), 1);
  env.emailMode = 'smtp'; await run({ now: new Date(+instant + 3600000) });
  assert.equal(sent.length, 1); assert.equal(sent[0].owner, true);
});

test('notification delivery failure does not prevent the separate email channel', async () => {
  await fixture(); await run({ notify: async () => { throw new Error('PRIVATE transport unavailable'); } });
  assert.equal(sent.length, 2);
  assert.equal(await Delivery.countDocuments({ channel: 'notification', status: 'retry' }), 2);
  await run({ now: new Date(+instant + 300000) });
  assert.equal(sent.length, 2); assert.equal(await NotificationModel.countDocuments(), 2);
});

test('known rejection retries with backoff; an uncertain SMTP timeout is not resent', async () => {
  await fixture();
  await run({ sendEmail: async input => {
    if (input.owner) throw new Error('PRIVATE provider detail');
    const error = new Error('PRIVATE temporary rejection'); error.deliveryOutcome = 'not_sent'; error.retryable = true; throw error;
  } });
  assert.equal(await Delivery.countDocuments({ status: 'retry', result: 'temporary_failure' }), 1);
  assert.equal(await Delivery.countDocuments({ status: 'uncertain' }), 1);
  await run(); assert.equal(sent.length, 0);
  await run({ now: new Date(+instant + 300000) }); assert.equal(sent.length, 1); assert.equal(sent[0].owner, false);
  assert.ok(!JSON.stringify(await Delivery.find().lean()).includes('PRIVATE'));
});

test('expired email lease is uncertain; notification lease can replay safely', async () => {
  await fixture(); await run({ limit: 0 });
  await Delivery.updateMany({}, { $set: { status: 'sending', leaseToken: 'dead-worker', leaseUntil: new Date(+instant - 1), attempts: 1 } });
  await run(); assert.equal(sent.length, 0);
  assert.equal(await Delivery.countDocuments({ status: 'uncertain' }), 2);
  assert.equal(await NotificationModel.countDocuments(), 2);
});

test('malformed provider acknowledgement cannot be reported as a sent email', async () => {
  await fixture(); await run({ sendEmail: async () => ({}) });
  assert.equal(await Delivery.countDocuments({ channel: 'email', status: 'uncertain' }), 2);
  await run(); assert.equal(sent.length, 0);
});

test('known failures stop after five attempts; permanent rejection is not retried', async () => {
  await fixture();
  let attempts = 0;
  const fail = async input => {
    attempts++;
    const error = new Error('not sent'); error.deliveryOutcome = 'not_sent'; error.retryable = !input.owner; throw error;
  };
  for (let i = 0; i < 7; i++) await run({ now: new Date(+instant + i * 3600000), sendEmail: fail });
  assert.equal(attempts, 6);
  assert.equal(await Delivery.countDocuments({ channel: 'email', status: 'failed' }), 2);
});

test('email delivery releases the lifecycle lock so returns can proceed while SMTP is slow', async () => {
  const r = await fixture();
  await run({ sendEmail: async () => {
    await withOperationLock('listing-decision', r.listingId, async () => {
      await RentalModel.updateOne({ _id: r._id }, { $set: { status: 'return_submitted', 'returnSubmission.recordedAt': instant } });
    });
    return { accepted: ['renter@example.test'] };
  } });
  assert.equal((await RentalModel.findById(r._id)).status, 'return_submitted');
  assert.equal(await Delivery.countDocuments({ channel: 'email', status: 'sent' }), 1);
  assert.equal(await Delivery.countDocuments({ status: 'cancelled' }), 2);
});

test('linked completion stops delivery and does not leave a stale rental blocking checkout', async () => {
  await fixture(); await run({ limit: 0 });
  await BookingModel.updateOne({}, { $set: { status: 'completed' } });
  await run(); assert.equal(sent.length, 0);
  await assertNoOverdueReturn('renter', instant);
});

test('follow-up supersedes unsent first reminders and extension invalidates old deadlines', async () => {
  const r = await fixture(); await run({ limit: 0 });
  await run({ now: afterDay }); assert.equal(sent.length, 2);
  assert.equal(await Delivery.countDocuments({ status: 'superseded' }), 4);
  await RentalModel.updateOne({ _id: r._id }, { $set: { status: 'active', endDate: new Date('2026-11-05') } });
  await assertNoOverdueReturn('renter', afterDay);
  assert.equal(overdueSummary(await RentalModel.findById(r._id), afterDay).needsAttention, false);
});

test('fresh eligibility blocks scheduler-lag and disputed rentals, not other accounts or returned/resolved ones', async () => {
  const r = await fixture({ status: 'active' });
  await assert.rejects(assertNoOverdueReturn('renter', instant), { code: 'OVERDUE_RETURN_REQUIRED', status: 409 });
  await assertNoOverdueReturn('owner', instant);
  await RentalModel.updateOne({ _id: r._id }, { $set: { status: 'disputed' } });
  await assert.rejects(assertNoOverdueReturn('renter', instant), { code: 'OVERDUE_RETURN_REQUIRED' });
  // Dismissal restores overdue state and is not final settlement.
  await RentalModel.updateOne({ _id: r._id }, { $set: { status: 'overdue' } });
  await assert.rejects(assertNoOverdueReturn('renter', instant), { code: 'OVERDUE_RETURN_REQUIRED' });
  await RentalModel.updateOne({ _id: r._id }, { $set: { 'returnSubmission.recordedAt': instant } });
  await assertNoOverdueReturn('renter', instant);
  await RentalModel.updateOne({ _id: r._id }, { $unset: { returnSubmission: 1 }, $set: { status: 'completed' } });
  await assertNoOverdueReturn('renter', instant);
});

test('admin receives readable delivery states without email addresses/provider errors or queue secrets', async () => {
  const r = await fixture(); await run({ now: afterDay });
  const service = createAdminRecordsService(adminModule.Model);
  const row = (await service.get('rentals', r.publicId)).record;
  assert.equal(row.overdueInfo.needsAttention, true);
  assert.equal(row.overdueReminders.length, 5);
  const safe = JSON.stringify(row.overdueReminders);
  assert.ok(!safe.includes('@')); assert.ok(!safe.includes('lease')); assert.ok(!safe.includes('userId'));
  const denied = await request(app).get(`/api/v1/admin/records/rentals/${r.publicId}`).set({ 'x-user-id': 'renter', 'x-user-roles': 'renter' });
  assert.equal(denied.status, 403);
});

test('SMTP classification distinguishes explicit rejection from ambiguous network failure', () => {
  assert.deepEqual(deliveryFailure({ responseCode: 451 }), { known: true, retryable: true });
  assert.deepEqual(deliveryFailure({ responseCode: 550 }), { known: true, retryable: false });
  assert.deepEqual(deliveryFailure({ code: 'ETIMEDOUT', command: 'DATA' }), { known: false, retryable: false });
  assert.deepEqual(deliveryFailure({ code: 'ECONNECTION', command: 'DATA' }), { known: false, retryable: false });
  assert.deepEqual(deliveryFailure({ code: 'ETIMEDOUT', command: 'CONN' }), { known: true, retryable: true });
});
