import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCampingResearchPreview } from '../src/modules/listing/priceSource.parsers.js';
import { PRICE_SOURCES } from '../src/modules/listing/priceSources.registry.js';
test('camping research accepts explicit single-item periods without becoming a live source', () => {
  // Invented parser fixture prices, not market observations or demo listings.
  const result = parseCampingResearchPreview('<h2>One-day references before tax</h2>' +
    '<h3>Single room camping tent</h3><p>Details</p><p>One-day reference: RM777</p>' +
    '<h3>Camping tent bundle</h3><p>One-day reference: RM888</p>' +
    '<h3>Camping chair</h3><p>One-day reference: RM999</p>' +
    '<h3>Another tent</h3><p>From RM20</p><h3>Third tent</h3><p>RM30</p>');
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].rentalDurationDays, 1);
  assert.equal(result.rows[0].identityLevel, 'specification_only');
  assert.equal(result.rows[0].brand, '');
  assert.equal(result.enabled, false);
  assert.equal(result.reusePermissionEstablished, false);
  assert.equal(PRICE_SOURCES.find((s) => s.id === 'rental-guy').urls.some((url) => url.includes('camping')), false);
});
