// A dispute pauses settlement, not the renter's ability to return a received item.
export function rentalReturnAllowed(rental, booking, dispute) {
  if (rental.listingType !== 'physical' || rental.returnSubmission?.recordedAt) return false;
  if (['active', 'overdue'].includes(rental.status)) return true;
  return Boolean(rental.status === 'disputed' && booking?.status === 'disputed' &&
    ['captured', 'partially_refunded', 'settled'].includes(booking.paymentStatus) &&
    dispute && !['resolved', 'dismissed'].includes(dispute.status) &&
    ['active', 'overdue', 'return_submitted'].includes(dispute.previousRentalStatus) &&
    !(rental.handover?.version === 2 && rental.handover.receiptStatus !== 'acknowledged'));
}
