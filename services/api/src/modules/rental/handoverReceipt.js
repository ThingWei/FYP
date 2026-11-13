import { AppError } from '../../core/errors.js';
import { RentalModel } from './rental.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { captureBookingPayment } from '../payment/payment.service.js';

export const requiresReceipt = rental => rental?.listingType === 'physical' && rental.handover?.version === 2;
export const awaitingReceipt = rental => requiresReceipt(rental) && rental.handover.receiptStatus !== 'acknowledged';

export async function assertHandoverAuthorization(booking) {
  const authorization = await PaymentModel.findOne({ bookingId: booking.publicId, type: 'authorization',
    status: 'authorized', 'metadata.extensionId': { $exists: false } }).sort({ createdAt: -1 });
  if (booking.paymentStatus !== 'authorized' || !authorization || authorization.payerId !== booking.renterId ||
      authorization.payeeId !== booking.ownerId || authorization.amount !== booking.pricing.total || authorization.currency !== 'MYR') {
    throw new AppError('An active demo payment hold is required before handover.', 409, 'PAYMENT_NOT_AUTHORIZED');
  }
}

// Runs only from a durable server-created lifecycle intent, under the listing
// lock. A valid acceptance survives a lost response or midnight during recovery.
export async function prepareHandoverCapture(intent, ensureOwned) {
  const [rental, booking] = await Promise.all([
    RentalModel.findById(intent.rentalId), BookingModel.findById(intent.bookingId),
  ]);
  if (!requiresReceipt(rental) || rental.handover.handoverId !== intent.handoverId ||
      rental.renterId !== intent.renterId || rental.bookingId !== booking?.publicId ||
      !['scheduled', 'active'].includes(rental.status) || !['approved', 'active'].includes(booking.status)) {
    throw new AppError('Receipt confirmation needs review.', 409, 'RECOVERY_REQUIRED');
  }
  await ensureOwned();
  await RentalModel.updateOne({ _id: rental._id, 'handover.handoverId': intent.handoverId,
    'handover.receiptStatus': 'pending' }, { $set: { 'handover.receiptStatus': 'processing',
    'handover.acceptedAt': intent.acceptedAt, 'handover.acknowledgedBy': intent.renterId } });
  // No revision increment: this is the processing phase of the already-durable
  // operation. Its final revision-fenced plan replaces the complete handover.
  const capture = await captureBookingPayment(booking);
  if (!capture || capture.status !== 'succeeded' || capture.amount !== booking.pricing.total) {
    throw new AppError('Receipt confirmation is processing. Check the latest status before retrying.', 503, 'HANDOVER_PROCESSING');
  }
  await ensureOwned();
}
