import { AppError } from '../../core/errors.js';
import { UserModel } from '../user/user.model.js';
import { listingRepository } from './listing.repository.js';
import { physicalRentalDate } from '../../core/calendarDate.js';

export const DAY = 86400000;
export async function recommendationUser(identity) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user?.roles.includes('renter')) throw new AppError('Renter role is required', 403, 'FORBIDDEN');
  const restricted = await UserModel.distinct('authId', { accountStatus: { $ne: 'active' } });
  return { user, filter: { status: 'active', ownerId: { $nin: [...new Set([
    identity.authId, ...(user.blockedUserIds ?? []), ...restricted,
  ])] } } };
}

export function malaysiaDay(now = new Date()) {
  return new Date(now.getTime() + 8 * 3600000).toISOString().slice(0, 10);
}
export function proximityScore(item, query) {
  const point = item.publicGeoPoint?.coordinates ?? (item.locationPrecision === 'approximate' && item.coordinates
    ? [item.coordinates.longitude, item.coordinates.latitude] : null);
  if (query.latitude === undefined || !Array.isArray(point) || point.length !== 2) return null;
  const radians = v => v * Math.PI / 180;
  const lat = Number(query.latitude), lon = Number(query.longitude);
  const a = Math.sin(radians(point[1] - lat) / 2) ** 2 +
    Math.cos(radians(lat)) * Math.cos(radians(point[1])) * Math.sin(radians(point[0] - lon) / 2) ** 2;
  const km = 6371.0088 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
  return Math.max(0, 1 - km / (Number(query.radiusKm) || 10));
}
export async function availabilityContext(query, now = new Date()) {
  const hasDates = !!(query.availableFrom && query.availableTo);
  const start = physicalRentalDate(hasDates ? query.availableFrom : malaysiaDay(now));
  const end = hasDates ? physicalRentalDate(query.availableTo) : new Date(start.getTime() + DAY);
  return { unavailable: new Set(await listingRepository.findUnavailableListingIds(start, end)), hasDates };
}
export function rerankRecommendations(items, query, availability) {
  return items.map(item => {
    const base = Number(item.recommendation?.score) || 0;
    const proximity = proximityScore(item, query);
    const free = item.listingType === 'physical' ? !availability.unavailable.has(item.publicId) : null;
    const weight = .75 + (proximity === null ? 0 : .15) + (free === null ? 0 : .1);
    const rank = (.75 * base + (proximity ?? 0) * .15 + (free === true ? .1 : 0)) / weight;
    return { ...item, recommendation: { ...item.recommendation,
      base_score: base, proximity_score: proximity, availability_score: free === null ? null : Number(free),
      score: Math.round(rank * 10000) / 10000,
      availabilityLabel: free === true ? (availability.hasDates ? 'Available for selected dates' :
        'Available today—check your rental dates') : null,
    } };
  }).sort((a, b) => b.recommendation.score - a.recommendation.score || a.publicId.localeCompare(b.publicId));
}

// Only reviewed generic complementary uses. No mount/connector/fit guarantee.
export const COMPLEMENT_RULES = Object.freeze([
  { category: 'Devices', subcategory: 'Cameras', targets: [
    { category: 'Equipment', subcategory: 'Event equipment', terms: /\b(tripod|softbox|light stand|studio light|led panel)\b/i },
    { category: 'Equipment', subcategory: 'Other equipment', terms: /\b(tripod|light stand)\b/i },
    { category: 'Devices', subcategory: 'Audio', terms: /\b(microphone|audio recorder|sound recorder)\b/i },
  ] },
  { category: 'Equipment', subcategory: 'Event equipment', targets: [
    { category: 'Devices', subcategory: 'Audio', terms: /\b(microphone|pa speaker|pa system|audio mixer)\b/i },
  ] },
]);
export function complementary(anchor, candidate) {
  if (anchor.listingType !== 'physical' || candidate.listingType !== 'physical' || anchor.publicId === candidate.publicId) return false;
  const rule = COMPLEMENT_RULES.find(r => r.category === anchor.category && r.subcategory === anchor.subcategory);
  return !!rule?.targets.some(t => t.category === candidate.category && t.subcategory === candidate.subcategory &&
    t.terms.test(`${candidate.title} ${candidate.productModel ?? ''}`));
}
export function trendingScores(views, bookings, now = new Date()) {
  const signals = new Map(), since = now.getTime() - 30 * DAY;
  function add(userId, listingId, at, score) {
    if (!userId || !listingId || !at || !Number.isFinite(new Date(at).getTime()) || new Date(at).getTime() < since || new Date(at) > now) return;
    const key = `${userId}\0${listingId}`;
    signals.set(key, { listingId, score: Math.max(score, signals.get(key)?.score ?? 0) });
  }
  for (const view of views) add(view.userId, view.listingId, view.lastViewedAt, 1);
  for (const b of bookings) if ((!b.sourceType || b.sourceType === 'marketplace') && ['approved', 'active', 'completed'].includes(b.status)) {
    add(b.renterId, b.listingId, b.status === 'completed' ? b.completedAt ?? b.decidedAt ?? b.createdAt :
      b.status === 'active' ? b.activatedAt ?? b.decidedAt ?? b.createdAt : b.decidedAt ?? b.createdAt,
      b.status === 'completed' ? 5 : 3);
  }
  const scores = new Map();
  for (const { listingId, score } of signals.values()) scores.set(listingId, (scores.get(listingId) ?? 0) + score);
  return scores;
}
export function coRentalCounts(anchorId, bookings, now = new Date()) {
  const groups = new Map(), supporters = new Map();
  for (const b of bookings) {
    const start = new Date(b.startDate).getTime();
    if (!['approved', 'active', 'completed'].includes(b.status) || b.sourceType && b.sourceType !== 'marketplace' ||
        !Number.isFinite(start) || start < now.getTime() - 365 * DAY || start > now.getTime()) continue;
    if (!groups.has(b.renterId)) groups.set(b.renterId, []);
    groups.get(b.renterId).push(b);
  }
  for (const [userId, rows] of groups) for (const anchor of rows.filter(b => b.listingId === anchorId)) {
    for (const b of rows) if (b.listingId !== anchorId && Math.abs(new Date(b.startDate) - new Date(anchor.startDate)) <= 7 * DAY) {
      if (!supporters.has(b.listingId)) supporters.set(b.listingId, new Set());
      supporters.get(b.listingId).add(userId);
    }
  }
  return new Map([...supporters].filter(([, users]) => users.size >= 3).map(([id, users]) => [id, users.size]));
}
