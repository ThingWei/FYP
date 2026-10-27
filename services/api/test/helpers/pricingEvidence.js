// Reviewed/payment fixtures only. Never used by seed scripts or live data.
import { priceContext, pricingSnapshot } from '../../src/modules/listing/priceProvenance.js';
export function reviewedPrice(item) {
  const row = { sourceType: 'marketplace', ...item };
  return { ...row, priceProvenance: { origin: 'owner_entered', independence: 'reviewed',
    reviewedBy: 'fixture-reviewer', reviewedAt: new Date('2026-01-01'), contextFingerprint: priceContext(row) } };
}
export function reviewedBooking(booking, listing) {
  return { ...booking, publicId: booking.publicId ?? `fixture-${booking.listingId}`,
    pricingEvidenceSnapshot: pricingSnapshot(reviewedPrice(listing)) };
}
export const realPayment = (booking) => ({ bookingId: booking.publicId, type: 'capture', status: 'succeeded',
  amount: booking.pricing.baseAmount, currency: 'MYR', createdAt: new Date('2026-01-01'), simulated: false, gatewayReference: 'fixture-independent-payment' });
