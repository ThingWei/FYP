// Reviewed product specifications only. No rental prices or value/price tiers.
const canon = (model, sensorFormat, inBodyStabilization) => Object.freeze({
  category: 'Devices', subcategory: 'Cameras', brand: 'Canon', model,
  reviewed: true, reviewedDate: '2026-10-28',
  sourceUrl: `https://asia.canon/en/consumer/${model.toLowerCase().replaceAll(' ', '-')}/body/specification`,
  attributes: Object.freeze({ bodyType: 'mirrorless', sensorFormat, inBodyStabilization }),
});
export const REVIEWED_COMPARISON_FACTS = Object.freeze([
  canon('EOS R50', 'aps_c', false), canon('EOS R10', 'aps_c', false),
  canon('EOS R7', 'aps_c', true), canon('EOS R6 Mark II', 'full_frame', true),
]);
const key = (v) => String(v ?? '').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const model = (item) => item.productModel ?? item.product_model ?? item.model ?? '';
export function samePricingIdentity(a, b) {
  return a.category === b.category && a.subcategory === b.subcategory && Boolean(key(a.brand)) &&
    key(a.brand) === key(b.brand) && Boolean(key(model(a))) && key(model(a)) === key(model(b));
}
export function reviewedComparisonFacts(item) {
  const saved = REVIEWED_COMPARISON_FACTS.find((row) => samePricingIdentity(row, item));
  if (saved) return saved;
  const facts = item.comparisonFacts ?? item.comparison_facts;
  if (facts?.reviewed !== true || !facts.attributes || typeof facts.attributes !== 'object' || Array.isArray(facts.attributes)) return null;
  try { const url = new URL(facts.sourceUrl); if (url.protocol !== 'https:' || url.username || url.password) return null; }
  catch { return null; }
  const attributes = Object.fromEntries(Object.entries(facts.attributes).filter(([name, value]) =>
    /^[a-zA-Z][a-zA-Z0-9_]{0,49}$/.test(name) &&
    (typeof value === 'boolean' || typeof value === 'string' && value.length > 0 && value.length <= 80 || typeof value === 'number' && Number.isFinite(value))));
  return Object.keys(attributes).length ? { reviewed: true, sourceUrl: facts.sourceUrl, attributes } : null;
}

export function reviewedClassMatch(a, b) {
  const left = reviewedComparisonFacts(a), right = reviewedComparisonFacts(b);
  if (!left || !right) return false;
  const keys = [...new Set([...Object.keys(left.attributes), ...Object.keys(right.attributes)])];
  return keys.length > 0 && keys.every((name) => left.attributes[name] !== undefined && right.attributes[name] !== undefined &&
    key(left.attributes[name]) === key(right.attributes[name]));
}

// A known class cannot be priced from an unknown/conflicting class. Cameras are
// heterogeneous even within one brand; cross-model comparisons require facts.
// Other domains retain explicitly broad type-only fallback when BOTH classes
// are unknown. Providers can supply the same reviewed contract in any domain.
export function suitableProductComparison(a, b) {
  if (samePricingIdentity(a, b)) return true;
  const left = reviewedComparisonFacts(a), right = reviewedComparisonFacts(b);
  if (left || right) return reviewedClassMatch(a, b);
  return b.subcategory !== 'Cameras';
}
