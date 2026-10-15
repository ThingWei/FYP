import { AppError } from '../../core/errors.js';
import { NotificationModel } from './notification.model.js';
import { ThreadModel } from './thread.model.js';
import { MessageModel } from './message.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ClaimModel } from '../dispute/claim.model.js';
import { ReviewModel } from '../review/review.model.js';

// Navigation hints only. Destination reads/actions retain their own authorization.
export async function notificationTarget(id, identity) {
  const note = await NotificationModel.findOne({ publicId: id, userId: identity.authId }).lean();
  if (!note) throw new AppError('Notification not found', 404, 'NOT_FOUND');
  const unavailable = { kind: 'unavailable' };
  const participant = { $or: [{ renterId: identity.authId }, { ownerId: identity.authId }] };
  async function bookingTarget(bookingId, kind = 'booking', extra = {}) {
    const booking = await BookingModel.findOne({ publicId: bookingId, ...participant }).select('publicId').lean();
    if (!booking) return unavailable;
    const rental = await RentalModel.findOne({ bookingId, ...participant }).select('publicId').lean();
    return { kind, bookingId, ...(rental && { rentalId: rental.publicId }), ...extra };
  }
  if (note.entityType === 'booking') return bookingTarget(note.entityId);
  if (note.entityType === 'rental') {
    const row = await RentalModel.findOne({ publicId: note.entityId, ...participant }).select('bookingId').lean();
    return row ? bookingTarget(row.bookingId) : unavailable;
  }
  if (note.entityType === 'payment') {
    const row = await PaymentModel.findOne({ publicId: note.entityId, $or: [{ payerId: identity.authId }, { payeeId: identity.authId }] }).select('bookingId publicId').lean();
    return row ? bookingTarget(row.bookingId, 'booking', { paymentId: row.publicId }) : unavailable;
  }
  if (['thread', 'message'].includes(note.entityType)) {
    const message = note.entityType === 'message' ? await MessageModel.findOne({ publicId: note.entityId }).select('threadId').lean() : null;
    if (note.entityType === 'message' && !message) return unavailable;
    const thread = await ThreadModel.findOne({ publicId: message?.threadId ?? note.entityId, participantIds: identity.authId }).select('bookingId publicId').lean();
    return thread ? bookingTarget(thread.bookingId, 'chat', { threadId: thread.publicId }) : unavailable;
  }
  if (['dispute', 'claim'].includes(note.entityType)) {
    const claim = note.entityType === 'claim' ? await ClaimModel.findOne({ publicId: note.entityId, ...participant }).select('disputeId publicId').lean() : null;
    if (note.entityType === 'claim' && !claim) return unavailable;
    const dispute = await DisputeModel.findOne({ publicId: claim?.disputeId ?? note.entityId,
      $or: [{ raisedById: identity.authId }, { respondentId: identity.authId }] }).select('bookingId publicId').lean();
    return dispute ? bookingTarget(dispute.bookingId, 'dispute', { disputeId: dispute.publicId, ...(claim && { claimId: claim.publicId }) }) : unavailable;
  }
  if (note.entityType === 'review') {
    const row = await ReviewModel.findOne({ publicId: note.entityId, $or: [{ authorId: identity.authId }, { subjectId: identity.authId }] }).select('bookingId').lean();
    return row ? bookingTarget(row.bookingId) : unavailable;
  }
  if (['reward','referral'].includes(note.entityType)) return { kind:'rewards' };
  if (note.entityType === 'user' && note.entityId === identity.authId && note.category === 'verification') return { kind:'verification' };
  return unavailable;
}
