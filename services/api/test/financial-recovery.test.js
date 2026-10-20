import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { ClaimModel } from '../src/modules/dispute/claim.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { bookingBalance, ledgerEntry } from '../src/modules/payment/paymentLedger.js';
import { LifecycleOperationModel, recoverLifecycleOperations, commitLifecycle } from '../src/operations/lifecycleJournal.js';
import { withOperationLock } from '../src/modules/booking/bookingRequestLock.js';
import { expireRentalExtensions } from '../src/modules/rental/rental.service.js';
import { voidTerminalPaymentHolds } from '../src/modules/payment/payment.service.js';

let mongodb;
const headers = (id, role) => ({ 'x-user-id': id, 'x-user-roles': role, 'x-user-name': id, 'x-user-email': `${id}@test.my` });
const renter = headers('renter', 'renter'), owner = headers('owner', 'owner'), admin = headers('admin', 'admin');
const bookingId = 'RH-BKG-2027-FINANCE';
const rentalId = 'RH-RNT-2027-FINANCE';
const path = `/api/v1/rentals/${rentalId}`;
before(async () => { mongodb = await MongoMemoryServer.create(); await connectDatabase(mongodb.getUri()); });
after(async () => { await disconnectDatabase(); await mongodb.stop(); });
beforeEach(async () => {
  for (const collection of Object.values(mongoose.connection.collections)) await collection.deleteMany({});
  await Promise.all([BookingModel.init(), RentalModel.init(), PaymentModel.init(), DisputeModel.init(), ClaimModel.init()]);
  for (const identity of [renter, owner, admin, headers('outsider', 'renter')]) {
    await request(app).post('/api/v1/users/session').set(identity).expect(201);
  }
  await BookingModel.create({ publicId: bookingId, listingId: 'camera', listingTitle: 'Camera', listingType: 'physical', category: 'Devices',
    renterId: 'renter', renterName: 'Renter', ownerId: 'owner', startDate: new Date('2027-01-01'), endDate: new Date('2027-01-03'),
    fulfilmentMethod: 'pickup', damageWaiverSelected: true,
    pricing: { baseAmount: 300, securityDeposit: 100, damageWaiverFee: 10, deliveryFee: 20, platformFee: 0, total: 430,
      originalDailyRate: 100, originalRentalDays: 3 }, status: 'active', paymentStatus: 'captured' });
  await RentalModel.create({ publicId: rentalId, bookingId, listingId: 'camera', listingType: 'physical', category: 'Devices',
    renterId: 'renter', ownerId: 'owner', startDate: new Date('2027-01-01'), endDate: new Date('2027-01-03'), status: 'active' });
  const booking = await BookingModel.findOne({ publicId: bookingId });
  await ledgerEntry(booking, 'capture', 430, 'initial-capture').save();
});

async function quote(end = '2027-01-05') {
  const result = await request(app).post(`${path}/extensions`).set(renter).send({ requestedEndDate: end, reason: 'More time for the project' }).expect(200);
  return result.body.data.extension;
}
function pay(extensionId, key = 'extension-attempt-001', outcome = 'success', method = 'card') {
  return request(app).post(`${path}/extensions/payment`).set(renter).send({ extensionId, method, simulationOutcome: outcome, idempotencyKey: key });
}
function decide(extensionId, status = 'approved') {
  return request(app).patch(`${path}/extensions/decision`).set(owner).send({ extensionId, status, ...(status === 'rejected' && { reason: 'No additional days available' }) });
}
async function openDispute() {
  const opened = await request(app).post('/api/v1/disputes').set(renter).send({ rentalId, category: 'other', summary: 'Please review this rental',
    description: 'The participants need an administrator to review the outstanding rental balance.', evidence: [] }).expect(201);
  return opened.body.data.publicId;
}
function resolve(id, data = {}) {
  return request(app).patch(`/api/v1/disputes/${id}/resolve`).set(admin).send({ outcome: 'release_to_renter', notes: 'Reviewed the available evidence and remaining held funds.', ...data });
}

test('extra days use the booked rate, require payment and never rewrite original charges', async () => {
  const extension = await quote();
  assert.equal(extension.extraDays, 2); assert.equal(extension.amount, 200); assert.equal(extension.dailyRate, 100);
  await decide(extension.id).expect(409);
  for (const method of ['card', 'fpx', 'wallet']) await pay(extension.id, `decline-${method}`, 'declined', method).expect(200);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).extension.paymentStatus, 'unpaid');
  await pay(extension.id).expect(200); await pay(extension.id).expect(200);
  await pay(extension.id, 'extension-attempt-001', 'declined').expect(409);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).endDate.toISOString().slice(0, 10), '2027-01-03');
  const decisions = await Promise.all([decide(extension.id), decide(extension.id)]);
  assert.deepEqual(decisions.map((entry) => entry.status).sort(), [200, 409]);
  assert.equal(await PaymentModel.countDocuments({ type: 'capture', 'metadata.extensionId': extension.id }), 1);
  const saved = await BookingModel.findOne({ publicId: bookingId });
  assert.equal(saved.pricing.total, 430); assert.equal(saved.pricing.baseAmount, 300);
  assert.equal(saved.endDate.toISOString().slice(0, 10), '2027-01-05');
  assert.equal((await bookingBalance(bookingId)).captured, 630);
});

test('extension authorization rejects bypasses, stale quotes and foreign accounts', async () => {
  const extension = await quote();
  const previous = env.authMode; env.authMode = 'local';
  try { await request(app).post(`${path}/extensions/payment`).send({}).expect(401); }
  finally { env.authMode = previous; }
  await request(app).post(`${path}/extensions/payment`).set(headers('outsider', 'renter')).send({ extensionId: extension.id, method: 'card', simulationOutcome: 'success', idempotencyKey: 'foreign-attempt' }).expect(404);
  await request(app).post(`${path}/extensions/payment`).set(renter).send({ extensionId: extension.id, method: 'cash', simulationOutcome: 'success', idempotencyKey: 'invalid-attempt' }).expect(422);
  await pay('EXT-00000000-0000-0000-0000-000000000000').expect(409);
  await decide('EXT-00000000-0000-0000-0000-000000000000').expect(409);
  await pay(extension.id).expect(200);
  await decide(extension.id, 'rejected').expect(200);
  assert.equal((await PaymentModel.findOne({ 'metadata.extensionId': extension.id })).status, 'voided');
  assert.equal((await bookingBalance(bookingId)).captured, 430);
});

test('expired extensions void authorizations and preserve history when re-quoted', async () => {
  const first = await quote(); await pay(first.id).expect(200);
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { 'extension.expiresAt': new Date(0) } });
  assert.equal(await expireRentalExtensions(), 1);
  assert.equal(await expireRentalExtensions(), 0);
  const second = await quote('2027-01-06');
  assert.notEqual(second.id, first.id);
  const rental = await RentalModel.findOne({ publicId: rentalId });
  assert.equal(rental.extensionHistory.length, 1);
  assert.equal(rental.extensionHistory[0].paymentStatus, 'voided');
  await pay(first.id).expect(409);
  await pay(second.id, 'new-quote-payment').expect(200);
  await decide(second.id).expect(200);
});

test('a new confirmed conflict blocks extension approval even after demo authorization', async () => {
  const extension = await quote(); await pay(extension.id).expect(200);
  const original = await BookingModel.findOne({ publicId: bookingId }).lean();
  delete original._id; delete original.__v;
  await BookingModel.create({ ...original, publicId: 'RH-BKG-2027-CONFLICT', renterId: 'other-renter', startDate: new Date('2027-01-04'), endDate: new Date('2027-01-05'), status: 'approved' });
  await decide(extension.id).expect(409);
  assert.equal(await PaymentModel.countDocuments({ type: 'capture', 'metadata.extensionId': extension.id }), 0);
  await decide(extension.id, 'rejected').expect(200);
});

test('return closes unpaid/authorized extensions without charging for extra days', async () => {
  const extension = await quote(); await pay(extension.id).expect(200);
  await request(app).post(`${path}/return`).set(renter).send({ condition: 'Good', evidence: ['local://return/item.jpg'] }).expect(200);
  await decide(extension.id).expect(409);
  const rental = await RentalModel.findOne({ publicId: rentalId });
  assert.equal(rental.extension.paymentStatus, 'voided');
  assert.equal(await PaymentModel.countDocuments({ type: 'capture' }), 1);
});

test('legacy missing original rates are not guessed from dates that may have been extended', async () => {
  await BookingModel.updateOne({ publicId: bookingId }, { $unset: { 'pricing.originalDailyRate': 1, 'pricing.originalRentalDays': 1 } });
  const result = await request(app).post(`${path}/extensions`).set(renter).send({ requestedEndDate: '2027-01-05', reason: 'Need additional days' }).expect(409);
  assert.equal(result.body.error.code, 'EXTENSION_RATE_UNAVAILABLE');
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).extension.status, 'none');
});

test('opening a dispute voids an outstanding extension hold, not the captured rental funds', async () => {
  const extension = await quote(); await pay(extension.id).expect(200);
  await openDispute();
  assert.equal((await PaymentModel.findOne({ 'metadata.extensionId': extension.id })).status, 'voided');
  assert.equal((await bookingBalance(bookingId)).held, 430);
  await decide(extension.id).expect(409);
});

test('normal settlement conserves funds and refunds cannot repay released money', async () => {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  await request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 25 }).expect(200);
  assert.deepEqual(await bookingBalance(bookingId), { captured: 430, distributed: 430, held: 0, reconciliationRequired: false });
  assert.equal((await PaymentModel.findOne({ type: 'deposit_release' })).amount, 75);
  assert.equal((await PaymentModel.findOne({ type: 'owner_settlement' })).amount, 355);
  const capture = await PaymentModel.findOne({ type: 'capture' });
  await request(app).post(`/api/v1/payments/${capture.publicId}/refunds`).set(admin).send({ amount: 1, reason: 'Refund again', idempotencyKey: 'double-payout-refund' }).expect(400);
});

test('partial refund blocks automatic full settlement; dispute allocates only remaining money', async () => {
  const capture = await PaymentModel.findOne({ type: 'capture' });
  await request(app).post(`/api/v1/payments/${capture.publicId}/refunds`).set(admin).send({ amount: 100, reason: 'Agreed partial refund', idempotencyKey: 'partial-refund-001' }).expect(201);
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  await request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 0 }).expect(409);
  assert.equal(await PaymentModel.countDocuments({ type: 'owner_settlement' }), 0);
  const dispute = await openDispute();
  await resolve(dispute, { outcome: 'split', renterAmount: 200, ownerAmount: 230 }).expect(400);
  await resolve(dispute, { outcome: 'split', renterAmount: 100, ownerAmount: 200 }).expect(400);
  await resolve(dispute, { outcome: 'split', renterAmount: 100, ownerAmount: 230 }).expect(200);
  await resolve(dispute, { outcome: 'split', renterAmount: 100, ownerAmount: 230 }).expect(200);
  assert.equal((await bookingBalance(bookingId)).held, 0);
  assert.equal(await PaymentModel.countDocuments({ type: 'owner_settlement' }), 1);
  assert.equal((await PaymentModel.findOne({ type: 'owner_settlement' })).amount, 230);
});

test('dispute after completed settlement records a zero remaining allocation without clawback', async () => {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  await request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 0 }).expect(200);
  const before = await PaymentModel.countDocuments();
  const dispute = await openDispute();
  const result = await resolve(dispute).expect(200);
  assert.equal(result.body.data.resolution.renterAmount, 0);
  assert.equal(await PaymentModel.countDocuments(), before);
});

test('approval of a claim records pending funding and never invents a payout', async () => {
  const dispute = await openDispute();
  const claim = await request(app).post(`/api/v1/disputes/${dispute}/claims`).set(owner).send({ description: 'Repair costs supported by the item condition evidence.', amountRequested: 50, evidence: ['local://claim/item.jpg'] }).expect(201);
  const before = await PaymentModel.countDocuments();
  const result = await request(app).patch(`/api/v1/disputes/claims/${claim.body.data.publicId}/decision`).set(admin).send({ status: 'approved', approvedAmount: 40, reason: 'Reviewed and accepted for a future funded demo payout.' }).expect(200);
  assert.equal(result.body.data.decision.payoutStatus, 'pending_funding');
  assert.equal(await PaymentModel.countDocuments(), before);
});

test('crash after settlement ledger writes recovers both states once, including original deductions', async () => {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  const originalUpdate = RentalModel.updateOne;
  RentalModel.updateOne = function () { throw new Error('Injected interruption after ledger writes'); };
  try { await request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 20 }).expect(500); }
  finally { RentalModel.updateOne = originalUpdate; }
  assert.equal(await LifecycleOperationModel.countDocuments({ status: 'pending' }), 1);
  assert.equal((await bookingBalance(bookingId)).held, 0);
  await recoverLifecycleOperations(); await recoverLifecycleOperations();
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).returnOutcome.depositDeduction, 20);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'completed');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'completed');
  assert.equal(await PaymentModel.countDocuments({ type: 'owner_settlement' }), 1);
  assert.equal(await LifecycleOperationModel.countDocuments({ status: 'pending' }), 0);
});

test('journal revision fence stops old replay from overwriting a later transition', async () => {
  const rental = await RentalModel.findOne({ publicId: rentalId });
  rental.status = 'return_submitted';
  await withOperationLock('listing-decision', rental.listingId, (ensure) => commitLifecycle('first-transition', rental.listingId, [rental], ensure));
  const next = await RentalModel.findById(rental._id); next.status = 'disputed';
  await withOperationLock('listing-decision', rental.listingId, (ensure) => commitLifecycle('second-transition', rental.listingId, [next], ensure));
  await LifecycleOperationModel.updateOne({ _id: 'first-transition' }, { $set: { status: 'pending' } });
  await recoverLifecycleOperations();
  assert.equal((await RentalModel.findById(rental._id)).status, 'disputed');
});

test('interrupted extension payment resumes its durable authorization without a second attempt', async () => {
  const extension = await quote();
  const update = RentalModel.updateOne;
  RentalModel.updateOne = () => { throw new Error('Injected interruption after extension authorization'); };
  try { await pay(extension.id).expect(500); } finally { RentalModel.updateOne = update; }
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).extension.paymentStatus, 'unpaid');
  await pay(extension.id).expect(200);
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).extension.paymentStatus, 'authorized');
  assert.equal(await PaymentModel.countDocuments({ type: 'authorization', 'metadata.extensionId': extension.id }), 1);
});

test('interrupted Owner extension approval recovers one capture and both date records', async () => {
  const extension = await quote(); await pay(extension.id).expect(200);
  const update = BookingModel.updateOne;
  BookingModel.updateOne = () => { throw new Error('Injected interruption before booking date update'); };
  try { await decide(extension.id).expect(500); } finally { BookingModel.updateOne = update; }
  await recoverLifecycleOperations();
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).endDate.toISOString().slice(0, 10), '2027-01-05');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).endDate.toISOString().slice(0, 10), '2027-01-05');
  assert.equal(await PaymentModel.countDocuments({ type: 'capture', 'metadata.extensionId': extension.id }), 1);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).extensionCharges.length, 1);
});

test('interrupted initial approval recovers the scheduled rental and booking without duplicate rentals', async () => {
  await RentalModel.deleteMany({}); await PaymentModel.deleteMany({});
  const booking = await BookingModel.findOne({ publicId: bookingId });
  booking.status = 'pending'; booking.paymentStatus = 'authorized'; booking.listingId = 'l-camera'; await booking.save();
  await ledgerEntry(booking, 'authorization', 430, 'initial-authorization', { status: 'authorized' }).save();
  await ListingModel.create({ publicId: 'l-camera', ownerId: 'owner', ownerName: 'Owner', title: 'Camera', category: 'Devices',
    listingType: 'physical', dailyPrice: 999, condition: 'Good', securityDeposit: 100, location: 'Kuala Lumpur', fulfilmentMethods: ['pickup'], status: 'active' });
  const update = BookingModel.updateOne;
  BookingModel.updateOne = () => { throw new Error('Injected interruption after scheduled rental creation'); };
  try { await request(app).patch(`/api/v1/bookings/${bookingId}/decision`).set(owner).send({ status: 'approved' }).expect(500); }
  finally { BookingModel.updateOne = update; }
  assert.equal(await RentalModel.countDocuments(), 1);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'pending');
  await recoverLifecycleOperations(); await recoverLifecycleOperations();
  assert.equal(await RentalModel.countDocuments(), 1);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'approved');
});

test('interrupted dispute settlement recovers allocations and statuses without reallocating a consumed balance', async () => {
  const dispute = await openDispute();
  const update = DisputeModel.updateOne;
  DisputeModel.updateOne = () => { throw new Error('Injected interruption before dispute closure'); };
  try { await resolve(dispute, { outcome: 'split', renterAmount: 100, ownerAmount: 330 }).expect(500); }
  finally { DisputeModel.updateOne = update; }
  await resolve(dispute, { outcome: 'split', renterAmount: 100, ownerAmount: 330 }).expect(200);
  assert.equal((await bookingBalance(bookingId)).held, 0);
  assert.equal(await PaymentModel.countDocuments({ type: 'owner_settlement' }), 1);
  assert.equal((await DisputeModel.findOne({ publicId: dispute })).status, 'resolved');
});

test('remaining balance is participant-only and never returns private identity or locations', async () => {
  await request(app).get(`/api/v1/payments/booking/${bookingId}/balance`).set(headers('outsider', 'renter')).expect(404);
  const result = await request(app).get(`/api/v1/payments/booking/${bookingId}/balance`).set(renter).expect(200);
  assert.deepEqual(result.body.data, { captured: 430, distributed: 0, held: 430, reconciliationRequired: false });
});

test('interrupted refund reconciles through an explicit balance read without another payout', async () => {
  const capture = await PaymentModel.findOne({ type: 'capture' });
  const input = { amount: 80, reason: 'Reviewed partial refund', idempotencyKey: 'interrupted-refund' };
  const endpoint = `/api/v1/payments/${capture.publicId}/refunds`;
  const update = BookingModel.updateOne;
  BookingModel.updateOne = () => { throw new Error('Injected interruption after refund ledger record'); };
  try { await request(app).post(endpoint).set(admin).send(input).expect(500); }
  finally { BookingModel.updateOne = update; }
  const balance = await request(app).get(`/api/v1/payments/booking/${bookingId}/balance`).set(admin).expect(200);
  assert.equal(balance.body.data.held, 350);
  await request(app).post(endpoint).set(admin).send(input).expect(201);
  assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 1);
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).paymentStatus, 'partially_refunded');
  assert.equal(await NotificationModel.countDocuments({ type: 'payment_refunded' }), 1);
});

test('completion notification failure retains a retryable outbox without failing the settlement', async () => {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  const create = NotificationModel.create;
  NotificationModel.create = () => { throw new Error('Injected notification interruption'); };
  try { await request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 0 }).expect(200); }
  finally { NotificationModel.create = create; }
  assert.equal(await LifecycleOperationModel.countDocuments({ status: 'done', effectsPending: true }), 1);
  await request(app).get(path).set(renter).expect(200);
  await request(app).get(path).set(renter).expect(200);
  assert.equal(await LifecycleOperationModel.countDocuments({ effectsPending: true }), 0);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_completed' }), 1);
  assert.equal(await PaymentModel.countDocuments({ type: 'owner_settlement' }), 1);
});

test('terminal orphan authorization is released once without touching captured funds', async () => {
  const booking = await BookingModel.findOne({ publicId: bookingId });
  await PaymentModel.deleteMany({});
  booking.status = 'cancelled'; booking.paymentStatus = 'unpaid'; await booking.save();
  await ledgerEntry(booking, 'authorization', 430, 'orphan-hold', { status: 'authorized' }).save();
  assert.equal(await voidTerminalPaymentHolds(), 1);
  assert.equal(await voidTerminalPaymentHolds(), 0);
  assert.equal((await PaymentModel.findOne({ type: 'authorization' })).status, 'voided');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).paymentStatus, 'voided');
});

test('dispute and return decision serialize without duplicate payouts or lost dispute status', async () => {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'return_submitted' } });
  const [opened, returned] = await Promise.all([
    request(app).post('/api/v1/disputes').set(renter).send({ rentalId, category: 'other', summary: 'Please review the condition', description: 'The condition needs review before any final distribution of funds.' }),
    request(app).post(`${path}/return/confirm`).set(owner).send({ condition: 'Good', depositDeduction: 0 }),
  ]);
  assert.equal(opened.status, 201);
  assert.ok([200, 409].includes(returned.status));
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'disputed');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'disputed');
  assert.ok((await bookingBalance(bookingId)).distributed <= 430);
});
