import test from 'node:test';
import assert from 'node:assert/strict';
import { preloadDeviceBindings } from '../src/modules/catalog/catalog.devicePreload.js';

const claim = (id, rank = 'normal') => ({ rank, mainsnak: { datavalue: { value: { id } } } });
const entity = (label, properties = {}) => ({ labels: { en: { value: label } }, claims:
  Object.fromEntries(Object.entries(properties).map(([key, ids]) => [key, ids.map((id) => claim(id))])) });
function fixture(products, extra = {}, mutate) {
  const requests = [];
  const entities = { Q100: entity('Fixture Maker'), ...products, ...extra };
  return { requests, load: () => preloadDeviceBindings({ manufacturers: [{ id: 'Q100' }],
    types: { Q7987: 'mouse', Q250: 'keyboard' }, limit: 12,
    providerUrl: 'https://example.invalid/w/api.php', matchesBrand: (label) => label === 'Fixture Maker',
    getJson: async (raw) => {
      const params = new URL(raw).searchParams;
      requests.push(params);
      assert.equal(params.has('query'), false);
      if (params.get('action') === 'query') {
        assert.equal(params.get('srsearch'), 'haswbstatement:P176=Q100|P1716=Q100');
        assert.ok(Number(params.get('srlimit')) <= 50);
        return mutate?.('search') ?? { query: { search: Object.keys(products).map((title) => ({ title })) } };
      }
      assert.equal(params.get('action'), 'wbgetentities');
      const ids = params.get('ids').split('|');
      assert.ok(ids.length <= 50);
      return mutate?.('entities') ?? { entities: Object.fromEntries(ids.map((id) => [id, entities[id] ?? { missing: '' }])) };
    } }) };
}

test('indexed preload validates direct types and bounded subclass ancestry, not arbitrary relations', async () => {
  const f = fixture({
    Q201: entity('Direct mouse', { P176: ['Q100'], P31: ['Q7987'] }),
    Q202: entity('Keyboard model class', { P1716: ['Q100'], P279: ['Q250'] }),
    Q203: entity('Wireless mouse', { P176: ['Q100'], P31: ['Q301'] }),
    Q204: entity('Software', { P176: ['Q100'], P31: ['Q302'] }),
    Q205: entity('Unrelated manufacturer', { P176: ['Q999'], P31: ['Q7987'] }),
    Q206: entity('Cycle', { P176: ['Q100'], P31: ['Q303'] }),
    Q207: entity('Unconfirmed deep ancestry', { P176: ['Q100'], P31: ['Q310'] }),
  }, {
    Q301: entity('Wireless mouse type', { P279: ['Q7987'] }),
    Q302: entity('Software type', { P31: ['Q7987'] }), // P31 chains do not establish product subclasses.
    Q303: entity('Cycle type', { P279: ['Q303'] }),
    Q310: entity('Deep 1', { P279: ['Q311'] }), Q311: entity('Deep 2', { P279: ['Q312'] }),
    Q312: entity('Deep 3', { P279: ['Q313'] }), Q313: entity('Deep 4', { P279: ['Q7987'] }),
  });
  const result = await f.load();
  assert.deepEqual(result.map((item) => item.modelLabel.value), ['Direct mouse', 'Keyboard model class', 'Wireless mouse']);
  assert.ok(f.requests.length <= 7);
});

test('explicit conflicting brand and deprecated manufacturer claims cannot validate an OEM product', async () => {
  const old = entity('Deprecated manufacture', { P31: ['Q7987'] });
  old.claims.P176 = [claim('Q100', 'deprecated')];
  const f = fixture({
    Q201: entity('Other brand OEM mouse', { P176: ['Q100'], P1716: ['Q999'], P31: ['Q7987'] }),
    Q202: entity('Selected brand mouse', { P176: ['Q100'], P1716: ['Q100'], P31: ['Q7987'] }),
    Q203: old,
  }, { Q999: entity('Different brand') });
  assert.deepEqual((await f.load()).map((item) => item.modelLabel.value), ['Selected brand mouse']);
});

test('malformed/partial responses remain unavailable; a valid empty search is a no-match', async () => {
  const products = { Q201: entity('Mouse', { P176: ['Q100'], P31: ['Q7987'] }) };
  for (const payload of [{}, { error: { code: 'maxlag' } }, { query: {} }]) {
    await assert.rejects(fixture(products, {}, (stage) => stage === 'search' ? payload : undefined).load(), /manufacturer search response/);
  }
  for (const payload of [{}, { entities: [] }, { entities: {} }]) {
    await assert.rejects(fixture(products, {}, (stage) => stage === 'entities' ? payload : undefined).load(), /entity response/);
  }
  const empty = fixture({});
  assert.deepEqual(await empty.load(), []);
  assert.equal(empty.requests.length, 1);
});

test('ancestor exploration remains bounded when classifications fan out', async () => {
  const parents = Array.from({ length: 150 }, (_, index) => `Q${1000 + index}`);
  const f = fixture({ Q201: entity('Unconfirmed', { P176: ['Q100'], P31: parents }) });
  assert.deepEqual(await f.load(), []);
  const ancestorRequests = f.requests.slice(2);
  assert.equal(ancestorRequests.reduce((count, params) => count + params.get('ids').split('|').length, 0), 96);
});
