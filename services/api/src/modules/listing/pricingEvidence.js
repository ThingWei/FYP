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
  return Boolean(profile.canonicalProductId) &&
    item.canonicalProductId === profile.canonicalProductId;
}

function sameProductText(item, profile) {
  return same(item.subcategory, profile.subcategory) &&
    same(item.brand, profile.brand) &&
    same(item.productModel, profile.product_model);
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
  if (same(item.condition, profile.condition)) score += 8;
  if (same(item.location, profile.location)) score += 10;
  else if (same(item.state, profile.state)) score += 6;
  const itemAge = Number(item.itemAgeYears ?? item.item_age_years);
  const requestedAge = Number(profile.item_age_years);
  if (Number.isFinite(itemAge) && Number.isFinite(requestedAge)) {
    score += Math.max(0, 5 - Math.abs(itemAge - requestedAge));
  }
  const itemDuration = Number(
    item.rentalDurationDays ?? item.rental_duration_days,
  );
  const requestedDuration = Number(profile.rental_duration_days);
  if (Number.isFinite(itemDuration) && Number.isFinite(requestedDuration)) {
    score += Math.max(0, 4 - Math.abs(itemDuration - requestedDuration));
  }
  const observedAt = item.observedAt ?? item.updatedAt;
  const timestamp = observedAt ? new Date(observedAt).getTime() : Number.NaN;
  if (Number.isFinite(timestamp)) {
    const ageDays = Math.max(0, (Date.now() - timestamp) / 86_400_000);
    score += Math.max(0, 4 - ageDays / 90);
  }
  return score;
}

export function selectComparableTier(items, profile, minimum) {
  let last = { name: 'category_wide', items: [] };
  for (const level of hierarchy) {
    const matches = items
      .filter((item) => level.match(item, profile))
      .sort((left, right) =>
        evidenceRelevance(right, profile) - evidenceRelevance(left, profile));
    last = { name: level.name, items: matches };
    if (matches.length >= (minimum ?? level.minimum)) return last;
  }
  return last;
}

export function evidenceCounts(items, profile) {
  const exact = items.filter((item) =>
    canonicalSame(item, profile) || sameProductText(item, profile));
  return {
    exact: exact.length,
    similar: Math.max(0, items.length - exact.length),
  };
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

export function statisticalFallback(activeStats, historicalStats) {
  const preferred = historicalStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS
    ? historicalStats
    : activeStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS
      ? activeStats
      : null;
  if (!preferred) return null;
  const spread = preferred.iqr > 0
    ? preferred.iqr / 2
    : preferred.mad > 0
      ? preferred.mad * 1.4826
      : null;
  if (!spread) return null;
  return {
    suggested_daily_price: Math.round(preferred.median * 100) / 100,
    lower_bound: Math.round(Math.max(1, preferred.median - spread) * 100) / 100,
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
  const relativeSpread = (stats.iqr ?? 0) / Math.max(stats.median, 1);
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
