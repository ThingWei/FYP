import test from 'node:test';
import assert from 'node:assert/strict';
import { env } from '../src/config/env.js';
import { priceSource, PRICE_SOURCE_COVERAGE, isAllowedSourceUrl } from '../src/modules/listing/priceSources.registry.js';
import { parsePriceSource } from '../src/modules/listing/priceSource.parsers.js';
import { collectSourceQuotes, compatiblePriceReferences } from '../src/modules/listing/priceSync.service.js';
import { eligibleTrainingReference } from '../src/modules/listing/pricingTrainingExport.js';
import { evidenceCounts } from '../src/modules/listing/pricingEvidence.js';

// Hand-built minimal inspected Shopline structure. Monetary values are test
// inputs, not downloaded observations or rental-price rules.
const card = (title = 'Mobi Garden QR Tent - Black Coated', description = '210 x 180cm 2-3 person RM112.00') =>
  `<li class="advc-carousel-images-with-text__item"><div class="advc-carousel-images-with-text__item-title">${title}</div><div class="advc-carousel-images-with-text__item-description">${description}</div></li>`;
const section = (cards = card(), heading = 'Tents', period = 'Fee covers up to 4 days of usage') =>
  `<div class="advc-carousel-images-with-text"><div class="advc-carousel-images-with-text__head"><h2>${heading}</h2><p>${period}</p></div><ul>${cards}</ul></div>`;
const entry = priceSource('goritta');
const now = new Date('2026-10-24T00:00:00Z');
const fetcher = (html) => async (url) => url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : html;
async function approvedFixture(fn) {
  const previous = env.priceSyncApprovedSources;
  env.priceSyncApprovedSources = ['goritta'];
  try { return await fn(); } finally { env.priceSyncApprovedSources = previous; }
}

test('Goritta covers only the existing Sports domain with one allowlisted rental page and a written-permission gate', () => {
  assert.equal(entry.requiresWrittenPermission, true);
  assert.deepEqual(entry.domains, ['Sports equipment']);
  assert.equal(PRICE_SOURCE_COVERAGE.length, 22);
  assert.ok(PRICE_SOURCE_COVERAGE.find((r) => r.subcategory === 'Sports equipment').sourceIds.includes('goritta'));
  assert.ok(isAllowedSourceUrl(entry, entry.urls[0]));
  for (const url of ['https://goritta.com/products/tent', 'https://other.test/rental', entry.urls[0] + '?all=true']) {
    assert.equal(isAllowedSourceUrl(entry, url), false);
  }
});

test('offline parser keeps named tent identities and specifications without inventing brands, prices or catalogue IDs', () => {
  const result = parsePriceSource(entry, section(card() + card('DoD One Pole Tent', '6-8 person RM168') +
    card('KZM Tier Dome GT', '3-4 person RM196') + card('Mobi Garden Holiday Retreat 5.9 - Black Coated', '2-4 person RM140')));
  assert.deepEqual(result.rows.map((r) => r.brand), ['Mobi Garden', 'DOD', 'KZM', 'Mobi Garden']);
  assert.deepEqual(result.rows.map((r) => r.quotedAmount), [112, 168, 196, 140]);
  assert.equal(result.rows[0].productModel, 'QR Tent - Black Coated');
  for (const row of result.rows) {
    assert.equal(row.productType, 'camping_tent');
    assert.equal(row.identityLevel, 'named_product');
    assert.equal(row.rentalDurationDays, 4);
    assert.equal(row.durationMinDays, 4);
    assert.equal(row.durationMaxDays, 4);
    assert.ok(row.packageNotes.includes('2-3 person') || row.packageNotes.includes('person'));
    assert.ok(row.packageNotes.includes('Pickup/return'));
    assert.equal(row.canonicalProductId, undefined);
    assert.equal(row.itemAgeYears, undefined);
    assert.equal(row.condition, undefined);
  }
  assert.deepEqual(result.links, []);
});

test('periods are section-local, not guessed from dimensions, runtime, another section or a global headline', () => {
  for (const html of [section(card(), 'Tents', ''), section(card(), 'Tents', 'Fee covers up to 3 days of usage'),
    section(card(), 'Chairs'), section(card(), 'Tents', '') + section(card(), 'Lights'),
    '<p>Four-day rentals</p>' + card(), section(card().replace('RM112.00', '112'))]) {
    assert.equal(parsePriceSource(entry, html).rows.length, 0);
  }
});

test('maintenance, unrelated items, mixed charges, ambiguous quotes and changed markup fail closed', () => {
  for (const [title, description] of [
    ['(Under Maintenance)', '2-4 person RM112'], ['Mobi Garden Tent', 'Unavailable RM112'],
    ['Mobi Garden Tent', 'Sold out RM112'], ['Mobi Garden Chair', 'RM112'],
    ['EcoFlow Power Station', 'RM112'], ['Generic Unknown Tent', 'RM112'],
    ['Mobi Garden Tent', 'From RM112'], ['Mobi Garden Tent', 'USD112'],
    ['Mobi Garden Tent', 'SGD112 RM112'], ['Mobi Garden Tent', 'Retail RM112'],
    ['Mobi Garden Tent', 'RM112 plus deposit RM50'], ['Mobi Garden Tent', 'RM112-RM140'],
    ['Mobi Garden Tent', 'RM112.001'], ['Mobi Garden Tent', 'Setup included RM112'],
    ['Mobi Garden Tent', 'RM112/day'], ['Mobi Garden Tent', 'Delivery included RM112'],
  ]) {
    assert.equal(parsePriceSource(entry, section(card(title, description))).rows.length, 0, title + description);
  }
  assert.equal(parsePriceSource(entry, section(card()).replace('__item-title', '__new-title')).rows.length, 0);
  assert.equal(parsePriceSource(entry, section(card() + card('Mobi Garden SC Chair', 'RM10'), 'Chairs')).rows.length, 0);
});

test('unapproved collection makes zero HTTP calls, even with a custom diagnostic fetcher', async () => {
  const previous = env.priceSyncApprovedSources;
  env.priceSyncApprovedSources = [];
  let requests = 0;
  try {
    await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => { requests++; return section(); } }),
      { code: 'PRICE_SOURCE_REVIEW_REQUIRED' });
    assert.equal(requests, 0);
  } finally { env.priceSyncApprovedSources = previous; }
});

test('permitted fixtures normalize and deduplicate without manufacturing a one-day rental rate or completed history', async () => {
  await approvedFixture(async () => {
    const collected = await collectSourceQuotes(entry, { fetchText: fetcher(section(card() + card())), now });
    assert.equal(collected.rows.length, 1);
    const row = collected.rows[0];
    assert.equal(row.quotedAmount, 112);
    assert.equal(row.dailyPrice, 28);
    assert.equal(row.rentalDurationDays, 4);
    assert.equal(row.canonicalProductId, null);
    assert.equal(row.reviewedBy, undefined);
    assert.equal(row.sourceType, 'external_asking_price');
    assert.equal(eligibleTrainingReference({ ...row, active: true }, ['goritta'], now), true);
    const profile = { category: 'Equipment', subcategory: 'Sports equipment', brand: row.brand,
      product_model: row.productModel, rental_duration_days: 4 };
    assert.equal(compatiblePriceReferences([row], profile, ['goritta']).length, 1);
    assert.equal(compatiblePriceReferences([row], { ...profile, rental_duration_days: 1 }, ['goritta']).length, 0);
    assert.equal(compatiblePriceReferences([row], { ...profile, product_model: 'Badminton racket' }, ['goritta']).length, 0);
    assert.equal(compatiblePriceReferences([row], profile, []).length, 0);
    assert.equal(evidenceCounts([row], profile).exact, 1);
    const conflict = await collectSourceQuotes(entry, { fetchText: fetcher(section(card() + card(undefined, 'RM120'))), now });
    assert.equal(conflict.rows.length, 0);
    assert.ok(conflict.skipped.includes('conflicting_quotes'));
    await assert.rejects(collectSourceQuotes(entry, { fetchText: async (url) =>
      url.endsWith('/robots.txt') ? 'User-agent: *\nDisallow: /' : section() }), /ACCESS_RESTRICTED/);
  });
});
