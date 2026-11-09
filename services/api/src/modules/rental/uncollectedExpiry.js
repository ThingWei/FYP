import { physicalRentalDate } from '../../core/calendarDate.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from './rental.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { prepareVoidBookingPayment } from '../payment/payment.service.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { commitLifecycle, recoverListingOperations } from '../../operations/lifecycleJournal.js';
import { notifyUser } from '../communication/notification.service.js';

// Caller supplies a participant scope for read-time checks. Never treat an
// elapsed date as proof of handover or charge a no-show penalty.
export async function expireUncollectedRentals({ now = new Date(), scope = {} } = {}) {
  const filter = { ...scope, listingType: 'physical', status: 'scheduled', endDate: { $lt: physicalRentalDate(now) } };
  const candidates = await RentalModel.find(filter).select('publicId listingId').sort({ endDate: 1, _id: 1 }).limit(100).lean();
  let expired = 0, needsReview = 0;
  for (const candidate of candidates) {
    await withOperationLock('listing-decision', candidate.listingId, async ensureOwned => {
      await recoverListingOperations(candidate.listingId, ensureOwned);
      const rental = await RentalModel.findOne({ ...filter, publicId: candidate.publicId });
      if (!rental || rental.handover?.recordedAt || rental.handover?.condition || rental.handover?.evidence?.length) return;
      const booking = await BookingModel.findOne({ publicId: rental.bookingId, status: 'approved' });
      if (!booking) return;
      const hold = await PaymentModel.findOne({ bookingId: booking.publicId, type: 'authorization',
        'metadata.extensionId': { $exists: false }, status: { $in: ['authorized', 'voided'] } }).sort({ createdAt: -1 }).lean();
      if (['captured', 'settled', 'partially_refunded', 'refunded'].includes(booking.paymentStatus) ||
          await PaymentModel.exists({ bookingId: booking.publicId, type: 'capture', status: 'succeeded' }) ||
          booking.paymentStatus === 'authorized' && !hold ||
          hold && (hold.payerId !== booking.renterId || hold.amount !== booking.pricing.total)) {
        needsReview++;
        await notifyUser({ userId: rental.ownerId, category: 'rental', type: 'uncollected_review_needed',
          title: 'Booking needs review', body: 'The booked dates ended without a handover record, but the payment records need checking. Contact support before taking further action.',
          entityType: 'rental', entityId: rental.publicId, dedupeKey: `uncollected-review:${rental.publicId}` });
        return;
      }
      const authorization = await prepareVoidBookingPayment(booking);
      if (!authorization && hold?.status === 'voided') booking.paymentStatus = 'voided';
      const record = await blockchainAdapter.cancel(rental.blockchain?.contractAddress || rental.contractAddress);
      rental.blockchain = { ...rental.blockchain?.toObject?.(), ...record };
      rental.transactionHash = record.lastTransactionHash ?? rental.transactionHash;
      rental.status = 'expired'; rental.expiredAt = now; rental.expiryReason = 'not_collected';
      booking.status = 'expired'; booking.expiredAt = now;
      booking.cancellationReason = 'The booked dates ended without a recorded handover. The item was not collected.';
      const notifications = [rental.ownerId, rental.renterId].map(userId => ({
        userId, category: 'rental', type: 'rental_not_collected', title: 'Booking expired — item not collected',
        body: `${booking.listingTitle} ended without a recorded handover. No rental started.${authorization ? ' The demo payment hold, including the deposit, was released.' : ' Check payment details for its current status.'}`,
        entityType: 'rental', entityId: rental.publicId, dedupeKey: `not-collected:${rental.publicId}:${userId}`,
      }));
      await commitLifecycle(`not-collected:${rental._id}`, rental.listingId,
        [...(authorization ? [authorization] : []), rental, booking], ensureOwned, { notifications });
      expired++;
    });
  }
  return { expired, needsReview };
}
