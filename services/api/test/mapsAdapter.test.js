import test from 'node:test';
import assert from 'node:assert/strict';
import { createMapsAdapter } from '../src/integrations/mapsAdapter.js';

const config = {
  mapsMode: 'openstreetmap',
  openStreetMapNominatimUrl: 'https://nominatim.openstreetmap.org',
  openStreetMapUserAgent: 'RentHub/1.0 (test)',
  openStreetMapMinIntervalMs: 1000,
};

test('OpenStreetMap geocoding returns Malaysian coordinates and caches queries', async () => {
  const requests = [];
  const adapter = createMapsAdapter({
    config,
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return {
        ok: true,
        json: async () => [
          {
            lat: '3.1390',
            lon: '101.6869',
            display_name: 'Kuala Lumpur, Malaysia',
          },
        ],
      };
    },
  });

  const first = await adapter.geocode('Kuala Lumpur');
  const cached = await adapter.geocode('kuala lumpur');

  assert.deepEqual(first.coordinates, {
    latitude: 3.139,
    longitude: 101.6869,
  });
  assert.equal(first.provider, 'openstreetmap');
  assert.deepEqual(cached, first);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url.searchParams.get('countrycodes'), 'my');
  assert.equal(requests[0].options.headers['User-Agent'], config.openStreetMapUserAgent);
});

test('disabled maps mode does not contact OpenStreetMap', async () => {
  const adapter = createMapsAdapter({
    config: { ...config, mapsMode: 'disabled' },
    fetchImpl: async () => {
      throw new Error('fetch should not be called');
    },
  });

  const result = await adapter.geocode('Shah Alam');
  assert.equal(result.provider, 'disabled');
  assert.equal(result.coordinates, null);
});

test('search returns multiple normalized Malaysian results and coalesces simultaneous queries', async () => {
  let requests = 0;
  const adapter = createMapsAdapter({ config, fetchImpl: async () => { requests++; return { ok: true, json: async () => [
    { lat: '3.1', lon: '101.6', display_name: 'Shah Alam, Selangor', address: { country_code: 'my', state: 'Selangor' } },
    { lat: '5.4', lon: '100.3', display_name: 'George Town, Penang', address: { country_code: 'my' } },
    { lat: '', lon: '101', display_name: 'Bad coordinates' },
    { lat: 'NaN', lon: '101', display_name: 'Invalid' },
    { lat: '1.3', lon: '103.8', display_name: 'Singapore', address: { country_code: 'sg' } },
  ] }; } });
  const [a, b] = await Promise.all([adapter.search('Shah Alam'), adapter.search('shah alam')]);
  assert.deepEqual(a, b); assert.equal(requests, 1); assert.equal(a.items.length, 2);
  assert.equal(a.items[0].state, 'Selangor');
});
test('rate limit, TTL and failures preserve provider restrictions', async () => {
  let clock = 0, requests = 0; const waits = [];
  const adapter = createMapsAdapter({ config: { ...config, openStreetMapMinIntervalMs: 0 }, now: () => clock,
    wait: async (ms) => { waits.push(ms); clock += ms; }, fetchImpl: async () => { requests++; return { ok: true, json: async () => [] }; } });
  await adapter.search('Kuala Lumpur'); await adapter.search('Penang');
  assert.deepEqual(waits, [1000]);
  await adapter.search('Kuala Lumpur'); assert.equal(requests, 2);
  clock += 86_400_001; await adapter.search('Kuala Lumpur'); assert.equal(requests, 3);
  const failing = createMapsAdapter({ config, fetchImpl: async () => { throw new Error('private provider URL'); } });
  await assert.rejects(failing.search('KL'), { code: 'MAPS_UNAVAILABLE' });
  await assert.rejects(adapter.search('a'), { code: 'VALIDATION_ERROR' });
});

test('place labels keep the selected area separate from its administrative hierarchy', async () => {
  const adapter = createMapsAdapter({ config, fetchImpl: async () => ({ ok: true, json: async () => [
    { name: 'Taman Melawati', lat: '3.21', lon: '101.75',
      display_name: 'Taman Melawati, Hulu Kelang, Gombak, Selangor, Malaysia',
      address: { suburb: 'Taman Melawati', town: 'Hulu Kelang', county: 'Gombak', state: 'Selangor', country_code: 'my' } },
    { lat: '3.15', lon: '101.7', display_name: 'Jalan Ampang, Kampung Baru, Kuala Lumpur, Malaysia',
      address: { road: 'Jalan Ampang', suburb: 'Kampung Baru', city: 'Kuala Lumpur', country_code: 'my' } },
    { lat: '3.16', lon: '101.71', display_name: '12, Jalan Test, Area A, City B, Selangor, Malaysia',
      address: { house_number: '12', road: 'Jalan Test', suburb: 'Area A', city: 'City B', country_code: 'my' } },
  ] }) });
  const result = await adapter.search('Taman Melawati');
  assert.equal(result.items[0].label, 'Taman Melawati');
  assert.equal(result.items[0].city, 'Hulu Kelang');
  assert.equal(result.items[0].state, 'Selangor');
  assert.equal(result.items[1].label, 'Jalan Ampang');
  assert.equal(result.items[2].label, '12 Jalan Test');
  assert.ok(!result.items[0].label.includes('Gombak'));
});

test('explicit pin lookup uses building detail, retains exact pin, coalesces and shares search rate limit', async () => {
  let clock = 0; const calls = [], waits = [];
  const adapter = createMapsAdapter({ config, now: () => clock,
    wait: async (ms) => { waits.push(ms); clock += ms; },
    fetchImpl: async (url) => { calls.push(url); return { ok: true, json: async () => url.pathname === '/search' ? [] : {
      name: 'Public library', lat: '3.14', lon: '101.7', display_name: 'Public library, Jalan Test, Area A, City B, Selangor, Malaysia',
      address: { amenity: 'Public library', road: 'Jalan Test', suburb: 'Area A', city: 'City B', state: 'Selangor', postcode: '05000', country_code: 'my' },
    } }; } });
  await adapter.search('Library');
  const point = { latitude: 3.141592, longitude: 101.712345 };
  const [a, b] = await Promise.all([adapter.resolvePin(point), adapter.resolvePin(point)]);
  assert.deepEqual(a, b); assert.equal(calls.length, 2); assert.deepEqual(waits, [1000]);
  assert.equal(calls[1].searchParams.get('zoom'), '18');
  assert.equal(calls[1].searchParams.get('lat'), String(point.latitude));
  assert.deepEqual(a.item.coordinates, point);
  assert.equal(a.item.label, 'Public library, Jalan Test, Area A');
  assert.equal(a.item.city, 'City B'); assert.equal(a.item.postcode, '05000');
  assert.equal(a.precision, 'nearby_mapped_address');
  assert.ok(!a.item.label.includes('City B'));
  await adapter.resolvePin(point); assert.equal(calls.length, 2);
});

test('state-only, unmapped and non-Malaysian pin results do not invent an exact address', async () => {
  for (const result of [
    { name: 'Selangor', display_name: 'Selangor, Malaysia', address: { state: 'Selangor', country_code: 'my' } },
    { error: 'Unable to geocode' },
    { name: 'Road', display_name: 'Road, Singapore', address: { road: 'Road', country_code: 'sg' } },
  ]) {
    const adapter = createMapsAdapter({ config, fetchImpl: async () => ({ ok: true, json: async () => result }) });
    assert.equal((await adapter.resolvePin({ latitude: 3, longitude: 101 })).item, null);
  }
  let requests = 0;
  const failing = createMapsAdapter({ config, now: () => 0, wait: async () => {}, fetchImpl: async () => {
    requests++; throw new Error('private coordinates');
  } });
  for (let attempt = 0; attempt < 2; attempt++) await assert.rejects(failing.resolvePin({ latitude: 3, longitude: 101 }), { code: 'MAPS_UNAVAILABLE' });
  assert.equal(requests, 2);
  for (const point of [{ latitude: '3', longitude: 101 }, { latitude: NaN, longitude: 101 }, { latitude: 91, longitude: 101 }, { latitude: 3 }, []]) {
    await assert.rejects(failing.resolvePin(point), { code: 'VALIDATION_ERROR' });
  }
  const disabled = createMapsAdapter({ config: { ...config, mapsMode: 'disabled' }, fetchImpl: async () => assert.fail('No lookup while disabled') });
  assert.equal((await disabled.resolvePin({ latitude: 3, longitude: 101 })).provider, 'disabled');
});
