import { validRentalPrice } from './priceLimits.js';
import { productTypeFor } from './priceProductDomains.js';
import { robustPriceStats } from './pricingEvidence.js';

// Deliberately separate from bookingEvidenceReason and all training exports.
// A recorded simulation is evidence about app behaviour, not achieved market prices.
export function demonstrationBookingReason(booking, payments, now = new Date()) {
  if (booking.status !== 'completed' || booking.listingType !== 'physical') return 'not_completed_physical';
  const snapshot = booking.pricingEvidenceSnapshot;
  if (!snapshot || snapshot.listingType !== 'physical' || !snapshot.category || !snapshot.subcategory || !snapshot.brand || !snapshot.productModel) return 'missing_historical_snapshot';
  const origin = snapshot.priceProvenance?.origin;
  if (['ai_suggested', 'ai_edited'].includes(origin)) return 'ai_derived';
  if (!['owner_entered', 'external_reference'].includes(origin)) return 'unknown_price_origin';
  if (!booking.completedAt || !Number.isFinite(+new Date(booking.completedAt)) || new Date(booking.completedAt) > now) return 'invalid_completion';
  if (!['captured', 'settled'].includes(booking.paymentStatus) || !(booking.pricing?.baseAmount > 0)) return 'unpaid';
  if (booking.pricing.currency && booking.pricing.currency !== 'MYR') return 'incompatible_currency';
  const captures = payments.filter((p) => p.bookingId === booking.publicId && p.type === 'capture' && p.status === 'succeeded');
  return captures.some((p) => p.simulated === true && p.currency === 'MYR' &&
    Number.isFinite(p.amount) && p.amount >= booking.pricing.baseAmount && p.createdAt &&
    Number.isFinite(+new Date(p.createdAt)) && new Date(p.createdAt) <= new Date(booking.completedAt))
    ? null : 'missing_simulated_capture';
}

// A factual guide from selected, compatible observations, not a new prediction.
// Particularly useful when only one quote exists or all observed amounts agree.
export function limitedPriceGuide(activeTier, historicalTier, category) {
  const history = historicalTier.items.filter((r) => validRentalPrice(r.dailyPrice, category));
  const asking = activeTier.items.filter((r) => validRentalPrice(r.dailyPrice, category));
  const rows = history.length ? history : asking;
  if (!rows.length) return null;
  const stats = robustPriceStats(rows.map((r) => r.dailyPrice));
  const prices = rows.map((r) => r.dailyPrice);
  return { available: true, suggested_daily_price: Math.round(stats.median * 100) / 100,
    lower_bound: rows.length > 1 ? Math.min(...prices) : null,
    upper_bound: rows.length > 1 ? Math.max(...prices) : null,
    model_source: 'limited_comparable_reference', estimate_kind: 'reference_guide',
    confidence: 0, confidence_label: 'low', reference_count: rows.length,
    reference_basis: history.length ? 'completed_records' : 'asking_prices' };
}

export function priceRecovery(profile, candidates, selectedCount, aiUnavailable = false) {
  const type = productTypeFor(profile.category, profile.subcategory,
    `${profile.brand ?? ''} ${profile.product_model ?? ''}`, profile.productType);
  const compatibleCount = selectedCount;
  return { status: compatibleCount ? 'temporary_service_issue' : !type ? 'product_details_needed'
      : candidates > 0 ? 'no_compatible_prices' : 'building_price_coverage',
    category: profile.category, subcategory: profile.subcategory, productType: type,
    canRetry: compatibleCount > 0 && aiUnavailable,
    manualPricingAvailable: true };
}
