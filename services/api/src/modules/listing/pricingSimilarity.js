import { priceText, referenceIdentityUncertain, referencePeriodMatches } from './priceProductDomains.js';
import { referencePeriodEligibility } from './pricingPeriods.js';
import { reviewedClassMatch } from './productComparisonFacts.js';

export const MAX_SELECTED_COMPARABLES = 12;
export const COMPARABLE_SELECTION_VERSION = 'renthub-comparables-v2';
const number = (value) => value == null || value === '' ? NaN : Number(value);
const model = (item) => item.productModel ?? item.product_model ?? '';

// A name-family is only a retrieval hint, never a claim of equal specifications,
// market value or exact identity. Keep Pro/Ultra/Lite etc. as distinct families.
export function comparableFamily(item) {
  if (item.category === 'Books') return '';
  const brand = priceText(item.brand);
  let name = priceText(model(item));
  if (brand && name.startsWith(brand + ' ')) name = name.slice(brand.length + 1);
  const tokens = name.replace(/\b(?:mark|mk)\s+(?:\d+|[ivx]+)\b/g, '')
    .split(' ').filter((token) => token && !/^\d+$|^[ivx]+$/.test(token))
    .map((token) => token.replace(/\d+/g, '#'));
  const meaningful = tokens.filter((token) => !/^(?:other|unknown|model|camera|phone|book|item|product|device)#?$/.test(token));
  return meaningful.length && meaningful.some((token) => /[a-z]{2}|[a-z]#/.test(token)) ? meaningful.join(' ') : '';
}

export function sameComparableFamily(item, profile) {
  const family = comparableFamily(profile);
  return Boolean(reviewedClassMatch(item, profile) && family && priceText(profile.brand) && priceText(item.brand) === priceText(profile.brand) &&
    comparableFamily(item) === family);
}

export function modelNeighbourhoodScore(item, profile) {
  if (!sameComparableFamily(item, profile)) return 0;
  // Numeric proximity is a bounded retrieval hint within a name family, not a
  // market-value adjustment or a claim that model numbering is comparable.
  const left = model(item).match(/\d+/g), right = model(profile).match(/\d+/g);
  return left?.length && right?.length ? 6 / (1 + Math.abs(Number(left[0]) - Number(right[0]))) : 0;
}

export function comparableDurationFits(item, profile) {
  const days = number(profile.rental_duration_days);
  if (!Number.isInteger(days) || days < 1) return true;
  if (item.sourceType === 'external_asking_price' || item.source_type === 'external_asking_price') {
    return referencePeriodEligibility(item, days).eligible;
  }
  if (item.durationMinDays != null || item.durationMaxDays != null) return referencePeriodMatches(item, days);
  // A realised multi-day average is not an advertised one-day rate. Ordinary
  // platform daily asking prices do not have a fixed rentalDurationDays.
  const fixed = number(item.rentalDurationDays ?? item.rental_duration_days);
  return !Number.isFinite(fixed) || fixed === days;
}

export function conditionSimilarity(item, profile) {
  const conditions = ['fair', 'good', 'very good', 'excellent', 'like new'];
  const left = conditions.indexOf(priceText(item.condition)), right = conditions.indexOf(priceText(profile.condition));
  return left >= 0 && right >= 0 ? Math.max(0, 8 - 2 * Math.abs(left - right)) : 0;
}

export function comparableSelection(name, selected, candidateCount, minimum, requestedRentalDays) {
  const exact = name.startsWith('exact_');
  return {
    version: COMPARABLE_SELECTION_VERSION,
    basis: !selected.length ? 'none' : exact ? 'exact_product'
      : name.endsWith('model_unconfirmed') ? 'matching_model_unconfirmed_details'
      : name.includes('family') ? 'same_brand_model_family'
        : name.includes('brand') ? 'same_brand_product_type' : 'same_product_type',
    candidateCount, selectedCount: selected.length, limit: MAX_SELECTED_COMPARABLES,
    minimumMet: selected.length >= minimum,
    missingConditionCount: selected.filter((row) => !row.condition).length,
    missingAgeCount: selected.filter((row) => !Number.isFinite(number(row.itemAgeYears ?? row.item_age_years))).length,
    uncertainIdentityCount: selected.filter((row) => row.identityMatchUncertain).length,
    durationBaselineCount: selected.filter((row) => row.durationBaseline).length,
    requestedRentalDays: requestedRentalDays ?? null,
  };
}

// Native/CSV references may not have been annotated by compatiblePriceReferences.
export function annotateComparable(item, profile) {
  return item.sourceType === 'external_asking_price' || item.source_type === 'external_asking_price'
    ? { ...item, durationBaseline: referencePeriodEligibility(item, profile.rental_duration_days ?? 1).baseline,
      identityMatchUncertain: Boolean(item.identityMatchUncertain || referenceIdentityUncertain(item, profile)) }
    : item;
}
