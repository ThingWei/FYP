import { AppError } from '../../core/errors.js';
import { nearbyFilter } from '../../core/location.js';
import { BookingModel } from '../booking/booking.model.js';
import { ListingModel } from './listing.model.js';
import { ListingViewModel } from './listingView.model.js';
import { listingService } from './listing.service.js';
import { DAY, malaysiaDay, recommendationUser, proximityScore, complementary,
  trendingScores, coRentalCounts, availabilityContext, rerankRecommendations } from './recommendationEvidence.js';

const realBookings = { status: { $in: ['approved', 'active', 'completed'] },
  $or: [{ sourceType: 'marketplace' }, { sourceType: { $exists: false } }] };
const section = items => ({ status: items.length ? 'ready' : 'empty', items });
const safely = async work => { try { return await work(); } catch { return { status: 'unavailable', items: [] }; } };
export const recommendationFeed = {
  async recordView(identity, listingId) {
    const { filter } = await recommendationUser(identity);
    if (!await ListingModel.exists({ ...filter, publicId: listingId })) throw new AppError('Listing unavailable', 404, 'NOT_FOUND');
    const now = new Date(), key = { userId: identity.authId, listingId, day: malaysiaDay(now) };
    const update = { $set: { lastViewedAt: now, expiresAt: new Date(now.getTime() + 90 * DAY) } };
    try { await ListingViewModel.updateOne(key, update, { upsert: true }); }
    catch (error) { if (error.code !== 11000) throw error; await ListingViewModel.updateOne(key, update); }
    return { recorded: true };
  },
  async home(identity, query) {
    const { filter } = await recommendationUser(identity);
    const limit = Math.min(Number(query.limit) || 30, 30);
    const work = (key, task) => query.section && query.section !== key ? Promise.resolve(undefined) : safely(task);
    const [recommended, trending, recentlyViewed] = await Promise.all([
      work('recommended', async () => section(await listingService.recommended(identity, query))),
      work('trending', async () => {
        if (query.latitude === undefined) return { status: 'location_required', items: [] };
        const since = new Date(Date.now() - 30 * DAY);
        const [listings, views, bookings] = await Promise.all([
          ListingModel.find({ ...filter, ...nearbyFilter(query), sourceType: { $ne: 'demo_seed' } }).limit(1000),
          ListingViewModel.find({ lastViewedAt: { $gte: since } }).sort({ lastViewedAt: -1 }).limit(10000).lean(),
          BookingModel.find({ ...realBookings, $and: [{ $or: [{ completedAt: { $gte: since } }, { activatedAt: { $gte: since } }, { decidedAt: { $gte: since } }, { createdAt: { $gte: since } }] }] })
            .sort({ createdAt: -1 }).limit(10000).lean(),
        ]);
        const scores = trendingScores(views, bookings);
        const availability = await availabilityContext(query);
        const items = listings.filter(item => (scores.get(item.publicId) ?? 0) > 0)
          .sort((a, b) => scores.get(b.publicId) - scores.get(a.publicId) ||
            (proximityScore(b, query) ?? 0) - (proximityScore(a, query) ?? 0) || a.publicId.localeCompare(b.publicId));
        return section(items.slice(0, limit).map(item => {
          const presented = item.toJSON();
          const ranked = rerankRecommendations([{ ...presented, recommendation: { reason: 'Popular with renters in this area' } }], query, availability)[0];
          return ranked;
        }));
      }),
      work('recentlyViewed', async () => {
        const views = await ListingViewModel.find({ userId: identity.authId,
          lastViewedAt: { $gte: new Date(Date.now() - 90 * DAY) } }).sort({ lastViewedAt: -1 }).limit(1000).lean();
        const ids = [...new Set(views.map(row => row.listingId))];
        const listings = await ListingModel.find({ ...filter, publicId: { $in: ids } });
        const byId = new Map(listings.map(item => [item.publicId, item.toJSON()]));
        return section(ids.filter(id => byId.has(id)).slice(0, limit).map(id => byId.get(id)));
      }),
    ]);
    return { recommended, trending, recentlyViewed, nearbyUsesApproximateLocations: true };
  },
  async complements(identity, listingId, query) {
    const { filter } = await recommendationUser(identity);
    const anchor = await ListingModel.findOne({ ...filter, publicId: listingId });
    if (!anchor) throw new AppError('Listing unavailable', 404, 'NOT_FOUND');
    const candidates = await ListingModel.find({ ...filter, ...nearbyFilter(query), listingType: 'physical' }).limit(1000);
    const ids = candidates.filter(item => complementary(anchor, item)).map(item => item.publicId);
    if (!ids.length) return section([]);
    const bookings = await BookingModel.find({ ...realBookings, startDate: { $gte: new Date(Date.now() - 365 * DAY), $lte: new Date() } })
      .sort({ startDate: -1 }).limit(10000).lean();
    const coRentals = coRentalCounts(anchor.publicId, bookings);
    const ranked = await listingService.recommended(identity, { ...query, limit: 30 }, { candidateIds: ids, returnAll: true });
    ranked.sort((a, b) => (coRentals.get(b.publicId) ?? 0) - (coRentals.get(a.publicId) ?? 0) ||
      b.recommendation.score - a.recommendation.score);
    return section(ranked.slice(0, Math.min(Number(query.limit) || 6, 30)).map(item => ({ ...item,
      recommendation: { ...item.recommendation, reason: coRentals.has(item.publicId)
        ? 'Often rented together for similar uses. Check compatibility before booking.'
        : 'Useful for a related activity. Check compatibility before booking.' } })));
  },
};
