import test from 'node:test';
import assert from 'node:assert/strict';
import { summarizePricingEvidence, main } from '../src/scripts/auditPricingEvidence.js';

// Controlled fixtures only. They are never inserted as marketplace observations.
const now = new Date('2026-10-27T12:00:00Z');
const profile = { category: 'Devices', subcategory: 'Computers', brand: 'Test brand',
  product_model: 'Wireless mouse', rental_duration_days: 1 };
const row = (extra = {}) => ({ ...profile, source_type: 'real', price_origin: 'owner_entered',
  independent_evidence: true, payment_simulated: false, observed_at: '2026-10-01',
  available_at: '2026-10-02', daily_price: 10, target_source: 'completed_rental', ...extra });
const payload = (rows) => ({ rows, summary: { excludedPlatform: { simulated_payment: 2 } } });

test('product audit excludes contaminated historical prices despite legacy real labels', () => {
  const result = summarizePricingEvidence(payload([row(), row({ source_type: 'demo_seed' }),
    row({ price_origin: 'ai_suggested' }), row({ price_origin: 'ai_edited' }),
    row({ price_origin: 'unknown' }), row({ independent_evidence: false }),
    row({ payment_simulated: true }), row({ observed_at: '2025-01-01' }),
    row({ available_at: '2027-01-01' }), row({ daily_price: NaN })]), profile, now);
  assert.equal(result.eligibleCompletedMarketplace, 1);
  assert.equal(result.historical.selectedCount, 1);
  assert.equal(result.historical.selectedMedian, 10);
  assert.equal(result.eligibleCompletedDemoSeed, 0);
  assert.equal(result.demoSeedIncludedByConfiguration, false);
  assert.equal(result.excludedPlatform.simulated_payment, 2);
  assert.equal(result.databaseWrites, 0);
});

test('product audit preserves types, duration bands and the asking/achieved distinction', () => {
  const source = payload([row({ target_source: 'active_asking' }),
    row({ product_model: 'Mechanical keyboard' }), row({ category: 'Equipment' }),
    row({ source_type: 'external_asking_price', price_origin: 'external_reference',
      target_source: 'external_asking_price', rental_duration_days: 14, daily_price: 1 }),
    row({ source_type: 'external_asking_price', price_origin: 'external_reference',
      target_source: 'external_asking_price', available_at: null, rental_duration_days: 1, daily_price: 1 }),
    row({ source_type: 'external_asking_price', price_origin: 'external_reference',
      target_source: 'external_asking_price', rental_duration_days: 1, daily_price: 9 })]);
  const before = structuredClone(source);
  const result = summarizePricingEvidence(source, profile, now);
  assert.equal(result.historical.selectedCount, 0);
  assert.equal(result.active.selectedCount, 1);
  assert.equal(result.externalAsking.selectedCount, 1);
  assert.equal(result.externalAsking.selectedMedian, 9);
  assert.equal(result.externalAsking.selectedMarketplaceCount, 0);
  assert.deepEqual(source, before);
});

test('product audit rejects incomplete arguments before opening any connection', async () => {
  await assert.rejects(main([]), /Usage/);
  await assert.rejects(main(['Devices', 'Computers', '', 'Mouse']), /Usage/);
});
