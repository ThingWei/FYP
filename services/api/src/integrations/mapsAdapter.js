import { env } from '../config/env.js';
import { AppError } from '../core/errors.js';
import { validCoordinates } from '../core/location.js';

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const text = (value, limit = 80) => typeof value === 'string' ? value.trim().slice(0, limit) : '';
const unique = (parts) => [...new Map(parts.filter(Boolean).map((part) => [part.toLocaleLowerCase('en-MY'), part])).values()];

// A result name is not its entire administrative hierarchy. Keep locality separate.
function normalizePlace(match, { point, reverse = false } = {}) {
  if (!match || typeof match !== 'object' || !text(match.display_name, 240) ||
    (match.address?.country_code && text(match.address.country_code).toLowerCase() !== 'my')) return null;
  const coordinates = point ?? { latitude: typeof match.lat === 'string' && match.lat.trim() ? Number(match.lat) : NaN,
    longitude: typeof match.lon === 'string' && match.lon.trim() ? Number(match.lon) : NaN };
  if (!validCoordinates(coordinates)) return null;
  const address = match.address ?? {};
  const city = [address.city, address.town, address.village, address.municipality].map((v) => text(v)).find(Boolean) ?? '';
  const state = text(address.state);
  const locality = [address.neighbourhood, address.suburb, address.quarter, address.village, address.town, address.city]
    .map((v) => text(v)).find(Boolean) ?? '';
  const road = text(address.road ?? address.pedestrian ?? address.residential, 120);
  const name = text(match.name, 120) || text(match.display_name.split(',')[0], 120);
  const street = road ? [text(address.house_number, 30), road].filter(Boolean).join(' ') : '';
  // State-only reverse results are not a street/address: don't misrepresent them.
  if (reverse && !road && !locality && ![address.building, address.amenity, address.shop, address.tourism].some((v) => text(v))) return null;
  const placeName = ![state, text(address.country), road, text(address.house_number)].includes(name) ? name : '';
  const searchName = street && !text(match.name) ? unique([placeName, street]).join(', ') : name;
  const label = reverse ? unique([placeName, street, locality]).join(', ').slice(0, 240) : searchName;
  if (!label) return null;
  return { label, city, state,
    postcode: typeof address.postcode === 'string' && /^\d{5}$/.test(address.postcode.trim()) ? address.postcode.trim() : '',
    coordinates };
}

// Search and explicit pin lookup share one bounded, cached, 1-request/second queue.
export function createMapsAdapter({ config = env, fetchImpl = fetch, now = Date.now, wait = delay } = {}) {
  const cache = new Map(), pending = new Map();
  let queue = Promise.resolve(), nextRequestAt = 0;
  async function request(key, path, parameters, normalize) {
    const cached = cache.get(key);
    if (cached && cached.expiresAt > now()) return cached.result;
    if (pending.has(key)) return pending.get(key);
    if (pending.size >= 20) throw new AppError('Location lookup is busy', 429, 'MAPS_BUSY');
    const work = queue.then(async () => {
      const waitMilliseconds = Math.max(0, nextRequestAt - now());
      if (waitMilliseconds > 0) await wait(waitMilliseconds);
      nextRequestAt = now() + Math.max(1000, config.openStreetMapMinIntervalMs || 1000);
      const url = new URL(path, config.openStreetMapNominatimUrl);
      for (const [name, value] of Object.entries({ format: 'jsonv2', addressdetails: '1', 'accept-language': 'en,ms', ...parameters })) url.searchParams.set(name, value);
      try {
        const response = await fetchImpl(url, { headers: { Accept: 'application/json',
          'User-Agent': config.openStreetMapUserAgent }, signal: AbortSignal.timeout(10_000), redirect: 'error' });
        if (!response.ok) throw new Error('Provider unavailable');
        const result = normalize(await response.json());
        if (cache.size >= 500) cache.delete(cache.keys().next().value);
        cache.set(key, { result, expiresAt: now() + 86_400_000 });
        return result;
      } catch {
        throw new AppError('Location lookup is temporarily unavailable', 503, 'MAPS_UNAVAILABLE');
      }
    });
    pending.set(key, work);
    queue = work.catch(() => undefined);
    try { return await work; } finally { pending.delete(key); }
  }
  async function search(query) {
    const normalized = String(query ?? '').trim();
    if (normalized.length < 2 || normalized.length > 160) throw new AppError('Enter a place name between 2 and 160 characters', 422, 'VALIDATION_ERROR');
    if (config.mapsMode === 'disabled') return { provider: 'disabled', query: normalized, items: [] };
    return request('search:' + normalized.toLocaleLowerCase('en-MY'), '/search', { q: normalized, countrycodes: 'my', limit: '6' }, (matches) => {
      if (!Array.isArray(matches)) throw new Error('Invalid response');
      return { provider: 'openstreetmap', query: normalized,
        items: matches.slice(0, 6).map((match) => normalizePlace(match)).filter(Boolean) };
    });
  }
  async function resolvePin(coordinates) {
    if (!validCoordinates(coordinates)) throw new AppError('Confirm valid map coordinates', 422, 'VALIDATION_ERROR');
    if (config.mapsMode === 'disabled') return { provider: 'disabled', item: null };
    return request('pin:' + coordinates.latitude + ':' + coordinates.longitude, '/reverse',
      { lat: coordinates.latitude, lon: coordinates.longitude, zoom: '18', layer: 'address,poi' }, (match) => {
        if (!match || typeof match !== 'object' || Array.isArray(match)) throw new Error('Invalid response');
        if (match.error) return { provider: 'openstreetmap', item: null };
        // Retain the user's pin, never snap it to the nearest indexed object.
        return { provider: 'openstreetmap', item: normalizePlace(match, { point: coordinates, reverse: true }), precision: 'nearby_mapped_address' };
      });
  }
  return { search, resolvePin,
    async geocode(query) {
      const result = await search(query), match = result.items[0];
      return { query: result.query, coordinates: match?.coordinates ?? null,
        displayName: match?.label ?? null, provider: result.provider };
    } };
}
export const mapsAdapter = createMapsAdapter();

