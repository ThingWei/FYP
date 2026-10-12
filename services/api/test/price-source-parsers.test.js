import test from 'node:test';
import assert from 'node:assert/strict';
import { CATALOG_COVERAGE } from '../src/modules/catalog/catalog.coverage.js';
import { PRICE_SOURCES, PRICE_SOURCE_COVERAGE, FUTURE_PRICE_DOMAINS, priceSource, isAllowedSourceUrl } from '../src/modules/listing/priceSources.registry.js';
import { parsePriceSource, readHtml } from '../src/modules/listing/priceSource.parsers.js';
import { robotsAllows } from '../src/modules/listing/priceSource.transport.js';
import { collectSourceQuotes, compatiblePriceReferences } from '../src/modules/listing/priceSync.service.js';
import { evidenceCounts, selectComparableTier } from '../src/modules/listing/pricingEvidence.js';

// Minimal fixtures mirror inspected public markup; amounts are parser test inputs, not price rules.
export const SOURCE_FIXTURES = {
  rentism: '<p>Canon Body</p><p>EOS R50 (body only) RM 65/day</p><p>iPhone 15 RM 100/day</p><p>Boya microphone RM 30/day</p><p>Motorola Walkie Talkie RM 20/day</p><p>Godox SK400 lighting RM 40/day</p>',
  itpa: '<table class="rental-rate-table"><tr><td>Dell Latitude laptop</td><td>8GB RAM</td><td>RM 50 / unit / day</td></tr></table>',
  cilt: '<div><h3>PlayStation 5</h3><div><p>Daily</p><p>RM 45</p></div><div><p>3-Day</p><p>RM 120</p></div><div><p>Weekend</p><p>RM 90</p></div></div>',
  drivor: '<h5>Day based pricing : Private: Toyota Camry</h5><div class="day-ranges-pricing-plan">1 - 3 days : RM 280 / Day</div><div class="day-ranges-pricing-plan">4 - 7 days : RM 250 / Day</div>',
  alquiler: '### Honda ADV160 - MYR 55/day\nURL: https://alquilermotorbike.com/fleet/honda-adv160\n\n## Next section',
  ecocana: '<div class="product-layout"><h4>Giant Escape bicycle</h4><div class="description">Rent (Daily) - bike</div><span class="price-new">RM 80</span></div>',
  'rental-guy': '<div class="trg-catalogue-card"><h3 class="trg-product-heading">Projector 4000 lumens</h3><span class="trg-reference-price">One-day reference: RM 180</span><p class="trg-product-description">HDMI projector only.</p></div>',
  'pc-rent': '<table><tr><td>Daily</td><td>RM 180 4000 ANSI Lumens</td></tr></table>',
  jomrent: '<h4>Rent Cordless Drill Only</h4><h4>RM10/24 Hours</h4><h4>Pressure Washer (120 bar)</h4><h4>RM69/24 Hours</h4>',
  partymix: ['Brown Blazer', 'Jedi Costume', 'Hanfu Traditional Costume'].map((label) => `<li class="product"><h2 class="woocommerce-loop-product__title">${label} [Rental for 4 Days]</h2><span class="price"><span class="woocommerce-Price-amount">RM 40.00</span>plus deposit of <span class="woocommerce-Price-amount">RM 100.00</span><span class="wceb-price-format"> / 4 days</span></span></li>`).join(''),
  futago: '<li>01 Winter clothing RM 150 10 days / item</li>',
};
const fixtureFetcher = (content) => async (url) => url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : content;

for (const coverage of CATALOG_COVERAGE) {
  test(`coverage: ${coverage.category} / ${coverage.subcategory}`, () => {
    const entry = PRICE_SOURCE_COVERAGE.find((row) => row.category === coverage.category && row.subcategory === coverage.subcategory);
    assert.ok(entry?.fallback);
    assert.ok(entry.sourceIds.every((id) => priceSource(id)?.domains.includes(entry.subcategory)));
    if (coverage.category === 'Books') assert.equal(entry.sourceIds.length, 0);
    const implemented = entry.sourceIds.filter((id) => SOURCE_FIXTURES[id]);
    if (implemented.length) assert.ok(implemented.some((id) => parsePriceSource(priceSource(id), SOURCE_FIXTURES[id]).rows.some((row) => row.category === entry.category && row.subcategory === entry.subcategory)));
  });
}
test('exactly 22 current domains; toys documented but not silently enabled', () => {
  assert.equal(PRICE_SOURCE_COVERAGE.length, 22);
  assert.equal(FUTURE_PRICE_DOMAINS.length, 3);
  assert.ok(!PRICE_SOURCE_COVERAGE.some((row) => /toy/i.test(row.category)));
  assert.equal(priceSource('avm').adapter, null);
});

for (const [id, content] of Object.entries(SOURCE_FIXTURES)) {
  test(`parser and normalized provenance: ${id}`, async () => {
    const result = await collectSourceQuotes(priceSource(id), { fetchText: fixtureFetcher(content) });
    assert.ok(result.rows.length > 0, JSON.stringify(result.skipped));
    for (const row of result.rows) {
      assert.equal(row.sourceType, 'external_asking_price');
      assert.equal(row.collectionMethod, 'automatic');
      assert.equal(row.currency, 'MYR');
      assert.equal(row.validationStatus, 'accepted');
      assert.equal(row.reviewedBy, undefined);
      assert.equal(row.canonicalProductId, null);
      assert.ok(Number.isFinite(row.dailyPrice));
      assert.ok(PRICE_SOURCE_COVERAGE.some((domain) => domain.category === row.category && domain.subcategory === row.subcategory && domain.sourceIds.includes(id)));
    }
  });
}
test('pending adapters and empty/changed markup fail closed', () => {
  for (const entry of PRICE_SOURCES.filter((source) => !source.adapter)) assert.deepEqual(parsePriceSource(entry, '<p>RM 40/day</p>').rows, []);
  assert.equal(parsePriceSource(priceSource('rentism'), '<p>Changed layout</p>').rows.length, 0);
});
test('reject from prices, retail consumables, non-camera Canon products, ambiguous periods and bundles', () => {
  const rentism = '<p>Canon flash RM 90/day</p><p>Canon EOS R50 from RM 50/day</p><p>Canon EOS R50 + lens RM 50/day</p><p>iPhone 15 RM 100</p><p>iPhone 15 USD 100/day</p>';
  assert.equal(parsePriceSource(priceSource('rentism'), rentism).rows.length, 0);
  const jomrent = '<h4>Cordless Drill(rent) + Brush(sell)</h4><h4>RM15/24 Hours</h4><h4>Detergent</h4><h4>RM7/tablet</h4>';
  assert.equal(parsePriceSource(priceSource('jomrent'), jomrent).rows.length, 0);
  assert.equal(parsePriceSource(priceSource('cilt'), SOURCE_FIXTURES.cilt).rows.length, 2);
  assert.equal(parsePriceSource(priceSource('drivor'), SOURCE_FIXTURES.drivor.replace('Camry', 'Hiace Van')).rows.length, 0);
});
test('garment fee excludes the deposit, keeps four-day package, rejects ranges and mismatched periods', () => {
  const row = parsePriceSource(priceSource('partymix'), SOURCE_FIXTURES.partymix).rows[0];
  assert.equal(row.quotedAmount, 40);
  assert.equal(row.rentalDurationDays, 4);
  assert.equal(row.brand, '');
  assert.equal(row.identityLevel, 'specification_only');
  assert.equal(parsePriceSource(priceSource('partymix'), SOURCE_FIXTURES.partymix.replaceAll('RM 40.00', 'RM 40.00 – RM 70.00')).rows.length, 0);
  assert.equal(parsePriceSource(priceSource('partymix'), SOURCE_FIXTURES.partymix.replaceAll('/ 4 days', '/ 1 day')).rows.length, 0);
});
test('duration bands are not falsely advertised as one-day quotes or counted repeatedly', async () => {
  const { rows } = await collectSourceQuotes(priceSource('drivor'), { fetchText: fixtureFetcher(SOURCE_FIXTURES.drivor) });
  assert.deepEqual(rows.map((row) => [row.quotedAmount, row.rentalDurationDays, row.dailyPrice]), [[280, 1, 280], [1000, 4, 250]]);
  assert.equal(rows[0].sourceProductKey, rows[1].sourceProductKey);
  assert.notEqual(rows[0].observationKey, rows[1].observationKey);
  const profile = { category: 'Vehicles', subcategory: 'Cars', brand: 'Toyota', product_model: 'Camry', rental_duration_days: 5 };
  assert.equal(compatiblePriceReferences(rows, profile, ['drivor'])[0].dailyPrice, 250);
  assert.equal(compatiblePriceReferences(rows, { ...profile, rental_duration_days: 8 }, ['drivor']).length, 0);
  assert.equal(compatiblePriceReferences(rows, profile, []).length, 0);
});
test('conflicting same-product quotes are quarantined, exact duplicate refreshes deduplicate', async () => {
  const duplicate = SOURCE_FIXTURES.rentism + SOURCE_FIXTURES.rentism;
  const original = await collectSourceQuotes(priceSource('rentism'), { fetchText: fixtureFetcher(SOURCE_FIXTURES.rentism) });
  const repeated = await collectSourceQuotes(priceSource('rentism'), { fetchText: fixtureFetcher(duplicate) });
  assert.equal(original.rows.length, repeated.rows.length);
  const conflict = await collectSourceQuotes(priceSource('rentism'), { fetchText: fixtureFetcher('<p>iPhone 15 RM 100/day</p><p>iPhone 15 RM 90/day</p>') });
  assert.equal(conflict.rows.length, 0);
  assert.ok(conflict.skipped.includes('conflicting_quotes'));
});
test('unbranded specification references never count as exact or same-brand evidence', async () => {
  const { rows } = await collectSourceQuotes(priceSource('rental-guy'), { fetchText: fixtureFetcher(SOURCE_FIXTURES['rental-guy']) });
  const profile = { category: 'Equipment', subcategory: 'Event equipment', brand: 'Epson', product_model: 'Projector 4000 lumens', canonicalProductId: 'fake', rental_duration_days: 1 };
  rows[0].canonicalProductId = 'fake'; // Defence against incorrectly populated legacy metadata.
  const compatible = compatiblePriceReferences(rows, profile, ['rental-guy']);
  assert.equal(evidenceCounts(compatible, profile).exact, 0);
  assert.equal(selectComparableTier(compatible, profile).name, 'category_wide');
  assert.equal(compatiblePriceReferences(rows, { ...profile, product_model: 'PA System' }, ['rental-guy']).length, 0);
  assert.equal(compatiblePriceReferences(rows, { ...profile, subcategory: 'Tools' }, ['rental-guy']).length, 0);
});
test('access restrictions, bounded HTML and URL allowlist have no bypass', async () => {
  const entry = priceSource('drivor');
  for (const url of ['http://drivor.my/vehicle/a/', 'https://evil.test/vehicle/a/', 'https://drivor.my/vehicle/a/?x=1', 'https://drivor.my/login', 'https://user@drivor.my/vehicle/a/']) assert.equal(isAllowedSourceUrl(entry, url), false);
  assert.equal(isAllowedSourceUrl(entry, 'https://drivor.my/vehicle/honda-city/'), true);
  assert.equal(robotsAllows('User-agent: *\nDisallow: /vehicle/', entry.urls[0]), false);
  assert.equal(robotsAllows('User-agent: *\nDisallow: /\nAllow: /vehicle/', entry.urls[0]), true);
  assert.equal(robotsAllows('User-agent: RentHubPriceSync\nDisallow: /\nUser-agent: *\nAllow: /', entry.urls[0]), false);
  assert.equal(robotsAllows('User-agent: *\nContent-signal: ai-input=no', entry.urls[0]), false);
  await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => 'User-agent: *\nDisallow: /' }), /ACCESS_RESTRICTED/);
  assert.throws(() => readHtml('x'.repeat(2_097_153)), /PAGE_TOO_LARGE/);
});
test('zero/over-limit money, over-limit periods and excessive decimal precision are rejected', async () => {
  for (const content of ['<p>iPhone 15 RM 0/day</p>', '<p>iPhone 15 RM 1000001/day</p>', '<p>iPhone 15 RM 1000/366 days</p>', '<p>iPhone 15 RM 10.999/day</p>']) {
    const result = await collectSourceQuotes(priceSource('rentism'), { fetchText: fixtureFetcher(content) });
    assert.equal(result.rows.length, 0);
  }
});

for (const status of [404, 410]) {
  test(`missing robots HTTP ${status} permits an allowlisted price-page probe, not arbitrary URLs`, async () => {
    const requests = [], entry = priceSource('pc-rent');
    const result = await collectSourceQuotes(entry, { fetchText: async (url) => {
      requests.push(url);
      if (url.endsWith('/robots.txt')) throw Object.assign(new Error(`HTTP_${status}`), { status });
      return SOURCE_FIXTURES['pc-rent'];
    } });
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].identityLevel, 'specification_only');
    assert.equal(result.rows[0].brand, '');
    assert.deepEqual(requests, [new URL('/robots.txt', entry.urls[0]).href, ...entry.urls]);
  });
}

test('missing robots does not bypass denials, rate limits, redirects, failures or price-page errors', async () => {
  const entry = priceSource('pc-rent');
  for (const status of [301, 401, 403, 429, 500, 503]) {
    let requests = 0;
    await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => {
      requests++; throw Object.assign(new Error(`HTTP_${status}`), { status });
    } }), { status });
    assert.equal(requests, 1); // No price-page request when robots access fails.
  }
  for (const policy of ['<html>Access challenge</html>', 'User-agent: *\nDisallow: /']) {
    await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => policy }), /ACCESS_RESTRICTED/);
  }
  await assert.rejects(collectSourceQuotes(entry, { fetchText: async () => { throw new Error('timeout'); } }), /timeout/);
  await assert.rejects(collectSourceQuotes(entry, { fetchText: async (url) => {
    throw Object.assign(new Error(url.endsWith('/robots.txt') ? 'HTTP_404' : 'HTTP_503'),
      { status: url.endsWith('/robots.txt') ? 404 : 503 });
  } }), { status: 503 });
});
test('inseparable service charges cannot become equipment-only evidence', async () => {
  const content = SOURCE_FIXTURES['rental-guy'].replace('HDMI projector only.', 'Projector with operator included.');
  const result = await collectSourceQuotes(priceSource('rental-guy'), { fetchText: fixtureFetcher(content) });
  assert.equal(result.rows.length, 0);
  assert.ok(result.skipped.includes('ambiguous_or_service_quote'));
});
test('discovery stays bounded to allowlisted vehicle pages without arbitrary or asset fetching', async () => {
  const links = Array.from({ length: 50 }, (_, index) => `<a href="https://drivor.my/vehicle/car-${index}/">Vehicle</a>`).join('');
  const requests = [];
  const fetchText = async (url) => {
    requests.push(url);
    return url.endsWith('/robots.txt') ? 'User-agent: *\nAllow: /' : SOURCE_FIXTURES.drivor + links + '<a href="https://evil.test/vehicle/secret/">No</a><script><p>iPhone 15 RM 100/day</p></script><img src="https://evil.test/a.png">';
  };
  const result = await collectSourceQuotes(priceSource('drivor'), { fetchText });
  assert.equal(result.pages, 20);
  assert.equal(requests.length, 21); // 20 pages plus robots, never linked assets.
  assert.ok(requests.every((url) => url.startsWith('https://drivor.my/')));
  assert.equal(result.rows.length, 2);
});
