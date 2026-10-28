import { minimumRentalPrice, validRentalPrice } from './priceLimits.js';
import { compatibleProductReference } from './priceProductDomains.js';
import { annotateComparable, comparableDurationFits, comparableSelection, conditionSimilarity,
  MAX_SELECTED_COMPARABLES, modelNeighbourhoodScore, sameComparableFamily } from './pricingSimilarity.js';

export const PRICING_EVIDENCE_WINDOW_DAYS = 365;
export const PRICING_EVIDENCE_QUERY_LIMIT = 1000;
export const PRICING_FALLBACK_MIN_OBSERVATIONS = 3;
export const PRICING_COMPLETED_PAYMENT_STATUSES = ['captured', 'settled'];

function normalized(value) {
  return String(value ?? '').trim().toLowerCase();
}

function same(value, expected) {
  return Boolean(normalized(expected)) && normalized(value) === normalized(expected);
}

function canonicalSame(item, profile) {
  return !item.identityMatchUncertain && !item.durationBaseline && item.identityLevel !== 'specification_only' && Boolean(profile.canonicalProductId) &&
    item.canonicalProductId === profile.canonicalProductId;
}

function sameProductName(item, profile) {
  return item.identityLevel !== 'specification_only' && same(item.subcategory, profile.subcategory) &&
    same(item.brand, profile.brand) &&
    same(item.productModel, profile.product_model);
}

function sameProductText(item, profile) {
  return !item.identityMatchUncertain && !item.durationBaseline && sameProductName(item, profile);
}

const hierarchy = [
  {
    name: 'exact_canonical_city',
    minimum: 1,
    match: (item, profile) =>
      canonicalSame(item, profile) && same(item.location, profile.location),
  },
  {
    name: 'exact_canonical_state',
    minimum: 1,
    match: (item, profile) =>
      canonicalSame(item, profile) && same(item.state, profile.state),
  },
  {
    name: 'exact_canonical_malaysia',
    minimum: 1,
    match: canonicalSame,
  },
  {
    name: 'exact_product_malaysia',
    minimum: 1,
    match: sameProductText,
  },
  {
    name: 'subcategory_brand_model_unconfirmed',
    minimum: 1,
    match: (item, profile) => (item.identityMatchUncertain || item.durationBaseline) && sameProductName(item, profile),
  },
  {
    name: 'subcategory_brand_model_family',
    minimum: 2,
    match: sameComparableFamily,
  },
  {
    name: 'subcategory_brand_condition_state',
    minimum: 2,
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) &&
      same(item.brand, profile.brand) &&
      same(item.condition, profile.condition) &&
      same(item.state, profile.state),
  },
  {
    name: 'subcategory_brand_malaysia',
    minimum: 2,
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) && same(item.brand, profile.brand),
  },
  {
    name: 'subcategory_local',
    minimum: 3,
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) && same(item.state, profile.state),
  },
  {
    name: 'subcategory_malaysia',
    minimum: 3,
    match: (item, profile) => same(item.subcategory, profile.subcategory),
  },
  {
    name: 'category_local',
    minimum: 3,
    match: (item, profile) => same(item.state, profile.state),
  },
  { name: 'category_wide', minimum: 3, match: () => true },
];

export function evidenceRelevance(item, profile) {
  let score = 0;
  if (canonicalSame(item, profile)) score += 40;
  else if (sameProductText(item, profile)) score += 32;
  if (same(item.subcategory, profile.subcategory)) score += 20;
  if (same(item.brand, profile.brand)) score += 15;
  if (sameComparableFamily(item, profile)) score += 16;
  score += modelNeighbourhoodScore(item, profile);
  score += conditionSimilarity(item, profile);
  if (same(item.location, profile.location)) score += 10;
  else if (same(item.state, profile.state)) score += 6;
  const number = (value) => value == null || value === '' ? NaN : Number(value);
  const itemAge = number(item.itemAgeYears ?? item.item_age_years);
  const requestedAge = number(profile.item_age_years);
  if (Number.isFinite(itemAge) && Number.isFinite(requestedAge)) {
    score += Math.max(0, 5 - Math.abs(itemAge - requestedAge));
  }
  const itemDuration = number(
    item.rentalDurationDays ?? item.rental_duration_days,
  );
  const requestedDuration = number(profile.rental_duration_days);
  if (Number.isFinite(itemDuration) && Number.isFinite(requestedDuration)) {
    score += Math.max(0, 4 - Math.abs(itemDuration - requestedDuration));
  }
  const observedAt = item.observedAt ?? item.updatedAt;
  const timestamp = observedAt ? new Date(observedAt).getTime() : Number.NaN;
  if (Number.isFinite(timestamp)) {
    const cutoff = new Date(profile.observed_at ?? profile.evidence_as_of ?? Date.now()).getTime();
    const ageDays = Math.max(0, (cutoff - timestamp) / 86_400_000);
    score += Math.max(0, 4 - ageDays / 90);
  }
  return score;
}

export function selectComparableTier(items, profile, minimum) {
  items = items.filter((item) => compatibleProductReference(item, profile) && comparableDurationFits(item, profile))
    .map((item) => annotateComparable(item, profile));
  let last = { name: 'category_wide', items: [] };
  for (const level of hierarchy) {
    let matches = items
      .filter((item) => level.match(item, profile))
      .sort((left, right) =>
        Number(Boolean(left.durationBaseline)) - Number(Boolean(right.durationBaseline)) ||
        evidenceRelevance(right, profile) - evidenceRelevance(left, profile) ||
        String(left.publicId ?? left.observationKey ?? left.productModel ?? '').localeCompare(
          String(right.publicId ?? right.observationKey ?? right.productModel ?? '')));
    const quotedPeriod = matches.filter((row) => !row.durationBaseline);
    if (quotedPeriod.length >= (minimum ?? level.minimum)) matches = quotedPeriod;
    const selected = matches.slice(0, MAX_SELECTED_COMPARABLES);
    last = { name: level.name, items: selected,
      selection: comparableSelection(level.name, selected, matches.length, minimum ?? level.minimum, profile.rental_duration_days) };
    if (matches.length >= (minimum ?? level.minimum)) return last;
  }
  return last;
}

export function evidenceCounts(items, profile) {
  items = items.filter((item) => compatibleProductReference(item, profile) && comparableDurationFits(item, profile))
    .map((item) => annotateComparable(item, profile));
  const exact = items.filter((item) =>
    canonicalSame(item, profile) || sameProductText(item, profile));
  return {
    exact: exact.length,
    similar: Math.max(0, items.length - exact.length),
  };
}

export function pricingEvidenceDisclosure(evidence) {
  const levels = [];
  for (const [prefix, countKey, medianKey, exactKey] of [
    ['active', 'comparable_active_count', 'comparable_active_median', 'exact_active_count'],
    ['historical', 'historical_rental_count', 'historical_rental_median', 'exact_completed_rental_count'],
  ]) {
    const median = Number(evidence[medianKey]);
    if (!(Number(evidence[countKey]) > 0 && Number.isFinite(median) && median > 0)) continue;
    const tier = String(evidence[`${prefix}_comparable_tier`] ?? '');
    levels.push(tier.startsWith('exact_') || Number(evidence[exactKey]) > 0 ? 'product'
      : tier.includes('brand') ? 'brand' : tier.startsWith('subcategory') ? 'subcategory' : 'category');
  }
  const scope = ['product', 'brand', 'subcategory', 'category'].find((level) => levels.includes(level));
  return {
    pricing_scope: scope ? `${scope}_estimate` : 'insufficient_evidence',
    product_specific_evidence: scope === 'product',
    evidence_status: scope === 'product' ? 'product_specific' : scope ? 'broad' : 'insufficient',
  };
}

export function withComparablePresentation(result, activeTier, historicalTier) {
  const values = [...activeTier.items, ...historicalTier.items]
    .map((item) => item.dailyPrice).filter((price) => Number.isFinite(price) && price > 0);
  const summary = { active: activeTier.selection, historical: historicalTier.selection,
    observedRange: values.length ? { lower: Math.min(...values), upper: Math.max(...values) } : null,
    originalModelRange: Number.isFinite(result.lower_bound) && Number.isFinite(result.upper_bound)
      ? { lower: result.lower_bound, upper: result.upper_bound } : null,
    rangeIncludesComparables: false };
  const response = { ...result, comparison_summary: summary };
  if (result.available && !result.product_specific_evidence && values.length >= 1 &&
      Number.isFinite(result.lower_bound) && Number.isFinite(result.upper_bound)) {
    // An envelope, not a newly calibrated confidence interval. Never shrink the
    // model's uncertainty or change its predicted amount to fit the references.
    response.lower_bound = Math.min(result.lower_bound, ...values);
    response.upper_bound = Math.max(result.upper_bound, ...values);
    summary.rangeIncludesComparables = true;
    response.explanation = [...(Array.isArray(result.explanation) ? result.explanation : []),
      'Displayed bounds also include selected comparable observations; the original model interval is retained separately. This envelope has not been independently calibrated.'];
  }
  return response;
}

function quantile(sorted, position) {
  if (!sorted.length) return null;
  const index = (sorted.length - 1) * position;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}

export function robustPriceStats(values) {
  const sorted = values
    .map(Number)
    .filter((value) => Number.isFinite(value) && value > 0)
    .sort((left, right) => left - right);
  if (!sorted.length) {
    return { count: 0, mean: null, median: null, q1: null, q3: null, iqr: null, mad: null };
  }
  const median = quantile(sorted, 0.5);
  const deviations = sorted.map((value) => Math.abs(value - median)).sort((a, b) => a - b);
  const q1 = quantile(sorted, 0.25);
  const q3 = quantile(sorted, 0.75);
  return {
    count: sorted.length,
    mean: sorted.reduce((sum, value) => sum + value, 0) / sorted.length,
    median,
    q1,
    q3,
    iqr: q3 - q1,
    mad: quantile(deviations, 0.5),
  };
}

export function statisticalFallback(activeStats, historicalStats, category) {
  const preferred = historicalStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS
    ? historicalStats
    : activeStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS
      ? activeStats
      : null;
  if (!preferred || !validRentalPrice(preferred.median, category)) return null;
  const spread = preferred.iqr > 0
    ? preferred.iqr / 2
    : preferred.mad > 0
      ? preferred.mad * 1.4826
      : null;
  if (!spread) return null;
  return {
    suggested_daily_price: Math.round(preferred.median * 100) / 100,
    lower_bound: Math.round(Math.max(minimumRentalPrice(category), preferred.median - spread) * 100) / 100,
    upper_bound: Math.round((preferred.median + spread) * 100) / 100,
    source: historicalStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS
      ? 'completed_rental_median'
      : 'active_listing_median',
  };
}

export function statisticalFallbackConfidence(
  stats,
  freshnessDays,
  productMatchType = 'exact_catalog_match',
) {
  if (!stats || stats.count < PRICING_FALLBACK_MIN_OBSERVATIONS || !stats.median) {
    return { score: 0, label: 'low' };
  }
  const evidenceScore = Math.min(1, Math.log1p(stats.count) / Math.log1p(40));
  const parsedFreshness = Number(freshnessDays);
  const freshnessScore = Number.isFinite(parsedFreshness)
    ? Math.exp(-Math.max(0, parsedFreshness) / 180)
    : 0;
  const relativeSpread = (stats.iqr ?? 0) / Math.max(stats.median, 0.01);
  const consistencyScore = Math.max(0, 1 - Math.min(1, relativeSpread));
  const matchQuality = {
    exact_catalog_match: 1,
    fuzzy_catalog_match: 0.85,
    catalog_brand_match_model_manual: 0.65,
    manual_entry: 0.45,
  }[productMatchType] ?? 0.45;
  const score = Math.round(
    Math.min(0.7, 0.15 + 0.35 * evidenceScore + 0.2 * freshnessScore + 0.3 * consistencyScore)
      * (0.75 + 0.25 * matchQuality)
      * 10_000,
  ) / 10_000;
  return { score, label: score >= 0.5 ? 'medium' : 'low' };
}
