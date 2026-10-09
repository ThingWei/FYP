import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evidenceCounts,
  pricingEvidenceDisclosure,
  evidenceRelevance,
  robustPriceStats,
  selectComparableTier,
  statisticalFallback,
  statisticalFallbackConfidence,
} from '../src/modules/listing/pricingEvidence.js';

const profile = {
  category: 'Devices', subcategory: 'Cameras', brand: 'Sony',
  product_model: 'A7 III', state: 'Kuala Lumpur', condition: 'Excellent',
};

test('pricing disclosures distinguish exact, brand, subcategory and category evidence', () => {
  for (const [tier, scope] of [
    ['exact_product_malaysia', 'product_estimate'],
    ['subcategory_brand_malaysia', 'brand_estimate'],
    ['subcategory_local', 'subcategory_estimate'],
    ['category_wide', 'category_estimate'],
  ]) {
    const result = pricingEvidenceDisclosure({comparable_active_count: 3,
      comparable_active_median: 70, active_comparable_tier: tier});
    assert.equal(result.pricing_scope, scope);
    assert.equal(result.product_specific_evidence, scope === 'product_estimate');
  }
});

test('counts or catalog identity alone cannot support a precise product price', () => {
  for (const evidence of [{}, {comparable_active_count: 3}, {exact_active_count: 1},
    {comparable_active_count: 3, comparable_active_median: Infinity}]) {
    const result = pricingEvidenceDisclosure(evidence);
    assert.equal(result.evidence_status, 'insufficient');
    assert.equal(result.product_specific_evidence, false);
  }
});

test('uses the narrowest comparable tier with enough evidence', () => {
  const exact = Array.from({ length: 3 }, (_, index) => ({
    subcategory: 'Cameras', brand: 'Sony', productModel: 'A7 III',
    state: 'Kuala Lumpur', condition: 'Excellent', dailyPrice: 80 + index,
  }));
  const wider = [{
    subcategory: 'Cameras', brand: 'Canon', productModel: 'R6',
    state: 'Kuala Lumpur', condition: 'Good', dailyPrice: 70,
  }];
  const selected = selectComparableTier([...exact, ...wider], profile);
  assert.equal(selected.name, 'exact_product_malaysia');
  assert.equal(selected.items.length, 3);
});

test('calculates median, quartiles and MAD without hand-authored prices', () => {
  const stats = robustPriceStats([60, 80, 100, 120]);
  assert.equal(stats.count, 4);
  assert.equal(stats.median, 90);
  assert.equal(stats.q1, 75);
  assert.equal(stats.q3, 105);
  assert.equal(stats.iqr, 30);
  assert.equal(stats.mad, 20);
});

test('returns unavailable instead of fabricating a sparse fallback', () => {
  const sparse = robustPriceStats([80, 90]);
  const empty = robustPriceStats([]);
  assert.equal(statisticalFallback(sparse, empty), null);
});

test('derives fallback confidence from evidence volume, freshness and spread', () => {
  const small = robustPriceStats([60, 80, 100]);
  const consistent = robustPriceStats(Array.from({ length: 20 }, (_, index) => 88 + index % 5));
  const smallConfidence = statisticalFallbackConfidence(small, 120);
  const strongConfidence = statisticalFallbackConfidence(consistent, 1);
  assert.ok(strongConfidence.score > smallConfidence.score);
  assert.equal(strongConfidence.label, 'medium');
});

test('prefers an exact canonical product across Malaysia over local broad matches', () => {
  const canonicalProfile = {
    ...profile,
    canonicalProductId: 'wikidata:Q-talon-2',
    location: 'Kuala Lumpur',
  };
  const items = [
    {
      canonicalProductId: 'wikidata:Q-talon-2',
      subcategory: 'Bicycles',
      brand: 'Giant',
      productModel: 'Talon 2',
      state: 'Johor',
      location: 'Johor Bahru',
      condition: 'Excellent',
      dailyPrice: 70,
    },
    {
      subcategory: 'Cameras',
      brand: 'Canon',
      productModel: 'R6',
      state: 'Kuala Lumpur',
      location: 'Kuala Lumpur',
      condition: 'Excellent',
      dailyPrice: 90,
    },
  ];
  const selected = selectComparableTier(items, canonicalProfile);
  assert.equal(selected.name, 'exact_canonical_malaysia');
  assert.equal(selected.items[0].dailyPrice, 70);
  assert.deepEqual(evidenceCounts(items, canonicalProfile), { exact: 1, similar: 1 });
});

test('progressively falls back through brand, subcategory and category evidence', () => {
  const brandMatches = [1, 2].map((index) => ({
    subcategory: 'Cameras',
    brand: 'Sony',
    productModel: `Other ${index}`,
    state: 'Johor',
    condition: 'Good',
  }));
  assert.equal(
    selectComparableTier(brandMatches, profile).name,
    'subcategory_brand_malaysia',
  );

  const subcategoryMatches = [1, 2, 3].map((index) => ({
    subcategory: 'Cameras',
    brand: `Maker ${index}`,
    productModel: `Camera ${index}`,
    state: 'Johor',
  }));
  assert.equal(
    selectComparableTier(subcategoryMatches, profile).name,
    'subcategory_malaysia',
  );

  const broadMatches = [1, 2, 3].map((index) => ({
    subcategory: 'Audio',
    brand: `Maker ${index}`,
    productModel: `Speaker ${index}`,
    state: 'Johor',
  }));
  assert.equal(selectComparableTier(broadMatches, profile).name, 'category_wide');
});

test('completed-rental hierarchy separates exact, brand, subcategory and broad tiers', () => {
  const exact = [{
    canonicalProductId: 'catalog:camera-a7',
    subcategory: 'Cameras', brand: 'Sony', productModel: 'A7 III', state: 'Johor',
  }];
  assert.equal(selectComparableTier(exact, {
    ...profile, canonicalProductId: 'catalog:camera-a7',
  }).name, 'exact_canonical_malaysia');

  const sameBrand = [1, 2].map((index) => ({
    subcategory: 'Cameras', brand: 'Sony', productModel: `A7 sibling ${index}`,
    state: 'Johor', condition: 'Good',
  }));
  assert.equal(selectComparableTier(sameBrand, profile).name,
    'subcategory_brand_malaysia');

  const sameSubcategory = [1, 2, 3].map((index) => ({
    subcategory: 'Cameras', brand: `Brand ${index}`, state: 'Johor',
  }));
  assert.equal(selectComparableTier(sameSubcategory, profile).name,
    'subcategory_malaysia');

  const broad = [1, 2, 3].map((index) => ({
    subcategory: 'Audio', brand: `Brand ${index}`, state: 'Johor',
  }));
  assert.equal(selectComparableTier(broad, profile).name, 'category_wide');
});

test('condition, age, duration and recency improve evidence relevance without price rules', () => {
  const close = {
    subcategory: 'Cameras', brand: 'Sony', productModel: 'Other',
    state: 'Kuala Lumpur', condition: 'Excellent', itemAgeYears: 2,
    rentalDurationDays: 3, observedAt: new Date(),
  };
  const distant = {
    ...close,
    condition: 'Fair',
    itemAgeYears: 9,
    rentalDurationDays: 14,
    observedAt: new Date('2020-01-01T00:00:00Z'),
  };
  const ageProfile = { ...profile, item_age_years: 2, rental_duration_days: 3 };
  assert.ok(evidenceRelevance(close, ageProfile) > evidenceRelevance(distant, ageProfile));
});

test('manual product identity reduces statistical fallback confidence', () => {
  const stats = robustPriceStats([80, 85, 90, 95, 100]);
  const exact = statisticalFallbackConfidence(stats, 1, 'exact_catalog_match');
  const manual = statisticalFallbackConfidence(stats, 1, 'manual_entry');
  assert.ok(manual.score < exact.score);
});
