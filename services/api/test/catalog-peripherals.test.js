import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogProvider } from '../src/modules/catalog/catalog.provider.js';
import { searchCuratedCatalog } from '../src/modules/catalog/catalog.curated.js';
import { deviceCatalogTypes } from '../src/modules/catalog/catalog.deviceDomains.js';

const uri = (id) => ({ type: 'uri', value: `http://www.wikidata.org/entity/${id}` });
const text = (value) => ({ type: 'literal', value });
const examples = [
  ['Computers', 'Logitech', 'Q223127', 'MX Master 3S', 'Q125697788', 'Q7987', 'mouse'],
  ['Computers', 'Logitech', 'Q223127', 'MX Keys S', 'Q125697771', 'Q250', 'keyboard'],
  ['Gaming', 'Sony', 'Q18594', 'DualSense', 'Q89695113', 'Q865422', 'controller'],
  // Deliberately invented test IDs for an uncatalogued monitor: not source claims.
  ['Computers', 'Example Display Co', 'Q900001', 'Example Monitor', 'Q900002', 'Q5290', 'monitor'],
];

test('structured device searches validate type and manufacturer for every peripheral domain', async () => {
  const original = global.fetch;
  try {
    for (const [subcategory, brand, makerId, model, modelId, typeId, productType] of examples) {
      const maker = brand === 'Sony' ? 'Sony Interactive Entertainment' : brand;
      const urls = [];
      global.fetch = async (raw) => {
        const url = new URL(raw); urls.push(url);
        if (url.searchParams.get('action') === 'wbsearchentities') {
          assert.equal(url.searchParams.get('search'), model);
          return { ok: true, json: async () => ({ search: [{ id: modelId, label: model }] }) };
        }
        const query = url.searchParams.get('query');
        assert.match(query, /wdt:P176\|wdt:P1716/);
        assert.match(query, /wdt:P31\/wdt:P279\*\|wdt:P279\+/);
        assert.ok(query.includes(`VALUES ?model { wd:${modelId} }`));
        assert.ok(query.includes(`wd:${typeId}`));
        const valid = { model: uri(modelId), modelLabel: text(model), manufacturer: uri(makerId),
          manufacturerLabel: text(maker), domainType: uri(typeId) };
        return { ok: true, json: async () => ({ results: { bindings: [
          valid, valid,
          { ...valid, model: uri('Q999999') }, // Not one of the bounded search candidates.
          { ...valid, manufacturerLabel: text('Other manufacturer') },
          { ...valid, domainType: uri('Q7889') }, // Video game software, not hardware.
          { ...valid, model: uri('not-an-entity') },
        ] } }) };
      };
      const result = await catalogProvider.search({ category: 'Devices', subcategory,
        entityType: 'product', brand, query: model });
      const item = result.items.find((value) => value.source === 'wikidata-devices');
      assert.equal(result.provider, 'wikidata-devices');
      assert.equal(item.id, modelId);
      assert.equal(item.brandId, makerId);
      assert.equal(item.specifications.productType, productType);
      assert.equal(item.specifications.validation, 'structured_type_and_manufacturer');
      assert.equal(result.items.filter((value) => value.source === 'wikidata-devices').length, 1);
      assert.equal(urls.length, 2);
    }
  } finally { global.fetch = original; }
});

test('brand queries require hardware evidence; a text-matching company/software result is insufficient', async () => {
  const original = global.fetch;
  global.fetch = async (raw) => {
    const url = new URL(raw);
    if (url.searchParams.has('action')) return { ok: true, json: async () => ({ search: [
      { id: 'Q900010', label: 'Example Peripheral Maker' },
      { id: 'Q900011', label: 'Example Software' },
    ] }) };
    assert.match(url.searchParams.get('query'), /VALUES \?manufacturer \{ wd:Q900010 wd:Q900011 \}/);
    return { ok: true, json: async () => ({ results: { bindings: [
      { manufacturer: uri('Q900010'), manufacturerLabel: text('Example Peripheral Maker'), domainType: uri('Q7987') },
      { manufacturer: uri('Q900011'), manufacturerLabel: text('Example Software'), domainType: uri('Q7889') },
    ] } }) };
  };
  try {
    const r = await catalogProvider.search({ category: 'Devices', subcategory: 'Computers',
      entityType: 'brand', query: 'Example' });
    assert.deepEqual(r.items.map((item) => item.label), ['Example Peripheral Maker']);
  } finally { global.fetch = original; }
});

test('manufacturer punctuation and reviewed aliases do not reject a valid monitor', async () => {
  const original = global.fetch;
  global.fetch = async (raw) => {
    const url = new URL(raw);
    if (url.searchParams.has('action')) return { ok: true, json: async () => ({
      search: [{ id: 'Q4781242', label: 'Apple Thunderbolt Display' }],
    }) };
    const query = url.searchParams.get('query');
    assert.ok(query.includes('"^ +| +$", ""'));
    assert.ok(query.includes('"apple inc"'));
    return { ok: true, json: async () => ({ results: { bindings: [{
      model: uri('Q4781242'), modelLabel: text('Apple Thunderbolt Display'),
      manufacturer: uri('Q312'), manufacturerLabel: text('Apple Inc.'), domainType: uri('Q5290'),
    }] } }) };
  };
  try {
    const r = await catalogProvider.search({ category: 'Devices', subcategory: 'Computers',
      entityType: 'product', brand: 'Apple', query: 'Apple Thunderbolt Display' });
    assert.equal(r.items[0].id, 'Q4781242');
    assert.equal(r.items[0].specifications.productType, 'monitor');
  } finally { global.fetch = original; }
});

test('first model page uses canonical manufacturer and rejects a conflicting selected brand', async () => {
  const original = global.fetch;
  let calls = 0;
  global.fetch = async (raw) => {
    calls++;
    const query = new URL(raw).searchParams.get('query');
    assert.ok(query.includes('VALUES ?manufacturer { wd:Q223127 }'));
    assert.ok(query.includes('FILTER(?manufacturer = wd:Q223127)'));
    return { ok: true, json: async () => ({ results: { bindings: [
      { model: uri('Q125697788'), modelLabel: text('Logitech MX Master 3S'),
        manufacturer: uri('Q223127'), manufacturerLabel: text('Logitech'), domainType: uri('Q7987') },
      { model: uri('Q900002'), modelLabel: text('Unrelated mouse'),
        manufacturer: uri('Q900001'), manufacturerLabel: text('Logitech'), domainType: uri('Q7987') },
    ] } }) };
  };
  try {
    const r = await catalogProvider.search({ category: 'Devices', subcategory: 'Computers',
      entityType: 'product', query: '', brand: 'Logitech', catalogBrandId: 'wikidata-devices:Q223127' });
    assert.equal(r.items[0].id, 'Q125697788');
    assert.equal(r.items.filter((item) => item.source === 'wikidata-devices').length, 1);
    const conflict = await catalogProvider.search({ category: 'Devices', subcategory: 'Computers',
      entityType: 'product', query: '', brand: 'Unrelated maker', catalogBrandId: 'wikidata-devices:Q223127' });
    assert.deepEqual(conflict.items, []);
    assert.equal(calls, 2);
  } finally { global.fetch = original; }
});

test('reviewed starter catalogue browses all four peripheral types without any external service', async () => {
  const original = global.fetch;
  global.fetch = async () => { throw new Error('provider offline'); };
  try {
    for (const [subcategory, brand, model, productType] of [
      ['Computers', 'Logitech', 'MX Master 3S', 'mouse'],
      ['Computers', 'Logitech', 'MX Keys S', 'keyboard'],
      ['Computers', 'Dell', 'U2723QE', 'monitor'],
      ['Gaming', 'Sony', 'DualSense', 'controller'],
    ]) {
      const brands = await catalogProvider.search({ category: 'Devices', subcategory,
        entityType: 'brand', query: '' });
      assert.ok(brands.items.some((item) => item.label === brand));
      const models = await catalogProvider.search({ category: 'Devices', subcategory,
        entityType: 'product', brand, query: '' });
      const entry = models.items.find((item) => item.label === model);
      assert.equal(entry.specifications.productType, productType);
      assert.match(entry.specifications.identitySourceUrl, /^https:\/\//);
      assert.equal(models.providerAvailable, false);
    }
    assert.deepEqual(searchCuratedCatalog({ category: 'Devices', subcategory: 'Smartphones',
      entityType: 'product', brand: 'Logitech', query: '' }), []);
    assert.equal(deviceCatalogTypes({ category: 'Vehicles', subcategory: 'Computers' }), undefined);
  } finally { global.fetch = original; }
});

test('malformed responses and outages are unavailable, while verified empty responses remain no-match', async () => {
  const original = global.fetch;
  const input = { category: 'Devices', subcategory: 'Computers', entityType: 'product',
    brand: 'Uncatalogued maker', query: 'Uncatalogued model' };
  try {
    for (const response of [{}, { error: { code: 'maxlag' } }, { results: {} }]) {
      global.fetch = async () => ({ ok: true, json: async () => response });
      await assert.rejects(catalogProvider.search(input), /could not determine a reliable no-match/);
    }
    global.fetch = async () => { throw new Error('unavailable'); };
    await assert.rejects(catalogProvider.search(input), /could not determine a reliable no-match/);
    global.fetch = async () => ({ ok: true, json: async () => ({ search: [] }) });
    assert.deepEqual((await catalogProvider.search(input)).items, []);
    global.fetch = async (raw) => ({ ok: true, json: async () => new URL(raw).searchParams.has('action')
      ? { search: [{ id: 'Q900020' }] } : { results: { bindings: [] } } });
    assert.deepEqual((await catalogProvider.search(input)).items, []);
  } finally { global.fetch = original; }
});
