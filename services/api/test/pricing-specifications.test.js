import test from 'node:test';
import assert from 'node:assert/strict';
import { pricingSpecifications, compatiblePricingSpecifications } from '../src/modules/listing/pricingSpecifications.js';
import { compatibleProductReference } from '../src/modules/listing/priceProductDomains.js';
import { selectComparableTier } from '../src/modules/listing/pricingEvidence.js';
import { trainingComparableFeatures } from '../src/modules/listing/pricingTrainingExport.js';

const projector = (productModel, extra = {}) => ({ category: 'Equipment', subcategory: 'Event equipment',
  productModel, productType: 'projector', identityLevel: 'specification_only', ...extra });

test('projector brightness respects explicit value and measurement standard', () => {
  const target = projector('Projector 2200 ANSI lumens');
  for (const text of ['Projector 2700 ANSI lumens', 'Projector 3500 ANSI lumens', 'HD Projector',
    'Projector 2200 LED lumens', 'Projector 2200 ISO lumens', 'Projector 2200 lumens',
    'Projector 2000-2200 ANSI lumens', 'Projector 2200 or 2700 ANSI lumens', 'Projector 0 ANSI lumens',
    'Projector -2200 ANSI lumens']) {
    assert.equal(compatibleProductReference(projector(text), target), false, text);
    assert.equal(compatibleProductReference(target, projector(text)), false, text);
  }
  for (const text of ['Projector 2,200 ANSI lumens', 'Projector ２２００ ANSI lumens', 'Projector 2200 ansi lumen',
    'Projector 2200 ANSI-lumens']) {
    assert.equal(compatibleProductReference(projector(text), target), true, text);
  }
  // Broader type-only comparisons remain possible when neither side supplies specs.
  assert.equal(compatibleProductReference(projector('HD Projector'), projector('Portable Projector')), true);
});

test('specification conflicts cannot be overridden by catalogue IDs or reviewed classes', () => {
  const comparisonFacts = { reviewed: true, sourceUrl: 'https://example.test/spec', attributes: { kind: 'projector' } };
  assert.equal(compatibleProductReference(projector('2200 ANSI lumens', { canonicalProductId: 'same', comparisonFacts }),
    projector('3500 ANSI lumens', { canonicalProductId: 'same', comparisonFacts })), false);
});

test('specification-only projectors cannot contaminate counts or median through broad fallback', () => {
  const target = { ...projector('Projector 2200 ANSI lumens'), rental_duration_days: 1, state: 'Selangor' };
  const offers = ['HD Projector', 'Projector 2700 ANSI lumens', 'Projector 3500 ANSI lumens'].map((name) =>
    projector(name, { dailyPrice: 75, state: 'Selangor', rentalDurationDays: 1 }));
  assert.equal(selectComparableTier(offers, target).items.length, 0);
  const matching = [100, 110, 120].map((dailyPrice, i) => projector('2,200 ANSI lumens', {
    publicId: `offer-${i}`, dailyPrice, state: 'Selangor', rentalDurationDays: 1 }));
  assert.deepEqual(selectComparableTier([...offers, ...matching], target).items.map(x => x.dailyPrice).sort((a,b)=>a-b),
    [100,110,120]);
});

test('offline history reconstruction uses the same specification constraints', () => {
  const row = { category: 'Equipment', subcategory: 'Event equipment', product_type: 'projector',
    product_model: 'Projector 2200 ANSI lumens', group_id: 'target', observed_at: '2026-11-03',
    rental_duration_days: 1 };
  const history = ['HD Projector', 'Projector 2700 ANSI lumens', 'Projector 3500 ANSI lumens'].map((name, i) => ({
    ...row, group_id: `history-${i}`, product_model: name, source_type: 'external_asking_price',
    target_source: 'external_asking_price', observed_at: '2026-11-01', available_at: '2026-11-01',
    daily_price: 75, quoted_rental_days: 1, duration_min_days: 1, duration_max_days: 1, rate_basis: 'daily_rate' }));
  const features = trainingComparableFeatures(row, history);
  assert.equal(features.comparable_active_count, 0);
  assert.equal(features.comparable_active_median, null);
  assert.equal(features.historical_rental_count, 0);
  const completed = history.map(x => ({ ...x, target_source: 'completed_rental', source_type: 'real', independent_evidence: true }));
  assert.equal(trainingComparableFeatures(row, completed).historical_rental_count, 0);
});

test('display size, RAM, storage, tent capacity and drill voltage constrain types independently', () => {
  for (const [kind, a, b, equal] of [
    ['monitor', '24 inch monitor', '27 inch monitor', false],
    ['monitor', '24" monitor', '24 inches monitor', true],
    ['monitor', '24-inch monitor', '24 inches monitor', true],
    ['monitor', '24 inch monitor', 'monitor', false],
    ['laptop', '16 GB RAM laptop', '8 GB RAM laptop', false],
    ['laptop', 'RAM 16GB laptop', '16GB RAM laptop', true],
    ['laptop', '512GB SSD laptop', '1TB SSD laptop', false],
    ['camping_tent', 'Tent for 2 people', 'Tent 4-pax', false],
    ['camping_tent', 'Tent 2 person', 'Tent up to 2 pax', true],
    ['drill', '18V drill', '12 volt drill', false],
    ['drill', '18V drill', '18 volts drill', true],
    ['drill', '18-volt drill', '18 volts drill', true],
  ]) assert.equal(compatiblePricingSpecifications({ productModel: a }, { productModel: b }, kind), equal, `${a} / ${b}`);
  assert.deepEqual(pricingSpecifications({ productModel: 'Maker X 2026 model 123' }, 'monitor'), {});
  assert.equal(compatiblePricingSpecifications({ productModel: '16GB RAM laptop RAM 8GB' },
    { productModel: '8GB RAM laptop' }, 'laptop'), false);
});
