import { env } from '../config/env.js';

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

export function createMapsAdapter({
  config = env,
  fetchImpl = fetch,
  now = Date.now,
  wait = delay,
} = {}) {
  const cache = new Map();
  let queue = Promise.resolve();
  let nextRequestAt = 0;

  async function fetchLocation(query) {
    const waitMilliseconds = Math.max(0, nextRequestAt - now());
    if (waitMilliseconds > 0) await wait(waitMilliseconds);
    nextRequestAt = now() + config.openStreetMapMinIntervalMs;

    const url = new URL('/search', config.openStreetMapNominatimUrl);
    url.searchParams.set('q', query);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('countrycodes', 'my');
    url.searchParams.set('limit', '1');

    const response = await fetchImpl(url, {
      headers: {
        Accept: 'application/json',
        'User-Agent': config.openStreetMapUserAgent,
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      throw new Error(`OpenStreetMap geocoding returned HTTP ${response.status}`);
    }

    const matches = await response.json();
    const match = Array.isArray(matches) ? matches[0] : null;
    return {
      query,
      coordinates: match
        ? {
            latitude: Number(match.lat),
            longitude: Number(match.lon),
          }
        : null,
      displayName: match?.display_name ?? null,
      provider: 'openstreetmap',
    };
  }

  return {
    async geocode(query) {
      const normalized = String(query ?? '').trim();
      if (!normalized) throw new Error('A location query is required');
      if (config.mapsMode === 'disabled') {
        return {
          query: normalized,
          coordinates: null,
          displayName: null,
          provider: 'disabled',
        };
      }

      const cacheKey = normalized.toLocaleLowerCase('en-MY');
      if (cache.has(cacheKey)) return cache.get(cacheKey);

      const request = queue.then(() => fetchLocation(normalized));
      queue = request.catch(() => undefined);
      const result = await request;
      cache.set(cacheKey, result);
      return result;
    },
  };
}

export const mapsAdapter = createMapsAdapter();

