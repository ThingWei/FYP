import { PRICE_SOURCE_COVERAGE } from './priceSources.registry.js';
import { PRICE_PRODUCT_DOMAINS, priceText, productTypeFor, referenceOfferKey } from './priceProductDomains.js';
import { eligibleTrainingReference } from './pricingTrainingExport.js';
import { PRICING_EVIDENCE_WINDOW_DAYS } from './pricingEvidence.js';

export const PRICE_COVERAGE_SCAN_LIMIT = 10000;

// Read-only diagnostic counts, not proof of rights, independent businesses,
// exact-model coverage or validated numerical accuracy. No prices are generated.
export function buildPriceCoverage(references, enabledSourceIds, { now = new Date(), truncated = false } = {}) {
  const rows = PRICE_SOURCE_COVERAGE.map((domain) => {
    const supported = PRICE_PRODUCT_DOMAINS.find((row) => row.category === domain.category && row.subcategory === domain.subcategory);
    const raw = references.filter((row) => row.category === domain.category && row.subcategory === domain.subcategory);
    const valid = raw.filter((row) => eligibleTrainingReference(row, enabledSourceIds, now));
    const quoteKey = (row) => JSON.stringify([referenceOfferKey(row),
      row.durationMinDays ?? row.rentalDurationDays, row.durationMaxDays ?? row.rentalDurationDays, +new Date(row.observedAt)]);
    const quotes = new Map(), conflicts = new Set();
    for (const row of valid) {
      const key = quoteKey(row);
      if (quotes.has(key) && quotes.get(key) !== row.dailyPrice) conflicts.add(key);
      quotes.set(key, row.dailyPrice);
    }
    const eligible = valid.filter((row) => !conflicts.has(quoteKey(row)));
    const typed = eligible.filter((row) => productTypeFor(row.category, row.subcategory, `${row.brand ?? ''} ${row.productModel}`));
    const offers = new Set(typed.map(referenceOfferKey));
    const websites = new Set(typed.map((row) => new URL(row.sourceUrl).hostname.replace(/^www\./, '')));
    const productGroups = new Set(typed.map((row) => JSON.stringify([row.canonicalProductId || '',
      priceText(row.brand), priceText(row.productModel), row.isbn || '', priceText(row.edition), priceText(row.variant)])));
    const countBy = (key, values) => Object.fromEntries([...new Set(values)].sort().map((value) => [value,
      typed.filter((row) => (row[key] || 'unspecified') === value).length]));
    return { ...domain, productTypes: supported.productTypes, requiredIdentity: supported.requiredIdentity,
      referenceStatus: !typed.length ? 'no_eligible_references' : offers.size >= 3 && websites.size >= 2
        ? 'multiple_reference_offers' : 'limited_reference_offers',
      accuracyStatus: 'not_established_by_coverage_counts',
      storedObservations: raw.length, eligibleObservations: typed.length,
      unclassifiedObservations: eligible.length - typed.length, excludedObservations: raw.length - eligible.length,
      conflictingObservations: valid.length - eligible.length,
      uniqueOfferCount: offers.size, sourceWebsiteCount: websites.size, productGroupCount: productGroups.size,
      namedProductObservations: typed.filter((row) => row.identityLevel !== 'specification_only').length,
      specificationOnlyObservations: typed.filter((row) => row.identityLevel === 'specification_only').length,
      withCondition: typed.filter((row) => row.condition).length, withItemAge: typed.filter((row) => row.itemAgeYears != null).length,
      stateCounts: countBy('state', typed.map((row) => row.state || 'unspecified')),
      productTypeCounts: Object.fromEntries(supported.productTypes.map((type) => [type,
        typed.filter((row) => productTypeFor(row.category, row.subcategory, `${row.brand ?? ''} ${row.productModel}`) === type).length])),
      rentalPeriods: [...new Set(typed.map((row) => `${row.durationMinDays ?? row.rentalDurationDays}-${row.durationMaxDays ?? row.rentalDurationDays}`))].sort(),
      freshestObservationAt: typed.length ? new Date(Math.max(...typed.map((row) => +new Date(row.observedAt)))).toISOString() : null,
    };
  });
  return { schemaVersion: 'renthub-price-coverage-v1', generatedAt: now.toISOString(), evidenceWindowDays: PRICING_EVIDENCE_WINDOW_DAYS,
    truncated, scannedObservations: references.length, scanLimit: PRICE_COVERAGE_SCAN_LIMIT,
    categoriesWithReferences: rows.filter((row) => row.eligibleObservations > 0).length, totalSubcategories: rows.length,
    limitations: ['Asking-price references only; completed rentals and demo history are not counted.',
      'Website counts do not establish independent businesses or data-reuse permission.',
      'Three offers from two websites is a diagnostic grouping, not an accuracy or release threshold.',
      'A populated subcategory does not establish coverage of each product, region or rental period.',
      'Supported daily equivalents start at RM0.01 for Books and RM1 for other categories; missing observations are not fabricated.'], rows };
}
