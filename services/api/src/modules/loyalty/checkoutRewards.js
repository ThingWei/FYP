import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { presentBooking } from '../../core/location.js';
import { BookingModel } from '../booking/booking.model.js';
import { bookingPaymentDeadline, payableBookingFilter } from '../booking/bookingDeadlines.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { recoverListingOperations } from '../../operations/lifecycleJournal.js';
import { PaymentModel } from '../payment/payment.model.js';
import { UserModel } from '../user/user.model.js';
import { RewardLedgerModel, LoyaltyConfigModel } from './loyalty.model.js';

const cents = value => Math.round(value * 100);
async function ownedBooking(identity, id) {
  const user = await UserModel.findOne({ authId: identity.authId, accountStatus: 'active', roles: 'renter' });
  if (!user) throw new AppError('Sign in with an active renter account.', 403, 'FORBIDDEN');
  const booking = await BookingModel.findOne({ publicId: id, renterId: identity.authId });
  if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
  return booking;
}
async function releaseClosedReservations(userId) {
  const rows = await RewardLedgerModel.find({ userId, 'reward.status': 'reserved' }).limit(100);
  for (const row of rows) {
    const booking = await BookingModel.findOne({ publicId: row.reward.bookingId, renterId: userId });
    const closed = booking && (['expired', 'cancelled', 'rejected'].includes(booking.status) || booking.status === 'pending' && booking.paymentStatus === 'unpaid' && bookingPaymentDeadline(booking) <= new Date());
    if (!closed || await PaymentModel.exists({ bookingId: booking.publicId, type: 'capture', status: 'succeeded' })) continue;
    if (booking.status === 'pending' && await PaymentModel.exists({ bookingId: booking.publicId, type: 'authorization', status: 'authorized' })) continue;
    await RewardLedgerModel.updateOne({ _id: row._id, 'reward.status': 'reserved', 'reward.bookingId': booking.publicId }, { $set: { 'reward.status': 'available' }, $unset: { 'reward.bookingId': 1 } });
  }
}
export async function checkoutRewards(identity, id) {
  const booking = await ownedBooking(identity, id);
  await releaseClosedReservations(identity.authId);
  const rows = await RewardLedgerModel.find({ userId: identity.authId, 'reward.currency': 'MYR', $or: [{ 'reward.status': 'available' }, { 'reward.status': 'reserved', 'reward.bookingId': id }] }).sort({ 'reward.discountAmount': -1, publicId: 1 }).limit(100).lean();
  const config = await LoyaltyConfigModel.findOne({ key: 'default' });
  return { enabled: config?.enabled !== false, appliedRewardId: booking.pricing.rewardId ?? null,
    items: rows.map(row => ({ id: row.publicId, code: row.reward.code, amount: row.reward.discountAmount, currency: 'MYR' })) };
}

export async function applyCheckoutReward(identity, id, rewardId = '') {
  const context = await ownedBooking(identity, id);
  return withOperationLock('listing-decision', context.listingId, async ensureOwned => {
    await recoverListingOperations(context.listingId, ensureOwned);
    await releaseClosedReservations(identity.authId);
    const token = new mongoose.Types.ObjectId().toString();
    const booking = await BookingModel.findOneAndUpdate({ publicId: id, renterId: identity.authId, status: 'pending', paymentStatus: 'unpaid',
      $or: [{ paymentLeaseUntil: { $exists: false } }, { paymentLeaseUntil: { $lte: new Date() } }] },
      { $set: { paymentLeaseToken: token, paymentLeaseUntil: new Date(Date.now() + 60_000) } }, { new: true });
    if (!booking) throw new AppError('Check the latest payment status before changing rewards.', 409, 'PAYMENT_IN_PROGRESS');
    let selected;
    try {
      if (!bookingPaymentDeadline(booking) || bookingPaymentDeadline(booking) <= new Date() || await PaymentModel.exists({ bookingId: id, type: { $in: ['authorization', 'capture'] }, status: { $in: ['authorized', 'succeeded'] } })) {
        throw new AppError('This checkout can no longer be changed.', 409, 'INVALID_BOOKING_STATE');
      }
      if (rewardId) {
        const config = await LoyaltyConfigModel.findOne({ key: 'default' });
        if (config?.enabled === false) throw new AppError('Rewards are temporarily paused.', 409, 'REWARDS_PAUSED');
        selected = await RewardLedgerModel.findOneAndUpdate({ publicId: rewardId, userId: identity.authId, 'reward.currency': 'MYR', 'reward.discountAmount': { $gt: 0 },
          $or: [{ 'reward.status': 'available' }, { 'reward.status': 'reserved', 'reward.bookingId': id }] },
          { $set: { 'reward.status': 'reserved', 'reward.bookingId': id } }, { new: true });
        if (!selected) throw new AppError('This reward is no longer available.', 409, 'REWARD_UNAVAILABLE');
      }
      const oldId = booking.pricing.rewardId;
      const gross = cents(booking.pricing.total) + cents(booking.pricing.rewardDiscount ?? 0);
      const discount = selected ? Math.min(cents(selected.reward.discountAmount), cents(booking.pricing.baseAmount)) : 0;
      if (selected && discount <= 0) throw new AppError('This booking has no rental charge to discount.', 409, 'REWARD_UNAVAILABLE');
      await ensureOwned();
      const updated = await BookingModel.findOneAndUpdate({ _id: booking._id, ...payableBookingFilter(new Date()), paymentLeaseToken: token, paymentLeaseUntil: { $gt: new Date() } }, {
        $set: { 'pricing.total': (gross - discount) / 100, 'pricing.rewardDiscount': discount / 100, 'pricing.rewardId': selected?.publicId ?? '', 'pricing.rewardCode': selected?.reward.code ?? '' },
      }, { new: true });
      if (!updated) throw new AppError('The payment window has closed.', 409, 'PAYMENT_WINDOW_EXPIRED');
      if (oldId && oldId !== selected?.publicId) await RewardLedgerModel.updateOne({ publicId: oldId, userId: identity.authId, 'reward.status': 'reserved', 'reward.bookingId': id }, { $set: { 'reward.status': 'available' }, $unset: { 'reward.bookingId': 1 } });
      return presentBooking(updated, identity);
    } catch (error) {
      // Retain a reservation whose booking update may have succeeded despite a
      // lost response. Otherwise it is safe to release only this new selection.
      if (selected) {
        const latest = await BookingModel.findById(booking._id);
        if (latest?.pricing.rewardId !== selected.publicId) await RewardLedgerModel.updateOne({ _id: selected._id, 'reward.status': 'reserved', 'reward.bookingId': id }, { $set: { 'reward.status': 'available' }, $unset: { 'reward.bookingId': 1 } });
      }
      throw error;
    } finally { await BookingModel.updateOne({ _id: booking._id, paymentLeaseToken: token }, { $unset: { paymentLeaseToken: 1, paymentLeaseUntil: 1 } }); }
  });
}

// The existing payment provider is simulated. Record the separate platform
// contribution explicitly; never charge it to the renter or deduct Owner pay.
export async function recordRewardFunding(booking) {
  const discount = booking.pricing.rewardDiscount ?? 0;
  if (!discount) return;
  const reward = await RewardLedgerModel.findOne({ publicId: booking.pricing.rewardId, userId: booking.renterId, 'reward.bookingId': booking.publicId, 'reward.status': { $in: ['reserved', 'used'] } });
  if (!reward || cents(discount) > cents(reward.reward.discountAmount)) throw new AppError('Reward funding needs review.', 409, 'REWARD_FUNDING_REQUIRED');
  const key = `reward-credit:${booking.publicId}`;
  const existing = await PaymentModel.findOne({ idempotencyKey: key });
  if (existing && (existing.type !== 'reward_credit' || existing.amount !== discount)) throw new AppError('Reward funding needs review.', 409, 'REWARD_FUNDING_REQUIRED');
  if (!existing) {
    if (!await PaymentModel.exists({ bookingId: booking.publicId, type: 'capture', status: 'succeeded', amount: booking.pricing.total, 'metadata.extensionId': { $exists: false } })) throw new AppError('Payment capture must finish before reward funding.', 409, 'REWARD_FUNDING_REQUIRED');
    try { await PaymentModel.create({ publicId: `TXN-RWD-${new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase()}`, bookingId: booking.publicId,
      payerId: 'renthub:simulated-platform', payeeId: 'renthub:simulated-holding', type: 'reward_credit', amount: discount, currency: 'MYR', method: 'system', status: 'succeeded',
      gatewayReference: `system_${key}`, idempotencyKey: key, simulated: true, metadata: { rewardId: reward.publicId } }); }
    catch (error) { if (error.code !== 11000) throw error; }
  }
  await RewardLedgerModel.updateOne({ _id: reward._id, 'reward.bookingId': booking.publicId }, { $set: { 'reward.status': 'used', 'reward.usedAt': new Date() } });
}
