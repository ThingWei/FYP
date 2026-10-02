import test from 'node:test';
import assert from 'node:assert/strict';
import { externalMarketComparables } from '../src/modules/listing/marketPriceComparables.js';

const iphone13 = {
  category: 'Devices',
  subcategory: 'Smartphones',
  brand: 'Apple',
  product_model: 'iPhone 13 Pro 256GB',
  condition: 'Good',
  item_age_years: 0,
};

test('matches an exact short-term Malaysian product comparable', () => {
  const result = externalMarketComparables(iphone13, 1);
  assert.equal(result.count, 1);
  assert.equal(result.adjustedAverage, 100);
  assert.equal(result.sources[0].dailyPrice, 100);
  assert.match(result.sources[0].sourceUrl, /^https:\/\//);
});

test('adjusts the daily average for condition, age and duration', () => {
  const result = externalMarketComparables(
    { ...iphone13, condition: 'Excellent', item_age_years: 2 },
    3,
  );
  assert.equal(result.count, 1);
  assert.ok(result.adjustedAverage > 100);
  assert.ok(result.adjustedAverage < 110);
});

test('does not treat a different product variant as an exact match', () => {
  const result = externalMarketComparables(
    { ...iphone13, product_model: 'iPhone 13 Pro Max 256GB' },
    1,
  );
  assert.equal(result.count, 0);
  assert.equal(result.adjustedAverage, null);
});

test('supports non-electronic products using lower-confidence resale evidence', () => {
  const result = externalMarketComparables(
    {
      category: 'Books',
      subcategory: 'Fiction',
      brand: 'Tolkien',
      product_model: 'Lord of the Ring book',
      condition: 'Good',
      item_age_years: 1,
    },
    1,
  );
  assert.equal(result.count, 2);
  assert.equal(result.directRentalCount, 0);
  assert.equal(result.resaleDerivedCount, 2);
  assert.ok(result.adjustedAverage > 4);
  assert.ok(result.adjustedAverage < 5);
  assert.equal(result.sources.every((item) => item.marketPrice === 50), true);
});
