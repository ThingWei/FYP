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

const hierarchy = [
  {
    name: 'exact_product_local',
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) &&
      same(item.brand, profile.brand) &&
      same(item.productModel, profile.product_model) &&
      same(item.state, profile.state) &&
      same(item.condition, profile.condition),
  },
  {
    name: 'subcategory_brand_local',
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) &&
      same(item.brand, profile.brand) &&
      same(item.state, profile.state),
  },
  {
    name: 'subcategory_local',
    match: (item, profile) =>
      same(item.subcategory, profile.subcategory) && same(item.state, profile.state),
  },
  {
    name: 'category_local',
    match: (item, profile) => same(item.state, profile.state),
  },
  { name: 'category_wide', match: () => true },
];

export function selectComparableTier(items, profile, minimum = 3) {
  let last = { name: 'category_wide', items: [] };
  for (const level of hierarchy) {
    const matches = items.filter((item) => level.match(item, profile));
    last = { name: level.name, items: matches };
    if (matches.length >= minimum) return last;
  }
  return last;
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

export function statisticalFallbackConfidence(stats, freshnessDays) {
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
  const score = Math.round(
    Math.min(0.7, 0.15 + 0.35 * evidenceScore + 0.2 * freshnessScore + 0.3 * consistencyScore)
      * 10_000,
  ) / 10_000;
  return { score, label: score >= 0.5 ? 'medium' : 'low' };
}
