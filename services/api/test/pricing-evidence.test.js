import test from 'node:test';
import assert from 'node:assert/strict';
import {
  robustPriceStats,
  selectComparableTier,
  statisticalFallback,
  statisticalFallbackConfidence,
} from '../src/modules/listing/pricingEvidence.js';

const profile = {
  category: 'Devices', subcategory: 'Cameras', brand: 'Sony',
  product_model: 'A7 III', state: 'Kuala Lumpur', condition: 'Excellent',
};

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
  assert.equal(selected.name, 'exact_product_local');
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
