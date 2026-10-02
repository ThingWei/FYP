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
