import test from 'node:test';
import assert from 'node:assert/strict';
import { PRICE_PRODUCT_DOMAINS, compatibleProductReference, normalizeIsbn, productTypeFor } from '../src/modules/listing/priceProductDomains.js';
import { compatiblePriceReferences } from '../src/modules/listing/priceSync.service.js';
import { buildPriceCoverage } from '../src/modules/listing/priceCoverage.js';
import { trainingComparableFeatures, eligibleTrainingReference } from '../src/modules/listing/pricingTrainingExport.js';
import { evidenceCounts, robustPriceStats, statisticalFallback, statisticalFallbackConfidence } from '../src/modules/listing/pricingEvidence.js';

test('book daily equivalents below RM1 survive reporting/evaluation; no RM1 uplift or inflated consistency', () => {
  const book = reference({ category: 'Books', subcategory: 'Fiction', brand: 'Author', productModel: 'Title',
    quotedAmount: 5, rentalDurationDays: 14, dailyPrice: 5 / 14 });
  assert.equal(eligibleTrainingReference(book, [], now), true);
  const report = buildPriceCoverage([book], [], { now });
  assert.equal(report.rows.find((r) => r.subcategory === 'Fiction').eligibleObservations, 1);
  assert.equal(eligibleTrainingReference({ ...book, category: 'Devices', subcategory: 'Cameras' }, [], now), false);
  assert.equal(eligibleTrainingReference({ ...book, dailyPrice: 0.005, quotedAmount: 0.07 }, [], now), false);
  const stats = robustPriceStats([0.2, 0.35, 0.5]);
  const result = statisticalFallback(stats, { count: 0 }, 'Books');
  assert.equal(result.suggested_daily_price, 0.35);
  assert.ok(result.lower_bound >= 0.01 && result.lower_bound < result.suggested_daily_price);
  assert.ok(result.upper_bound > result.suggested_daily_price);
  assert.equal(statisticalFallback(stats, { count: 0 }, 'Devices'), null);
  const floor = statisticalFallback(robustPriceStats([0.01, 0.01, 0.1]), { count: 0 }, 'Books');
  assert.equal(floor.lower_bound, 0.01);
  assert.equal(statisticalFallbackConfidence(stats, 0).score,
    statisticalFallbackConfidence({ ...stats, median: stats.median * 100, iqr: stats.iqr * 100 }, 0).score);
});

const cases = [
  ['Devices', 'Smartphones', 'Samsung', 'Galaxy S24', 'smartphone'],
  ['Devices', 'Cameras', 'Canon', 'EOS R50', 'camera'],
  ['Devices', 'Computers', 'Dell', 'XPS 13', 'laptop'],
  ['Devices', 'Audio', 'JBL', 'Charge 5', 'speaker'],
  ['Devices', 'Gaming', 'Sony', 'DualSense controller', 'controller'],
  ['Devices', 'Other devices', 'Garmin', 'Forerunner 265', 'smartwatch'],
  ['Vehicles', 'Cars', 'Toyota', 'Camry', 'car'],
  ['Vehicles', 'Motorcycles', 'Honda', 'ADV160', 'motorcycle'],
  ['Vehicles', 'Bicycles', 'Giant', 'Talon 2', 'bicycle'],
  ['Vehicles', 'Other vehicles', 'Segway', 'Ninebot Max G2', 'electric_scooter'],
  ['Equipment', 'Event equipment', 'Yamaha', 'MG10XU', 'audio_mixer'],
  ['Equipment', 'Tools', 'Makita', 'DHP484 drill', 'drill'],
  ['Equipment', 'Sports equipment', 'Generic', 'Four-person camping tent', 'camping_tent'],
  ['Equipment', 'Other equipment', 'Karcher', 'WD 3', 'vacuum'],
  ['Books', 'Textbooks', 'James Stewart', 'Calculus', 'book'],
  ['Books', 'Reference books', 'DK', 'Knowledge Encyclopedia', 'book'],
  ['Books', 'Fiction', 'J. R. R. Tolkien', 'The Hobbit', 'book'],
  ['Books', 'Other books', 'Lonely Planet', 'Malaysia', 'book'],
  ['Clothing', 'Formal wear', 'Generic', 'Blazer', 'formal_jacket'],
  ['Clothing', 'Costumes', 'Generic', 'Jedi costume', 'costume'],
  ['Clothing', 'Traditional wear', 'Generic', 'Baju Kurung', 'malay_traditional'],
  ['Clothing', 'Other clothing', 'Columbia', 'Powder Lite jacket', 'winter_garment'],
];
const now = new Date('2026-10-23T00:00:00Z');
const reference = (patch = {}) => ({ category: 'Devices', subcategory: 'Cameras', brand: 'Canon', productModel: 'EOS R50',
  sourceType: 'external_asking_price', sourceName: 'Test reference', sourceUrl: 'https://example.test/rental/camera',
  active: true, currency: 'MYR', country: 'MY', collectionMethod: 'manual_csv', reviewedBy: 'PRIVATE-REVIEWER',
  reviewedAt: now, observedAt: now, rentalDurationDays: 1, quotedAmount: 100, dailyPrice: 100, ...patch });
const profile = (row) => ({ ...row, product_model: row.productModel, rental_duration_days: 1 });

for (const [category, subcategory, brand, productModel, type] of cases) {
  test(`price domain and compatible reviewed reference: ${category} / ${subcategory}`, () => {
    const row = reference({ category, subcategory, brand, productModel });
    assert.equal(productTypeFor(category, subcategory, `${brand} ${productModel}`), type);
    assert.equal(compatiblePriceReferences([row], profile(row), []).length, 1);
    const report = buildPriceCoverage([row], [], { now });
    assert.equal(report.rows.length, 22);
    assert.equal(report.rows.find((r) => r.category === category && r.subcategory === subcategory).eligibleObservations, 1);
  });
}

test('every domain has a semantic strategy; invalid category pairs and unknown mixed-domain types fail closed', () => {
  assert.equal(PRICE_PRODUCT_DOMAINS.length, 22);
  assert.ok(PRICE_PRODUCT_DOMAINS.every((row) => row.productTypes.length && row.requiredIdentity.length));
  assert.equal(productTypeFor('Books', 'Cars', 'Toyota Camry'), null);
  assert.equal(productTypeFor('Toys', 'Gaming', 'Nintendo Switch'), null);
  assert.equal(productTypeFor('Equipment', 'Sports equipment', 'Unknown item'), null);
  assert.equal(productTypeFor('Vehicles', 'Other vehicles', 'Mobility scooter'), 'mobility_scooter');
});

test('CSV and automatic quotes cannot mix lenses, bodies, kits, controller/console or storage variants', () => {
  const camera = reference(), target = profile(camera);
  for (const collectionMethod of ['manual_csv', 'automatic']) {
    const extras = { collectionMethod, sourceId: 'rentism', sourceProductKey: 'lens', productType: 'camera_lens',
      validationStatus: 'accepted', validatedAt: now, durationMinDays: 1, durationMaxDays: 7 };
    assert.equal(compatiblePriceReferences([reference({ ...extras, productModel: 'RF lens 35mm' })], target, ['rentism']).length, 0);
  }
  assert.equal(compatibleProductReference(reference({ packageNotes: 'Camera with lens' }), target), false);
  assert.equal(compatibleProductReference(reference({ packageType: 'with_lens' }), { ...target, packageType: 'with_lens' }), true);
  assert.equal(compatibleProductReference(reference({ packageNotes: 'Body only' }), target), true);
  const unknownPackage = compatiblePriceReferences([reference({ packageNotes: 'Body only' })], target, []);
  assert.equal(evidenceCounts(unknownPackage, target).exact, 0);
  const phone = reference({ subcategory: 'Smartphones', brand: 'Apple', productModel: 'iPhone 15 128GB' });
  assert.equal(compatibleProductReference(phone, { ...profile(phone), product_model: 'iPhone 15 256GB', productModel: undefined }), false);
  assert.equal(compatibleProductReference(phone, { ...profile(phone), variant: '128 GB' }), true);
  const controller = reference({ subcategory: 'Gaming', brand: 'Sony', productModel: 'DualSense controller' });
  assert.equal(compatibleProductReference(controller, { category: 'Devices', subcategory: 'Gaming', brand: 'Sony', product_model: 'PlayStation 5' }), false);
});

test('books require title/author or validated ISBN, edition conflicts cannot be hidden by a catalogue ID', () => {
  const book = reference({ category: 'Books', subcategory: 'Textbooks', brand: 'Author', productModel: 'Calculus', edition: '2nd edition' });
  const target = { ...profile(book), edition: '2' };
  assert.equal(compatibleProductReference(book, target), true);
  assert.equal(compatibleProductReference(book, { category: 'Books', subcategory: 'Textbooks', brand: 'Author', product_model: 'Calculus 2nd edition' }), true);
  assert.equal(compatibleProductReference(book, { ...target, product_model: 'Different title', productModel: undefined }), false);
  assert.equal(compatibleProductReference(book, { ...target, edition: '3' }), false);
  assert.equal(compatibleProductReference(book, { ...target, subcategory: 'Fiction' }), false);
  const isbnBook = { ...book, isbn: '0-306-40615-2' };
  assert.equal(normalizeIsbn(isbnBook.isbn), '9780306406157');
  assert.equal(normalizeIsbn('9780306406158'), null);
  assert.equal(compatibleProductReference(isbnBook, { ...target, isbn: '978-0-306-40615-7' }), true);
  assert.equal(compatibleProductReference(isbnBook, target), false);
  assert.equal(compatibleProductReference({ ...book, canonicalProductId: 'same' }, { ...target, canonicalProductId: 'same', edition: '3' }), false);
  assert.equal(compatibleProductReference({ ...book, brand: '作者 王' }, { ...target, brand: '作者 王' }), true);
});

test('explicit periods, latest refreshes, tracking URLs and conflicting offers cannot inflate comparisons', () => {
  const row = reference();
  assert.equal(compatiblePriceReferences([reference({ rentalDurationDays: 7, quotedAmount: 700 })], profile(row), []).length, 0);
  const old = reference({ observedAt: new Date('2026-10-22'), dailyPrice: 80, quotedAmount: 80 });
  const tracked = reference({ sourceUrl: `${row.sourceUrl}?utm_source=ad#section` });
  assert.equal(compatiblePriceReferences([old, row, tracked], profile(row), []).length, 1);
  assert.equal(compatiblePriceReferences([old, row], profile(row), [])[0].dailyPrice, 100);
  assert.equal(compatiblePriceReferences([row, reference({ dailyPrice: 90 })], profile(row), []).length, 0);
});

test('coverage separates stored, excluded, typed offers, websites, periods, locations and unknown quality', () => {
  const row = reference();
  const rows = [row, reference({ sourceUrl: `${row.sourceUrl}?utm_source=repeat` }),
    reference({ observedAt: new Date('2020-01-01') }), reference({ active: false }),
    reference({ collectionMethod: 'automatic', sourceId: 'disabled', validationStatus: 'accepted', validatedAt: now,
      productType: 'camera', durationMinDays: 1, durationMaxDays: 7 }),
    reference({ category: 'Equipment', subcategory: 'Sports equipment', productModel: 'Unknown equipment' })];
  const report = buildPriceCoverage(rows, [], { now, truncated: true });
  const camera = report.rows.find((row) => row.subcategory === 'Cameras');
  assert.equal(camera.storedObservations, 5);
  assert.equal(camera.eligibleObservations, 2);
  assert.equal(camera.uniqueOfferCount, 1);
  assert.equal(camera.sourceWebsiteCount, 1);
  assert.equal(camera.withItemAge, 0);
  assert.deepEqual(camera.rentalPeriods, ['1-1']);
  assert.equal(camera.stateCounts.unspecified, 2);
  assert.equal(camera.accuracyStatus, 'not_established_by_coverage_counts');
  assert.equal(report.rows.find((row) => row.subcategory === 'Sports equipment').unclassifiedObservations, 1);
  assert.equal(report.rows.find((row) => row.subcategory === 'Fiction').referenceStatus, 'no_eligible_references');
  assert.equal(report.truncated, true);
  assert.equal(JSON.stringify(report).includes('PRIVATE-REVIEWER'), false);
});

test('offline comparable preparation applies the same manual-reference semantic and period gates', () => {
  const target = { category: 'Devices', subcategory: 'Cameras', brand: 'Canon', product_model: 'EOS R50',
    group_id: 'target', observed_at: now.toISOString(), rental_duration_days: 1 };
  const history = ['RF lens 35mm', 'EOS R6'].map((product_model, index) => ({
    ...target, product_model, group_id: `history-${index}`, source_type: 'external_asking_price', target_source: 'external_asking_price',
    daily_price: 100, observed_at: '2026-10-20T00:00:00Z', available_at: '2026-10-21T00:00:00Z',
    collection_method: 'manual_csv', quoted_rental_days: index ? 7 : 1,
  }));
  assert.equal(trainingComparableFeatures(target, history).external_asking_price_count, 0);
});

test('conflicting normalized offers are not counted as eligible coverage', () => {
  const report = buildPriceCoverage([reference(), reference({ quotedAmount: 90, dailyPrice: 90,
    sourceUrl: 'https://example.test/rental/camera?utm_source=other' })], [], { now });
  const camera = report.rows.find((row) => row.subcategory === 'Cameras');
  assert.equal(camera.eligibleObservations, 0);
  assert.equal(camera.conflictingObservations, 2);
  assert.equal(camera.excludedObservations, 2);
  assert.equal(camera.uniqueOfferCount, 0);
});
