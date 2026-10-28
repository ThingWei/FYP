import test from 'node:test';
import assert from 'node:assert/strict';
import { nextPriceProvenance, listingEvidenceReason, bookingEvidenceReason, pricingSnapshot } from '../src/modules/listing/priceProvenance.js';
import { buildPricingTrainingExport, trainingComparableFeatures } from '../src/modules/listing/pricingTrainingExport.js';
import { selectComparableTier, evidenceRelevance } from '../src/modules/listing/pricingEvidence.js';
import { reviewedPrice, reviewedBooking, realPayment } from './helpers/pricingEvidence.js';
import { reviewPreview } from '../src/scripts/auditPricingRealWorld.js';
const item = (extra = {}) => ({ publicId: 'test-item', listingType: 'physical', sourceType: 'marketplace',
  category: 'Devices', subcategory: 'Computers', brand: 'Test maker', productModel: 'Computer mouse',
  dailyPrice: 25, status: 'active', updatedAt: new Date(), ...extra });

test('unknown and AI-derived prices cannot become independent through declaration or edits', () => {
  const legacy = item();
  assert.equal(listingEvidenceReason(legacy), 'unknown_price_origin');
  const applied = nextPriceProvenance({ dailyPrice: 25, priceProvenance: { origin: 'ai_suggested', suggestedAmount: 25 } }, legacy);
  const listing = { ...legacy, priceProvenance: applied };
  assert.equal(listingEvidenceReason(listing), 'ai_derived');
  assert.equal(nextPriceProvenance({ title: 'Another title' }, listing).origin, 'ai_suggested');
  assert.equal(nextPriceProvenance({ dailyPrice: 30, priceProvenance: { origin: 'owner_entered' } }, listing).origin, 'ai_edited');
  assert.equal(nextPriceProvenance({ dailyPrice: 30, priceProvenance: { origin: 'owner_entered', independence: 'reviewed' } }, listing).independence, 'unverified');
  assert.equal(legacy.priceProvenance, undefined);
});

test('external-derived draft edits cannot erase their originating offer', () => {
  const listing = item({ priceProvenance: { origin: 'external_reference', independence: 'unverified', originatingOfferKey: 'fixture-offer' } });
  const declaration = nextPriceProvenance({ dailyPrice: 30, priceProvenance: { origin: 'owner_entered' } }, listing);
  assert.equal(declaration.origin, 'external_reference');
  assert.equal(declaration.originatingOfferKey, 'fixture-offer');
  assert.equal(listingEvidenceReason({ ...listing, priceProvenance: declaration }), 'derived_external_copy');
  const suggestion = nextPriceProvenance({ priceProvenance: { origin: 'ai_suggested', suggestedAmount: 45 } }, listing);
  assert.equal(suggestion.origin, 'ai_suggested');
  assert.equal(suggestion.originatingOfferKey, 'fixture-offer');
});

test('review binds to the saved price and item context and is cleared by relevant edits', () => {
  const listing = reviewedPrice(item());
  assert.equal(listingEvidenceReason(listing), null);
  assert.equal(nextPriceProvenance({ description: 'Another description' }, listing).independence, 'reviewed');
  for (const change of [{ dailyPrice: 30 }, { productModel: 'Laptop' }, { condition: 'Fair' }]) {
    assert.equal(nextPriceProvenance(change, listing).independence, 'unverified');
    assert.equal(listingEvidenceReason({ ...listing, ...change }), 'unverified_owner_price');
  }
  assert.equal(listingEvidenceReason({ ...listing, sourceType: 'demo_seed' }), 'demonstration');
  assert.equal(listingEvidenceReason({ ...listing, priceProvenance: { origin: 'external_reference' } }), 'derived_external_copy');
});

test('real completed evidence requires an immutable independent profile and nonsimulated successful payment', () => {
  const listing = reviewedPrice(item());
  const booking = reviewedBooking({ publicId: 'booking', listingId: listing.publicId, sourceType: 'marketplace',
    status: 'completed', pricing: { baseAmount: 25 } }, listing);
  const payment = realPayment(booking);
  assert.equal(bookingEvidenceReason(booking, [payment]), null);
  assert.equal(bookingEvidenceReason(booking, [{ ...payment, simulated: true }]), 'simulated_payment');
  assert.equal(bookingEvidenceReason(booking, []), 'unverified_payment');
  assert.equal(bookingEvidenceReason(booking, [{ ...payment, amount: 1 }]), 'unverified_payment');
  assert.equal(bookingEvidenceReason(booking, [{ ...payment, currency: 'USD' }]), 'unverified_payment');
  assert.equal(bookingEvidenceReason({ ...booking, pricingEvidenceSnapshot: undefined }, [payment]), 'missing_historical_snapshot');
  assert.equal(bookingEvidenceReason({ ...booking, sourceType: 'demo_seed' }, [payment]), 'demonstration');
  listing.productModel = 'Changed listing';
  assert.equal(booking.pricingEvidenceSnapshot.productModel, 'Computer mouse');
  assert.equal(bookingEvidenceReason(booking, [payment]), null);
});

test('contaminated prices never enter clean training rows or influence compatible evidence', () => {
  const clean = reviewedPrice(item());
  const bad = [item({ publicId: 'unknown' }), { ...clean, publicId: 'ai', priceProvenance: { origin: 'ai_suggested' } },
    { ...clean, publicId: 'demo', sourceType: 'demo_seed' }];
  const result = buildPricingTrainingExport({ listings: [clean, ...bad] });
  assert.equal(result.rows.length, 1);
  assert.equal(result.summary.excludedPlatform.unknown_price_origin, 1);
  assert.equal(result.summary.excludedPlatform.ai_derived, 1);
  assert.equal(result.summary.excludedPlatform.demonstration, 1);
  const profile = { ...item(), product_model: 'Computer mouse', productType: 'mouse' };
  const candidates = [item(), item({ productModel: 'Laptop' }), item({ productModel: 'Computer monitor' }),
    item({ productModel: 'Game controller', subcategory: 'Gaming' })];
  assert.equal(selectComparableTier(candidates, profile).items.length, 1);
});

test('missing age is not treated as age zero and an offer cannot supply its own target features', () => {
  const profile = { ...item(), item_age_years: 0 };
  // Isolate age from wall-clock freshness; consecutive Date.now() calls can differ.
  assert.equal(evidenceRelevance(item({ itemAgeYears: null, updatedAt: undefined }), profile),
    evidenceRelevance(item({ itemAgeYears: undefined, updatedAt: undefined }), profile));
  const row = { ...item(), product_model: 'Computer mouse', rental_duration_days: 1,
    group_id: 'target', observed_at: '2026-10-20', origin_offer_key: 'shared-offer' };
  const history = [{ ...row, group_id: 'different-group', observed_at: '2026-10-01', available_at: '2026-10-02',
    source_type: 'external_asking_price', target_source: 'external_asking_price', daily_price: 25 }];
  assert.equal(trainingComparableFeatures(row, history).comparable_active_count, 0);
});

test('preview does not infer reuse approval from configured sources or fake missing fields', () => {
  const now = new Date('2026-10-27');
  const reference = { publicId: 'ref', observationKey: 'ref', sourceType: 'external_asking_price', active: true,
    currency: 'MYR', country: 'MY', category: 'Devices', subcategory: 'Computers', brand: 'Test maker', productModel: 'Laptop',
    quotedAmount: 100, rentalDurationDays: 1, dailyPrice: 100, sourceName: 'Fixture', sourceUrl: 'https://example.com/laptop',
    observedAt: '2026-10-01', reviewedAt: '2026-10-02', reviewedBy: 'test-reviewer', sourceId: 'fixture' };
  assert.equal(reviewPreview([reference], ['fixture'], [], now).rows.length, 0);
  assert.equal(reviewPreview([reference], ['fixture'], [{ sourceId: 'fixture', status: 'approved' }], now).rows.length, 0);
  const r = reviewPreview([reference, reference], ['fixture'], [{ sourceId: 'fixture', status: 'approved',
    checkedAt: '2026-10-02', reviewedBy: 'fixture-only-reviewer', evidenceReference: 'fixture-only-permission' }], now);
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].itemAgeYears, null);
  assert.equal(r.rows[0].condition, null);
  assert.equal(r.databaseWrites, 0);
});
