import test from 'node:test';
import assert from 'node:assert/strict';
import { PRICE_SOURCE_COVERAGE, priceSource, isAllowedSourceUrl } from '../src/modules/listing/priceSources.registry.js';
import { parsePriceSource } from '../src/modules/listing/priceSource.parsers.js';
import { collectSourceQuotes, compatiblePriceReferences } from '../src/modules/listing/priceSync.service.js';
import { eligibleTrainingReference } from '../src/modules/listing/pricingTrainingExport.js';

const removed = ['irent', 'rentsmart', '12rent', 'goritta', 'avm'];
for (const id of removed) {
  test(`removed source ${id} has no registration, parser, collection or clean evidence`, async () => {
    assert.equal(priceSource(id), undefined);
    assert.ok(PRICE_SOURCE_COVERAGE.every((domain) => !domain.sourceIds.includes(id)));
    assert.equal(isAllowedSourceUrl(priceSource(id), 'https://example.test/'), false);
    const entry = { id, adapter: id, urls: ['https://example.test/'] };
    assert.deepEqual(parsePriceSource(entry, '<p>Laptop RM50/day</p>').rows, []);
    let requests = 0;
    await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => { requests++; return ''; } }), { code: 'PRICE_SOURCE_NOT_FOUND' });
    assert.equal(requests, 0);
    const now = new Date('2026-10-27');
    const row = { active: true, collectionMethod: 'automatic', sourceId: id, sourceType: 'external_asking_price',
      category: 'Devices', subcategory: 'Computers', brand: 'Test maker', productModel: 'Laptop', productType: 'laptop',
      quotedAmount: 50, dailyPrice: 50, rentalDurationDays: 1, durationMinDays: 1, durationMaxDays: 1,
      country: 'MY', currency: 'MYR', sourceName: 'Removed fixture', sourceUrl: 'https://example.test/laptop',
      observedAt: now, validatedAt: now, validationStatus: 'accepted' };
    assert.equal(eligibleTrainingReference(row, removed, now), false);
    assert.equal(compatiblePriceReferences([row], { ...row, product_model: 'Laptop', rental_duration_days: 1 }, removed).length, 0);
  });
}
