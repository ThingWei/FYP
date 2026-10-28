import { createHash } from 'node:crypto';

export const PRICE_ORIGINS = ['unknown', 'owner_entered', 'ai_suggested', 'ai_edited', 'external_reference'];
export const DECLARED_PRICE_ORIGINS = ['unknown', 'owner_entered', 'ai_suggested', 'ai_edited'];
const plain = (value) => value?.toObject ? value.toObject() : value;
export function priceContext(item) {
  return createHash('sha256').update(JSON.stringify([
    item.category, item.subcategory, item.brand, item.productModel ?? item.product_model,
    item.canonicalProductId, item.condition, item.itemAgeYears ?? item.item_age_years,
    item.isbn, item.edition, item.variant, item.packageType, item.dailyPrice,
  ].map((v) => v == null || v === '' ? null : v))).digest('hex');
}

// Client declarations never grant independent/reviewed status. Legacy omissions
// remain unknown. Editing an AI-derived amount cannot wash its lineage away.
export function nextPriceProvenance(input, previous = {}, now = new Date()) {
  const old = plain(previous.priceProvenance);
  const next = { ...plain(previous), ...input };
  const changed = priceContext(next) !== priceContext(previous);
  if (old && !changed && !input.priceProvenance) return old;
  const declared = input.priceProvenance;
  if (old && !changed && declared?.origin === old.origin) return old;
  const ai = ['ai_suggested', 'ai_edited'].includes(old?.origin);
  let origin = declared?.origin ?? (changed && input.dailyPrice !== undefined ? 'owner_entered' : old?.origin ?? 'unknown');
  if (ai && origin !== 'ai_suggested') origin = 'ai_edited';
  if (ai && changed && !declared) origin = 'ai_edited';
  if ((old?.origin === 'external_reference' || old?.originatingOfferKey) && !['ai_suggested', 'ai_edited'].includes(origin)) origin = 'external_reference';
  const supplied = { ...old, ...declared };
  return { origin, independence: 'unverified', recordedAt: now,
    ...(old?.originatingOfferKey && { originatingOfferKey: old.originatingOfferKey }),
    ...(Number.isFinite(supplied.suggestedAmount) && { suggestedAmount: supplied.suggestedAmount }),
    ...(supplied.modelVersion && { modelVersion: supplied.modelVersion }),
  };
}

export function listingEvidenceReason(item) {
  if (item.sourceType === 'demo_seed') return 'demonstration';
  if (item.sourceType !== 'marketplace') return 'unknown_activity';
  const p = plain(item.priceProvenance);
  if (['ai_suggested', 'ai_edited'].includes(p?.origin)) return 'ai_derived';
  if (p?.origin === 'external_reference' || p?.originatingOfferKey) return 'derived_external_copy';
  if (!p || p.origin === 'unknown') return 'unknown_price_origin';
  if (p.origin !== 'owner_entered' || p.independence !== 'reviewed' ||
      !p.reviewedBy || !p.reviewedAt || !Number.isFinite(+new Date(p.reviewedAt)) || new Date(p.reviewedAt) > new Date() ||
      p.contextFingerprint !== priceContext(item)) return 'unverified_owner_price';
  return null;
}

export function bookingEvidenceReason(booking, payments = []) {
  if (booking.sourceType === 'demo_seed') return 'demonstration';
  const records = payments.filter((p) => p.bookingId === booking.publicId);
  if (records.some((p) => p.simulated === true)) return 'simulated_payment';
  const snapshot = plain(booking.pricingEvidenceSnapshot);
  if (!snapshot) return 'missing_historical_snapshot';
  const reason = listingEvidenceReason(snapshot);
  if (reason) return reason;
  const paid = records.some((p) => p.simulated === false && p.gatewayReference &&
    !p.gatewayReference.startsWith('sim_') && p.currency === 'MYR' && Number.isFinite(p.amount) &&
    p.amount > 0 && p.amount >= booking.pricing?.baseAmount && p.createdAt &&
    Number.isFinite(+new Date(p.createdAt)) && new Date(p.createdAt) <= new Date() &&
    (booking.status === 'completed' ? p.type === 'capture' && p.status === 'succeeded'
      : p.type === 'authorization' && p.status === 'authorized' || p.type === 'capture' && p.status === 'succeeded'));
  return paid ? null : 'unverified_payment';
}

export function pricingSnapshot(listing) {
  const fields = ['listingType', 'sourceType', 'category', 'subcategory', 'brand', 'productModel',
    'canonicalProductId', 'condition', 'itemAgeYears', 'isbn', 'edition', 'variant', 'packageType', 'dailyPrice', 'state'];
  return { ...Object.fromEntries(fields.filter((k) => listing[k] !== undefined).map((k) => [k, listing[k]])),
    priceProvenance: structuredClone(plain(listing.priceProvenance) ?? { origin: 'unknown', independence: 'unverified' }) };
}
