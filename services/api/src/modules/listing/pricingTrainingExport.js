// Read-only, provenance-aware training preparation. Never creates transactions.
import { createHash } from 'node:crypto';
import { validRentalPrice } from './priceLimits.js';
import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';
import { productTypeFor } from './priceSources.registry.js';
import { compatibleProductReference, referencePeriodMatches, referenceIdentityUncertain, referenceOfferKey } from './priceProductDomains.js';
import { listingEvidenceReason, bookingEvidenceReason } from './priceProvenance.js';
import { PRICING_COMPLETED_PAYMENT_STATUSES, PRICING_EVIDENCE_WINDOW_DAYS,
  robustPriceStats, selectComparableTier } from './pricingEvidence.js';

const DAY = 86_400_000;
const hash = (value) => createHash('sha256').update(String(value)).digest('hex').slice(0, 24);
const normalized = (value) => String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
const date = (value) => value && Number.isFinite(new Date(value).getTime()) ? new Date(value) : null;
const future = (value, now) => date(value) && date(value) > now;
const asking = new Set(['active_asking', 'demo_seed_active_asking', 'external_asking_price']);
const completed = new Set(['completed_rental', 'demo_seed_completed_rental']);

export function trainingProductGroup(item) {
  if (item.identityLevel !== 'specification_only' && item.canonicalProductId) {
    return `product:${hash(item.canonicalProductId)}`;
  }
  if (item.identityLevel !== 'specification_only' && item.brand && item.productModel) {
    return `product-text:${hash([item.category, item.subcategory, item.brand, item.productModel].map(normalized).join('|'))}`;
  }
  if (item.sourceProductKey) return `external-product:${hash(`${item.sourceId}:${item.sourceProductKey}`)}`;
  return `record:${hash(item.publicId)}`;
}

function base(item, observed, dailyPrice, target, source) {
  return {
    category: item.category, subcategory: item.subcategory || 'Unknown',
    condition: item.condition || null, brand: item.brand || null,
    product_model: item.productModel || item.title,
    canonicalProductId: item.identityLevel === 'specification_only' ? null : item.canonicalProductId ?? null,
    productMatchType: item.canonicalProductId && item.identityLevel !== 'specification_only' ? 'exact_catalog_match' : 'manual_entry',
    state: item.state || 'Unknown',
    // Never export a private unit/address, exact coordinates or reviewer identity.
    location: item.locationDetails?.city || item.state || 'Unknown',
    item_age_years: item.itemAgeYears ?? null, owner_trust_score: null,
    owner_average_rating: null, owner_completed_rentals: null,
    daily_price: dailyPrice, source_type: source, target_source: target,
    observed_at: observed.toISOString(), group_id: trainingProductGroup(item),
    identity_level: item.identityLevel ?? 'named_product',
    product_type: item.productType ?? null,
    price_origin: item.priceProvenance?.origin ?? (source === 'external_asking_price' ? 'external_reference' : 'unknown'),
    independent_evidence: source === 'external_asking_price' || !listingEvidenceReason(item),
    isbn: item.isbn || '', edition: item.edition || '', variant: item.variant || '', packageType: item.packageType || '',
    _ownerId: item.ownerId ?? null, _knownAt: observed,
  };
}

export function eligibleTrainingReference(row, enabledSourceIds, now = new Date()) {
  const observed = date(row.observedAt), amount = row.quotedAmount, days = row.rentalDurationDays;
  if (row.active !== true || row.sourceType !== 'external_asking_price' || row.currency !== 'MYR' || row.country !== 'MY' ||
      !observed || observed > now || observed < new Date(now - PRICING_EVIDENCE_WINDOW_DAYS * DAY) ||
      !CATALOG_COVERAGE.some((c) => c.category === row.category && c.subcategory === row.subcategory) ||
      !row.productModel || !row.sourceName || !row.sourceUrl ||
      !Number.isFinite(amount) || amount <= 0 || Math.abs(amount * 100 - Math.round(amount * 100)) > 1e-6 ||
      !Number.isInteger(days) || days < 1 || days > 365 || !validRentalPrice(amount / days, row.category) ||
      (row.itemAgeYears != null && (!Number.isFinite(row.itemAgeYears) || row.itemAgeYears < 0 || row.itemAgeYears > 100)) ||
      !Number.isFinite(row.dailyPrice) || Math.abs(row.dailyPrice - amount / days) > 1e-6 ||
      /\bfrom\b|starting|chauffeur|crew included|operator included|setup included|service bundle|\$|USD|SGD/i.test(row.packageNotes ?? '')) return false;
  try {
    const url = new URL(row.sourceUrl);
    if (url.protocol !== 'https:' || url.username || url.password || /^(localhost|127\.|\[?::1\]?)/i.test(url.hostname)) return false;
  } catch { return false; }
  if (row.collectionMethod === 'automatic') {
    const min = row.durationMinDays, max = row.durationMaxDays;
    return enabledSourceIds.includes(row.sourceId) && row.validationStatus === 'accepted' &&
      Boolean(date(row.validatedAt)) && !future(row.validatedAt, now) &&
      Boolean(row.productType) && row.productType === productTypeFor(row.category, row.subcategory, `${row.brand ?? ''} ${row.productModel}`) &&
      Number.isInteger(min) && Number.isInteger(max) && min >= 1 && max <= 365 && min <= max;
  }
  return (row.collectionMethod === 'manual_csv' || !row.collectionMethod) &&
    Boolean(row.brand && row.reviewedBy && date(row.reviewedAt)) && !future(row.reviewedAt, now);
}

// Shared by export preparation and offline forward-time evaluation. The caller
// restricts history to its training side; this function also excludes future,
// late-known, same-product and incompatible evidence for each target.
export function trainingComparableFeatures(row, history, reviews = []) {
  const at = date(row.observed_at);
  if (!at) throw new Error('Invalid observation time');
  const prior = history.filter((candidate) => {
    const observed = date(candidate.observed_at);
    const known = date(candidate._knownAt) || date(candidate.available_at) ||
      (candidate.source_type !== 'external_asking_price' ? observed : null);
    return candidate.group_id !== row.group_id &&
      !(candidate.origin_offer_key && candidate.origin_offer_key === row.origin_offer_key) && candidate.category === row.category &&
      observed && known && observed < at && known < at &&
      observed >= new Date(at - PRICING_EVIDENCE_WINDOW_DAYS * DAY) &&
      (candidate.source_type === 'external_asking_price' || candidate.source_type === 'real' && candidate.independent_evidence === true);
  });
  const asCandidate = (r) => ({ ...r, productModel: r.product_model, dailyPrice: r.daily_price,
    identityMatchUncertain: r.source_type === 'external_asking_price' && referenceIdentityUncertain({ ...r, packageNotes: r.package_notes }, row),
    identityLevel: r.identity_level, observedAt: r.observed_at });
  const externalCompatible = (r) => compatibleProductReference({ ...r,
    productType: r.product_type, packageNotes: r.package_notes }, row) && referencePeriodMatches({
    durationMinDays: r.duration_min_days, durationMaxDays: r.duration_max_days,
    rentalDurationDays: r.quoted_rental_days ?? r.rental_duration_days,
  }, row.rental_duration_days);
  const activeTier = selectComparableTier(prior.filter((r) => asking.has(r.target_source) &&
    (r.source_type !== 'external_asking_price' || externalCompatible(r))).map(asCandidate), row);
  const historyTier = selectComparableTier(prior.filter((r) => completed.has(r.target_source)).map(asCandidate), row);
  const active = robustPriceStats(activeTier.items.map((r) => r.dailyPrice));
  const historical = robustPriceStats(historyTier.items.map((r) => r.dailyPrice));
  const dates = [...activeTier.items, ...historyTier.items].map((r) => +new Date(r.observed_at));
  const ownerReviews = row._ownerId ? reviews.filter((r) => r.subjectId === row._ownerId && date(r.createdAt) < at &&
    date(r.createdAt) && Number.isFinite(r.overallRating)) : [];
  return {
    comparable_active_count: active.count, comparable_active_median: active.median,
    comparable_active_mean: active.mean, comparable_active_iqr: active.iqr,
    historical_rental_count: historical.count, historical_rental_median: historical.median,
    historical_rental_mean: historical.mean, historical_rental_iqr: historical.iqr,
    marketplace_active_listing_count: activeTier.items.filter((r) => r.target_source === 'active_asking').length,
    external_asking_price_count: activeTier.items.filter((r) => r.source_type === 'external_asking_price').length,
    active_comparable_tier: activeTier.name, historical_comparable_tier: historyTier.name,
    market_freshness_days: dates.length ? Math.max(0, Math.floor((at - Math.max(...dates)) / DAY)) : null,
    demand_supply_ratio: historical.count / Math.max(active.count, 1),
    owner_average_rating: row._ownerId && ownerReviews.length ? ownerReviews.reduce((s, r) => s + r.overallRating, 0) / ownerReviews.length : null,
    owner_completed_rentals: row._ownerId ? prior.filter((r) => r._ownerId === row._ownerId && completed.has(r.target_source)).length : null,
    prediction_month: at.getUTCMonth() + 1,
  };
}

export function buildPricingTrainingExport({ listings = [], bookings = [], reviews = [], references = [],
  payments = [], includeDemoDiagnostics = false, enabledSourceIds = [], now = new Date() } = {}) {
  const byId = new Map(listings.map((item) => [item.publicId, item]));
  const observations = [], seen = new Map();
  const excludedPlatform = {};
  const exclude = (reason) => { excludedPlatform[reason] = (excludedPlatform[reason] ?? 0) + 1; };
  for (const booking of bookings) {
    const reason = bookingEvidenceReason(booking, payments);
    const demo = booking.sourceType === 'demo_seed' || byId.get(booking.listingId)?.sourceType === 'demo_seed';
    if (reason && !(includeDemoDiagnostics && demo)) { exclude(reason); continue; }
    const listing = booking.pricingEvidenceSnapshot ?? (demo ? byId.get(booking.listingId) : null);
    if (!listing || listing.listingType !== 'physical' || !['approved', 'active', 'completed'].includes(booking.status) ||
        !['authorized', ...PRICING_COMPLETED_PAYMENT_STATUSES].includes(booking.paymentStatus)) continue;
    const start = date(booking.startDate), end = date(booking.endDate);
    if (!start || !end || end < start) continue;
    const days = Number.isInteger(booking.pricing?.originalRentalDays) && booking.pricing.originalRentalDays >= 1
      ? booking.pricing.originalRentalDays : Math.floor((end - start) / DAY) + 1;
    if (days > 365) continue;
    const price = booking.pricing?.baseAmount / days;
    if (!Number.isFinite(price) || price <= 0 || price > 1_000_000) continue;
    const isCompleted = booking.status === 'completed';
    if (isCompleted && !PRICING_COMPLETED_PAYMENT_STATUSES.includes(booking.paymentStatus)) continue;
    const at = date(isCompleted && booking.completedAt) || date(booking.decidedAt) || date(booking.createdAt);
    if (!at || at > now) continue;
    const knownAt = new Date(Math.max(+at, +(date(listing.priceProvenance?.reviewedAt) || 0),
      ...payments.filter((p) => p.bookingId === booking.publicId && p.simulated === false)
        .map((p) => +(date(p.createdAt) || 0))));
    if (knownAt > now) { exclude('future_payment_or_review'); continue; }
    observations.push({ ...base(listing, at, price,
      `${demo ? 'demo_seed_' : ''}${isCompleted ? 'completed_rental' : 'accepted_booking'}`, demo ? 'demo_seed' : 'real'),
    _knownAt: knownAt, available_at: knownAt.toISOString(),
    rental_duration_days: days, independent_evidence: !reason,
    payment_simulated: reason === 'simulated_payment' });
  }
  for (const item of listings) {
    const at = date(item.updatedAt) || date(item.createdAt);
    if (item.listingType !== 'physical' || item.status !== 'active' || !at || at > now ||
        !Number.isFinite(item.dailyPrice) || item.dailyPrice <= 0 || item.dailyPrice > 1_000_000) continue;
    const demo = item.sourceType === 'demo_seed';
    const reason = listingEvidenceReason(item);
    if (reason && !(includeDemoDiagnostics && demo)) { exclude(reason); continue; }
    const knownAt = new Date(Math.max(+at, +(date(item.priceProvenance?.reviewedAt) || 0)));
    if (knownAt > now) { exclude('future_review'); continue; }
    observations.push({ ...base(item, at, item.dailyPrice, demo ? 'demo_seed_active_asking' : 'active_asking',
      demo ? 'demo_seed' : 'real'), _knownAt: knownAt, available_at: knownAt.toISOString(),
      rental_duration_days: 1, independent_evidence: !reason });
  }
  let excludedReferences = 0, duplicates = 0;
  const quoteFingerprints = new Set();
  for (const reference of references) {
    if (!eligibleTrainingReference(reference, enabledSourceIds, now)) { excludedReferences++; continue; }
    const offer = reference.originatingOfferKey || referenceOfferKey(reference);
    const period = [offer, reference.durationMinDays ?? reference.rentalDurationDays,
      reference.durationMaxDays ?? reference.rentalDurationDays];
    const key = JSON.stringify([...period, date(reference.observedAt)?.toISOString()]);
    if (!key) { excludedReferences++; continue; }
    if (seen.has(key)) {
      if (seen.get(key) !== reference.dailyPrice) throw new Error('Conflicting reference observations; no export written');
      duplicates++; continue;
    }
    seen.set(key, reference.dailyPrice);
    const fingerprint = JSON.stringify([...period, reference.dailyPrice]);
    if (quoteFingerprints.has(fingerprint)) { duplicates++; continue; }
    quoteFingerprints.add(fingerprint);
    const row = base(reference, date(reference.observedAt), reference.dailyPrice, 'external_asking_price', 'external_asking_price');
    // A spec-only quote must never become a canonical or same-brand identity.
    if (reference.identityLevel === 'specification_only') row.brand = null;
    const manual = reference.collectionMethod !== 'automatic';
    row._knownAt = new Date(Math.max(+date(reference.observedAt), +(date(reference.createdAt) || 0),
      +date(manual ? reference.reviewedAt : reference.validatedAt)));
    if (row._knownAt > now) { excludedReferences++; continue; }
    const days = reference.rentalDurationDays;
    const featureDays = manual || days >= reference.durationMinDays && days <= reference.durationMaxDays
      ? days : reference.durationMinDays;
    observations.push({ ...row, rental_duration_days: featureDays, quoted_rental_days: days,
      duration_feature_basis: featureDays === days ? 'quoted_period' : 'eligible_band_minimum',
      duration_min_days: reference.durationMinDays ?? days, duration_max_days: reference.durationMaxDays ?? days,
      collection_method: reference.collectionMethod ?? 'manual_csv', source_name: reference.sourceName,
      source_url: reference.sourceUrl, package_notes: reference.packageNotes ?? '',
      origin_offer_key: hash(offer),
      available_at: row._knownAt.toISOString() });
  }
  observations.sort((a, b) => new Date(a.observed_at) - new Date(b.observed_at) || a.group_id.localeCompare(b.group_id));
  const prepared = [];
  for (const row of observations) {
    prepared.push({ ...row, ...trainingComparableFeatures(row, prepared, reviews) });
  }
  const rows = prepared.map(({ _ownerId, _knownAt, ...row }) => row);
  const counts = (field) => rows.reduce((result, row) => { result[row[field]] = (result[row[field]] || 0) + 1; return result; }, {});
  return { schemaVersion: 'renthub-pricing-observations-v2', generatedAt: now.toISOString(), rows,
    summary: { rows: rows.length, sourceTypes: counts('source_type'), targetSources: counts('target_source'),
      excludedReferences, duplicateReferences: duplicates,
      excludedPlatform,
      limitations: ['Source markers do not independently verify real-world transactions',
        'Current listing metadata is not a historical product-profile snapshot',
        'Advertised asking prices are not completed rentals; no URLs were fetched'] } };
}
