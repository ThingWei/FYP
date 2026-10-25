import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogProvider } from '../src/modules/catalog/catalog.provider.js';

test('smartphone queries expand their stable ordered window instead of repeating the first page', async () => {
  const original = global.fetch;
  const limits = [];
  global.fetch = async (raw) => {
    const query = new URL(raw).searchParams.get('query');
    assert.match(query, /ORDER BY \?modelLabel \?model/);
    const limit = Number(query.match(/LIMIT (\d+)/)[1]);
    limits.push(limit);
    return { ok: true, json: async () => ({ results: { bindings: Array.from({ length: limit }, (_, index) => ({
      model: { value: `http://www.wikidata.org/entity/Q${900000 + index}` },
      modelLabel: { value: `Synthetic fixture phone ${index}` },
    })) } }) };
  };
  try {
    for (const limit of [12, 24, 121]) {
      const r = await catalogProvider.search({ category: 'Devices', subcategory: 'Smartphones',
        entityType: 'product', brand: 'Fixture make', catalogBrandId: 'wikidata-smartphones:Q9000', query: '', limit });
      assert.equal(r.items.length, limit);
    }
    assert.deepEqual(limits, [12, 24, 121]);
  } finally { global.fetch = original; }
});

test('general Wikidata searches respect the anonymous candidate cap while preserving domain filtering', async () => {
  const original = global.fetch;
  global.fetch = async (raw) => {
    assert.equal(new URL(raw).searchParams.get('limit'), '50');
    return { ok: true, json: async () => ({ search: Array.from({ length: 50 }, (_, index) => ({
      id: `Q${910000 + index}`, label: `Fixture make Camera ${index}`,
      description: 'Fixture make camera model',
    })) }) };
  };
  try {
    const r = await catalogProvider.search({ category: 'Devices', subcategory: 'Cameras',
      entityType: 'product', brand: 'Fixture make', query: 'Camera', limit: 121 });
    assert.equal(r.items.length, 50);
    assert.ok(r.items.every((item) => item.source === 'wikidata'));
  } finally { global.fetch = original; }
});

test('book model windows expand their bounded scan without weakening subject checks', async () => {
  const original = global.fetch;
  const scanLimits = [];
  global.fetch = async (raw) => {
    const limit = Number(new URL(raw).searchParams.get('limit'));
    scanLimits.push(limit);
    return { ok: true, json: async () => ({ entries: [
      { key: '/works/OL999999W', title: 'Wrong subject', subjects: ['Textbooks'] },
      ...Array.from({ length: 121 }, (_, index) => ({ key: `/works/OL${990000 + index}W`,
        title: `Fiction fixture ${index}`, subjects: ['Fantasy fiction'] })),
    ] }) };
  };
  try {
    for (const limit of [12, 24, 121]) {
      const r = await catalogProvider.search({ category: 'Books', subcategory: 'Fiction',
        entityType: 'product', brand: 'Fixture author', catalogBrandId: 'openlibrary:OL999999A', query: '', limit });
      assert.equal(r.items.length, limit);
      assert.ok(r.items.every((item) => item.label !== 'Wrong subject'));
    }
    assert.deepEqual(scanLimits, [48, 96, 484]);
  } finally { global.fetch = original; }
});
