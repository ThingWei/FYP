import { nearbyFilter } from '../../core/location.js';
import { LISTING_CATEGORIES } from './listing.model.js';

const pattern = value => new RegExp(value.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');

// Shared discovery constraints; only public locality is searchable here.
export function recommendationCandidateFilter(base, query) {
  const filter = { ...base, ...nearbyFilter(query) };
  if (query.search?.trim()) {
    const text = pattern(query.search);
    filter.$or = [{ title: text }, { description: text }, { 'locationDetails.city': text }, { state: text }];
  }
  if (LISTING_CATEGORIES.includes(query.category)) filter.category = query.category;
  if (['physical', 'service'].includes(query.type)) filter.listingType = query.type;
  if (query.location?.trim()) filter.$and = [...(filter.$and ?? []),
    { $or: [{ 'locationDetails.city': pattern(query.location) }, { state: pattern(query.location) }] }];
  if (query.verified !== undefined) filter.verified = query.verified === 'true';
  if (query.promoted === 'true') {
    const now = new Date();
    filter['promotion.enabled'] = true;
    filter['promotion.startsAt'] = { $lte: now }; filter['promotion.endsAt'] = { $gte: now };
  }
  if (query.minPrice !== undefined || query.maxPrice !== undefined) filter.dailyPrice = {
    ...(query.minPrice !== undefined && { $gte: Number(query.minPrice) }),
    ...(query.maxPrice !== undefined && { $lte: Number(query.maxPrice) }),
  };
  return filter;
}
