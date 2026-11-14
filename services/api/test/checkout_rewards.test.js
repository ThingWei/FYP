import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RewardLedgerModel, LoyaltyConfigModel } from '../src/modules/loyalty/loyalty.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { paymentService, captureBookingPayment, planPhysicalSettlement } from '../src/modules/payment/payment.service.js';
import { bookingBalance, planAllocations } from '../src/modules/payment/paymentLedger.js';
import { recordRewardFunding } from '../src/modules/loyalty/checkoutRewards.js';
let mongo;
const identity = { authId: 'rewards-renter', roles: ['renter'] };
const headers = { 'x-user-id': identity.authId, 'x-user-email': 'reward@example.invalid', 'x-user-name': 'Reward renter', 'x-user-roles': 'renter' };
const bookingId = 'RH-BKG-2026-REWARD';
const endpoint = id => `/api/v1/rewards/checkout/${id}`;
function book(id = bookingId, extra = {}) {
 return BookingModel.create({ publicId: id, listingId: `l-${id.toLowerCase()}`, listingTitle: 'Reward camera', listingType: 'physical', fulfilmentMethod: 'pickup', renterId: identity.authId, renterName: 'Reward renter', ownerId: 'reward-owner', ownerName: 'Owner', startDate: new Date(Date.now()+86400000), endDate: new Date(Date.now()+86400000), pricing: { baseAmount: 100, securityDeposit: 50, platformFee: 0, damageWaiverFee: 0, total: 150, currency: 'MYR' }, agreement: { version: 'renthub-booking-v1', termsHash: 'test', acceptedAt: new Date() }, status: 'pending', paymentStatus: 'unpaid', paymentDueAt: new Date(Date.now()+600000), expiresAt: new Date(Date.now()+86400000), ...extra });
}
function reward(id = 'RH-RWD-ONE', userId = identity.authId, amount = 10) {
 return RewardLedgerModel.create({ publicId: id, userId, type: 'redemption', points: -500, balanceAfter: 0, description: 'Booking reward', sourceType: 'redemption', sourceId: id, sourceKey: id, reward: { code: id, discountAmount: amount, currency: 'MYR', status: 'available' } });
}
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all([UserModel.init(), BookingModel.init(), RewardLedgerModel.init(), PaymentModel.init()]); });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => { await Promise.all([UserModel.deleteMany({}), BookingModel.deleteMany({}), RewardLedgerModel.deleteMany({}), PaymentModel.deleteMany({}), LoyaltyConfigModel.deleteMany({})]); await UserModel.create({ authId: identity.authId, email: 'reward@example.invalid', displayName: 'Reward renter', roles: ['renter','owner'], activeRole: 'renter' }); await book(); await reward(); });

test('owned checkout lists and applies one server-valued reward, preserving Owner charges and deposit', async () => {
 const list = await request(app).get(endpoint(bookingId)).set(headers).expect(200);
 assert.equal(list.body.data.items[0].amount, 10);
 const apply = await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE', discountAmount: 140 }).expect(200);
 assert.equal(apply.body.data.pricing.total, 140); assert.equal(apply.body.data.pricing.baseAmount, 100); assert.equal(apply.body.data.pricing.securityDeposit, 50);
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(200);
 assert.equal((await BookingModel.findOne({ publicId: bookingId })).pricing.total, 140);
 assert.equal(await PaymentModel.countDocuments(), 0);
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: '' }).expect(200);
 assert.equal((await BookingModel.findOne({ publicId: bookingId })).pricing.total, 150);
 assert.equal((await RewardLedgerModel.findOne()).reward.status, 'available');
});
test('foreign booking/reward, paid checkout, lease and expiry cannot bypass restrictions', async () => {
 await reward('RH-RWD-FOREIGN', 'another');
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-FOREIGN' }).expect(409);
 await book('RH-BKG-2026-FOREIGN', { renterId: 'another' });
 await request(app).get(endpoint('RH-BKG-2026-FOREIGN')).set(headers).expect(404);
 await BookingModel.updateOne({ publicId: bookingId }, { paymentLeaseUntil: new Date(Date.now()+60000) });
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(409);
 await BookingModel.updateOne({ publicId: bookingId }, { $unset: { paymentLeaseUntil: 1 }, $set: { paymentDueAt: new Date(Date.now()-1) } });
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(409);
 assert.equal((await RewardLedgerModel.findOne({ publicId: 'RH-RWD-ONE' })).reward.status, 'available');
});
test('competing bookings cannot reserve the same reward concurrently', async () => {
 await book('RH-BKG-2026-SECOND');
 const results = await Promise.all([bookingId, 'RH-BKG-2026-SECOND'].map(id => request(app).put(endpoint(id)).set(headers).send({ rewardId: 'RH-RWD-ONE' })));
 assert.deepEqual(results.map(r => r.status).sort(), [200,409]);
 assert.equal(await BookingModel.countDocuments({ 'pricing.rewardDiscount': 10 }), 1);
});
test('cash capture plus distinct platform contribution funds full Owner settlement once', async () => {
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(200);
 const auth = await paymentService.authorize({ bookingId, method: 'card', idempotencyKey: 'reward-payment' }, identity);
 assert.equal(auth.amount, 140);
 const booking = await BookingModel.findOne({ publicId: bookingId });
 await captureBookingPayment(booking); await booking.save(); await captureBookingPayment(booking);
 const balance = await bookingBalance(bookingId);
 assert.equal(balance.held, 150); assert.equal(balance.customerCaptured, 140); assert.equal(balance.rewardCredits, 10);
 assert.equal(await PaymentModel.countDocuments({ type: 'reward_credit' }), 1);
 assert.equal(await PaymentModel.countDocuments({ type: 'capture' }), 1);
 const entries = await planPhysicalSettlement(booking, 0);
 assert.equal(entries.find(e => e.type === 'owner_settlement').amount, 100);
 assert.equal(entries.find(e => e.type === 'deposit_release').amount, 50);
 await assert.rejects(planAllocations(booking, 'cashout-credit', [{ type: 'dispute_release', amount: 145 }]), e => e.code === 'REWARD_CREDIT_NOT_REFUNDABLE');
 assert.equal((await RewardLedgerModel.findOne()).reward.status, 'used');
 // A later paid extension changes the booking total; recovering the original
 // already-funded receipt must not create credit again or reject that history.
 booking.pricing.total += 20;
 await recordRewardFunding(booking);
 assert.equal(await PaymentModel.countDocuments({ type: 'reward_credit' }), 1);
});
test('expired unpaid reservation becomes reusable, and reward value cannot consume the deposit', async () => {
 await RewardLedgerModel.updateOne({ publicId: 'RH-RWD-ONE' }, { 'reward.discountAmount': 200 });
 const first = await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(200);
 assert.equal(first.body.data.pricing.total, 50); assert.equal(first.body.data.pricing.rewardDiscount, 100);
 await BookingModel.updateOne({ publicId: bookingId }, { status: 'expired' }); await book('RH-BKG-2026-NEXT');
 const list = await request(app).get(endpoint('RH-BKG-2026-NEXT')).set(headers).expect(200);
 assert.equal(list.body.data.items.length, 1);
 await assert.rejects(recordRewardFunding(await BookingModel.findOne({ publicId: bookingId })), e => e.code === 'REWARD_FUNDING_REQUIRED');
 assert.equal(await PaymentModel.countDocuments(), 0);
});
test('full cash refund returns the contribution to RentHub and never cashes out the reward', async () => {
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(200);
 await paymentService.authorize({ bookingId, method: 'wallet', idempotencyKey: 'reward-refund-payment' }, identity);
 const booking = await BookingModel.findOne({ publicId: bookingId }); const capture = await captureBookingPayment(booking); await booking.save();
 const input = { reason: 'Refund test', idempotencyKey: 'reward-full-refund' };
 const refund = await paymentService.refund(capture.publicId, input); await paymentService.refund(capture.publicId, input);
 assert.equal(refund.amount, 140); assert.equal((await bookingBalance(bookingId)).held, 0);
 assert.equal((await BookingModel.findOne({ publicId: bookingId })).paymentStatus, 'refunded');
 assert.equal(await PaymentModel.countDocuments({ type: 'refund' }), 1);
 const reversal = await PaymentModel.findOne({ type: 'platform_retention' }); assert.equal(reversal.amount, 10); assert.equal(reversal.payeeId, 'renthub:simulated-platform');
});
test('interrupted reward bookkeeping recovers without another capture or contribution', async t => {
 await request(app).put(endpoint(bookingId)).set(headers).send({ rewardId: 'RH-RWD-ONE' }).expect(200);
 await paymentService.authorize({ bookingId, method:'card', idempotencyKey:'recover-reward-payment' },identity);
 const booking=await BookingModel.findOne({publicId:bookingId});
 const update=RewardLedgerModel.updateOne.bind(RewardLedgerModel);let interrupted=false;
 t.mock.method(RewardLedgerModel,'updateOne',async (filter,change,...options)=>{
   if(!interrupted && change.$set?.['reward.status']==='used'){interrupted=true;throw Error('Temporary bookkeeping failure');}
   return update(filter,change,...options);
 });
 await assert.rejects(captureBookingPayment(booking));
 assert.equal((await RewardLedgerModel.findOne()).reward.status,'reserved');
 await captureBookingPayment(booking);
 assert.equal(await PaymentModel.countDocuments({type:'capture'}),1);
 assert.equal(await PaymentModel.countDocuments({type:'reward_credit'}),1);
 assert.equal((await RewardLedgerModel.findOne()).reward.status,'used');
 assert.equal(booking.paymentStatus,'captured');
});
