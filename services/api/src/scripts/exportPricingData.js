import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { ListingModel } from '../modules/listing/listing.model.js';
import { ReviewModel } from '../modules/review/review.model.js';
import {
  PRICING_COMPLETED_PAYMENT_STATUSES,
  robustPriceStats,
  selectComparableTier,
} from '../modules/listing/pricingEvidence.js';

const ELIGIBLE_BOOKING_PAYMENT_STATUSES = [
  'authorized',
  ...PRICING_COMPLETED_PAYMENT_STATUSES,
];

function rentalDays(booking) {
  const milliseconds = new Date(booking.endDate) - new Date(booking.startDate);
  return Math.max(1, Math.floor(milliseconds / 86_400_000) + 1);
}

function safeDate(...values) {
  return values
    .map((value) => value && new Date(value))
    .find((value) => value && !Number.isNaN(value.getTime()));
}

function anonymousGroup(value) {
  return createHash('sha256').update(String(value)).digest('hex').slice(0, 20);
}

function baseRow(listing, observedAt, dailyPrice, targetSource) {
  return {
    category: listing.category,
    subcategory: listing.subcategory || 'Unknown',
    condition: listing.condition || 'Unknown',
    brand: listing.brand || 'Unknown',
    product_model: listing.productModel || listing.title,
    canonicalProductId: listing.canonicalProductId ?? null,
    productMatchType: listing.productMatchType ?? 'manual_entry',
    state: listing.state || 'Unknown',
    location: listing.location || listing.state || 'Unknown',
    item_age_years: listing.itemAgeYears ?? null,
    // No point-in-time trust-score snapshot exists yet; leave it missing rather
    // than leaking the Owner's current score into a historical observation.
    owner_trust_score: null,
    owner_average_rating: 0,
    owner_completed_rentals: 0,
    daily_price: dailyPrice,
    source_type: 'real',
    target_source: targetSource,
    observed_at: observedAt.toISOString(),
    group_id: `listing:${anonymousGroup(listing.publicId)}`,
    listingId: listing.publicId,
    ownerId: listing.ownerId,
  };
}

async function exportRows() {
  const [listings, bookings, ownerReviews] = await Promise.all([
    ListingModel.find({ listingType: 'physical' })
      .select('publicId ownerId title category subcategory condition brand productModel canonicalProductId productMatchType itemAgeYears location state dailyPrice status createdAt updatedAt')
      .lean(),
    BookingModel.find({
      listingType: 'physical',
      status: { $in: ['completed', 'active', 'approved'] },
      paymentStatus: { $in: ELIGIBLE_BOOKING_PAYMENT_STATUSES },
      'pricing.baseAmount': { $gt: 0 },
    })
      .select('listingId status startDate endDate pricing.baseAmount completedAt decidedAt createdAt')
      .lean(),
    ReviewModel.find({
      subjectRole: 'owner',
      status: 'published',
    })
      .select('subjectId overallRating createdAt')
      .lean(),
  ]);
  const byId = new Map(listings.map((listing) => [listing.publicId, listing]));
  const observations = [];
  for (const booking of bookings) {
    const listing = byId.get(booking.listingId);
    if (!listing) continue;
    const dailyPrice = booking.pricing.baseAmount / rentalDays(booking);
    if (!Number.isFinite(dailyPrice) || dailyPrice <= 0) continue;
    const completed = booking.status === 'completed';
    const observedAt = safeDate(
      completed && booking.completedAt,
      booking.decidedAt,
      booking.createdAt,
    );
    if (!observedAt) continue;
    observations.push({
      ...baseRow(
        listing,
        observedAt,
        dailyPrice,
        completed ? 'completed_rental' : 'accepted_booking',
      ),
      rental_duration_days: rentalDays(booking),
    });
  }
  for (const listing of listings.filter((item) => item.status === 'active')) {
    const observedAt = safeDate(listing.updatedAt, listing.createdAt);
    if (!observedAt || !Number.isFinite(listing.dailyPrice) || listing.dailyPrice <= 0) continue;
    observations.push({
      ...baseRow(listing, observedAt, listing.dailyPrice, 'active_asking'),
      rental_duration_days: 1,
    });
  }
  observations.sort((left, right) => new Date(left.observed_at) - new Date(right.observed_at));
  const prepared = [];
  for (const observation of observations) {
    const at = new Date(observation.observed_at);
    const prior = prepared.filter(
      (candidate) =>
        new Date(candidate.observed_at) < at &&
        candidate.listingId !== observation.listingId &&
        candidate.category === observation.category,
    );
    const profile = {
      ...observation,
      product_model: observation.product_model,
    };
    const activeTier = selectComparableTier(
      prior.filter((item) => item.target_source === 'active_asking').map((item) => ({
        ...item,
        productModel: item.product_model,
        dailyPrice: item.daily_price,
      })),
      profile,
    );
    const historicalTier = selectComparableTier(
      prior.filter((item) => item.target_source === 'completed_rental').map((item) => ({
        ...item,
        productModel: item.product_model,
        dailyPrice: item.daily_price,
      })),
      profile,
    );
    const active = robustPriceStats(activeTier.items.map((item) => item.dailyPrice));
    const historical = robustPriceStats(historicalTier.items.map((item) => item.dailyPrice));
    const evidenceDates = [...activeTier.items, ...historicalTier.items]
      .map((item) => new Date(item.observed_at))
      .filter((date) => !Number.isNaN(date.getTime()));
    const freshestEvidence = evidenceDates.length
      ? new Date(Math.max(...evidenceDates.map((date) => date.getTime())))
      : null;
    const priorOwnerReviews = ownerReviews.filter(
      (review) =>
        review.subjectId === observation.ownerId &&
        new Date(review.createdAt) < at,
    );
    const ownerAverageRating = priorOwnerReviews.length
      ? priorOwnerReviews.reduce((sum, review) => sum + review.overallRating, 0) /
        priorOwnerReviews.length
      : 0;
    const ownerCompletedRentals = prior.filter(
      (candidate) =>
        candidate.ownerId === observation.ownerId &&
        candidate.target_source === 'completed_rental',
    ).length;
    prepared.push({
      ...observation,
      comparable_active_count: active.count,
      comparable_active_median: active.median,
      comparable_active_mean: active.mean,
      comparable_active_iqr: active.iqr,
      historical_rental_count: historical.count,
      historical_rental_median: historical.median,
      historical_rental_mean: historical.mean,
      historical_rental_iqr: historical.iqr,
      market_freshness_days: freshestEvidence
        ? Math.max(0, Math.floor((at - freshestEvidence) / 86_400_000))
        : null,
      demand_supply_ratio: historical.count / Math.max(active.count, 1),
      owner_average_rating: ownerAverageRating,
      owner_completed_rentals: ownerCompletedRentals,
      prediction_month: at.getUTCMonth() + 1,
    });
  }
  return prepared.map(({ listingId: _listingId, ownerId: _ownerId, ...row }) => row);
}

const outputArgument = process.argv[2];
const output = path.resolve(outputArgument || '.data/pricing_observations.json');
try {
  await connectDatabase();
  const rows = await exportRows();
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify({
    generatedAt: new Date().toISOString(),
    rows,
  }, null, 2));
  console.log(JSON.stringify({ output, rows: rows.length }));
} finally {
  await disconnectDatabase();
}
