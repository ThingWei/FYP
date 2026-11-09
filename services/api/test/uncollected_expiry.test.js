import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { LifecycleOperationModel } from '../src/operations/lifecycleJournal.js';
import { expireUncollectedRentals } from '../src/modules/rental/uncollectedExpiry.js';
import { rentalService } from '../src/modules/rental/rental.service.js';
import { disputeService } from '../src/modules/dispute/dispute.service.js';
let mongo, sequence = 0;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all([BookingModel, RentalModel, PaymentModel, NotificationModel, UserModel, LifecycleOperationModel].map(model => model.deleteMany({})));
});
async function fixture({ status = 'scheduled', type = 'physical', captured = false, endDate = '2026-11-10', handover } = {}) {
  const id = `X${++sequence}`;
  const booking = await BookingModel.create({ publicId: `RH-BKG-2026-${id}`, listingId: `listing-${id}`,
    listingTitle: 'Demo camera', listingType: type, renterId: 'renter', renterName: 'Demo Renter', ownerId: 'owner',
    startDate: new Date(new Date(endDate).getTime() - 86400000), endDate: new Date(endDate),
    ...(type === 'physical' ? { fulfilmentMethod: 'pickup' } : { serviceVenue: 'Online' }),
    status: 'approved', paymentStatus: captured ? 'captured' : 'authorized',
    pricing: { baseAmount: 100, securityDeposit: 50, total: 150 } });
  const rental = await RentalModel.create({ publicId: `RH-RNT-2026-${id}`, bookingId: booking.publicId,
    listingId: booking.listingId, listingType: type, category: 'Devices', renterId: 'renter', ownerId: 'owner',
    startDate: booking.startDate, endDate: booking.endDate, status, handover });
  await PaymentModel.create({ publicId: `RH-TXN-2026-${id}`, bookingId: booking.publicId, payerId: 'renter', payeeId: 'owner',
    type: captured ? 'capture' : 'authorization', status: captured ? 'succeeded' : 'authorized', amount: 150, method: 'card', simulated: true,
    idempotencyKey: `test-payment:${id}`, gatewayReference: `test:${id}` });
  return { booking, rental };
}
test('uncollected expiry waits through the inclusive Malaysia end day and releases the full hold once', async () => {
  const { booking, rental } = await fixture();
  assert.deepEqual(await expireUncollectedRentals({ now: new Date('2026-11-10T15:59:59.999Z') }), { expired: 0, needsReview: 0 });
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
  assert.deepEqual(await expireUncollectedRentals({ now: new Date('2026-11-10T16:00:00Z') }), { expired: 1, needsReview: 0 });
  const saved = await RentalModel.findById(rental._id), savedBooking = await BookingModel.findById(booking._id);
  assert.equal(saved.status, 'expired'); assert.equal(saved.expiryReason, 'not_collected');
  assert.equal(savedBooking.status, 'expired'); assert.equal(savedBooking.paymentStatus, 'voided');
  assert.equal((await PaymentModel.findOne({ bookingId: booking.publicId })).status, 'voided');
  assert.equal(await PaymentModel.countDocuments({ type: { $in: ['capture', 'refund', 'owner_settlement'] } }), 0);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_not_collected' }), 2);
  assert.equal((await expireUncollectedRentals({ now: new Date('2026-11-11') })).expired, 0);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_not_collected' }), 2);
  assert.equal(saved.endDate.toISOString().slice(0, 10), '2026-11-10');
});
test('elapsed start date alone does not expire an ongoing booked period', async () => {
  await fixture();
  assert.equal((await expireUncollectedRentals({ now: new Date('2026-11-09T20:00:00Z') })).expired, 0);
});
test('active, disputed, returned, service and recorded-handover rentals are never no-show expiries', async () => {
  for (const status of ['active', 'overdue', 'return_submitted', 'disputed', 'completed']) await fixture({ status });
  await fixture({ type: 'service' });
  await fixture({ handover: { condition: 'Good', recordedAt: new Date('2026-11-09') } });
  assert.equal((await expireUncollectedRentals({ now: new Date('2026-11-11') })).expired, 0);
  assert.equal(await PaymentModel.countDocuments({ status: 'voided' }), 0);
});
test('unexpected captured payment requires review without automatic refund or blame', async () => {
  const { booking, rental } = await fixture({ captured: true });
  assert.deepEqual(await expireUncollectedRentals({ now: new Date('2026-11-11') }), { expired: 0, needsReview: 1 });
  await expireUncollectedRentals({ now: new Date('2026-11-11') });
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
  assert.equal((await BookingModel.findById(booking._id)).paymentStatus, 'captured');
  assert.equal(await NotificationModel.countDocuments({ type: 'uncollected_review_needed' }), 1);
  assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 0);
});
test('concurrent expiry jobs preserve a single transition and two participant notifications', async () => {
  await fixture();
  const results = await Promise.all([1, 2].map(() => expireUncollectedRentals({ now: new Date('2026-11-11') })));
  assert.equal(results.reduce((sum, result) => sum + result.expired, 0), 1);
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_not_collected' }), 2);
});

test('a stale unpaid flag cannot void a hold belonging to a different payer or amount', async () => {
  const { booking, rental } = await fixture();
  booking.paymentStatus = 'unpaid'; await booking.save();
  await PaymentModel.updateOne({ bookingId: booking.publicId }, { $set: { payerId: 'different-payer', amount: 999 } });
  assert.equal((await expireUncollectedRentals({ now: new Date('2026-11-11') })).needsReview, 1);
  assert.equal((await PaymentModel.findOne({ bookingId: booking.publicId })).status, 'authorized');
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
});
test('direct late handover is rejected without starting a rental or capturing a payment', async () => {
  const { rental } = await fixture({ endDate: '2020-01-01' });
  await UserModel.create({ authId: 'owner', displayName: 'Owner', email: 'owner@example.test', roles: ['renter', 'owner'], activeRole: 'owner', accountStatus: 'active' });
  await assert.rejects(rentalService.confirmHandover(rental.publicId, { condition: 'Good', evidence: ['upload://unused'] },
    { authId: 'owner', roles: ['owner'] }), error => error.code === 'HANDOVER_WINDOW_CLOSED');
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
  assert.equal(await PaymentModel.countDocuments({ type: 'capture' }), 0);
});

test('expired rentals cannot be reopened by a stale dispute submission', async () => {
  const { rental } = await fixture();
  await expireUncollectedRentals({ now: new Date('2026-11-11') });
  await UserModel.create({ authId: 'owner', displayName: 'Owner', email: 'owner@example.test', roles: ['renter', 'owner'], activeRole: 'owner' });
  await assert.rejects(disputeService.create({ rentalId: rental.publicId, evidence: [] }, { authId: 'owner', roles: ['owner'] }), error => error.code === 'INVALID_RENTAL_STATE');
  assert.equal((await RentalModel.findById(rental._id)).status, 'expired');
});

test('interrupted expiry recovers the recorded release and lifecycle without duplicate effects', async t => {
  const { rental, booking } = await fixture();
  const original = RentalModel.updateOne;
  t.mock.method(RentalModel, 'updateOne', function (...args) {
    throw new Error('Controlled interrupted rental update');
  });
  await assert.rejects(expireUncollectedRentals({ now: new Date('2026-11-11') }), /Controlled interrupted/);
  t.mock.restoreAll();
  assert.equal((await PaymentModel.findOne({ bookingId: booking.publicId })).status, 'voided');
  assert.equal((await RentalModel.findById(rental._id)).status, 'scheduled');
  await expireUncollectedRentals({ now: new Date('2026-11-11') });
  assert.equal((await RentalModel.findById(rental._id)).status, 'expired');
  assert.equal((await BookingModel.findById(booking._id)).status, 'expired');
  assert.equal(await NotificationModel.countDocuments({ type: 'rental_not_collected' }), 2);
  assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 0);
  assert.equal(RentalModel.updateOne, original);
});
