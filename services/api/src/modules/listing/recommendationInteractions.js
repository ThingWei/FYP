import { createHash } from 'node:crypto';

export const RECOMMENDATION_INTERACTION_RULES = Object.freeze({
  viewed: { rating: 2, precedence: 0 },
  saved: { rating: 3.5, precedence: 1 },
  booking: { rating: 4, precedence: 2 },
  completed_rental: { rating: 4.5, precedence: 3 },
  published_review: { rating: null, precedence: 4 },
});

const ELIGIBLE_BOOKING_STATUSES = new Set([
  'pending',
  'approved',
  'active',
  'completed',
  'disputed',
]);

function validDate(...values) {
  for (const value of values) {
    if (!value) continue;
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date;
  }
  return new Date(0);
}

function interactionKey(userId, listingId) {
  return `${userId}\u0000${listingId}`;
}

function retainHigherConfidence(map, interaction) {
  if (!interaction.userId || !interaction.listingId) return;
  const key = interactionKey(interaction.userId, interaction.listingId);
  const existing = map.get(key);
  const nextRule = RECOMMENDATION_INTERACTION_RULES[interaction.interactionType];
  const existingRule = existing &&
    RECOMMENDATION_INTERACTION_RULES[existing.interactionType];
  const sourcePriority = { marketplace: 2, demo_seed: 1, synthetic: 0 };
  const nextSource = sourcePriority[interaction.sourceType] ?? -1;
  const previousSource = existing ? sourcePriority[existing.sourceType] ?? -1 : -1;
  if (
    !existing ||
    nextSource > previousSource ||
    (nextSource === previousSource && (
      nextRule.precedence > existingRule.precedence ||
      (nextRule.precedence === existingRule.precedence &&
        interaction.observedAt > existing.observedAt)))
  ) {
    map.set(key, interaction);
  }
}

export function recommendationUserId(userId) {
  return createHash('sha256')
    .update(`renthub-recommendation-v1:${String(userId)}`)
    .digest('hex');
}

export function buildRecommendationInteractions({
  users = [],
  views = [],
  bookings = [],
  reviews = [],
  listings = [],
  includeDemoSeed = false,
  stagedUserIds = [],
  allStaged = false,
} = {}) {
  const interactions = new Map();
  const bookingSourceById = new Map();
  const staged = new Set(stagedUserIds);
  const demoListings = new Set(listings.filter((listing) => listing.sourceType === 'demo_seed').map((listing) => listing.publicId));
  // Apply explicit export-only classification BEFORE stronger-signal selection.
  // Otherwise an old marketplace-labelled view can hide a staged completion.
  const sourceFor = (userId, original = 'marketplace', listingId) => original === 'synthetic' ? original :
    allStaged || staged.has(userId) || demoListings.has(listingId) ? 'demo_seed' : original;
  const retain = (interaction) => {
    if (!includeDemoSeed && interaction.sourceType === 'demo_seed') return;
    retainHigherConfidence(interactions, interaction);
  };
  for (const view of views) retain({
    userId: view.userId, listingId: view.listingId, interactionType: 'viewed',
    rating: 2, observedAt: validDate(view.lastViewedAt), sourceType: sourceFor(view.userId, view.sourceType, view.listingId),
  });

  for (const user of users) {
    for (const listingId of user.savedListingIds ?? []) {
      retain({
        userId: user.authId,
        listingId,
        interactionType: 'saved',
        rating: RECOMMENDATION_INTERACTION_RULES.saved.rating,
        observedAt: validDate(user.updatedAt, user.createdAt),
        sourceType: sourceFor(user.authId, undefined, listingId),
      });
    }
  }

  for (const booking of bookings) {
    bookingSourceById.set(booking.publicId, sourceFor(booking.renterId, booking.sourceType, booking.listingId));
    if (!ELIGIBLE_BOOKING_STATUSES.has(booking.status)) continue;
    const sourceType = sourceFor(booking.renterId, booking.sourceType, booking.listingId);
    if (!includeDemoSeed && sourceType === 'demo_seed') continue;
    const completed = booking.status === 'completed';
    const interactionType = completed ? 'completed_rental' : 'booking';
    retain({
      userId: booking.renterId,
      listingId: booking.listingId,
      interactionType,
      rating: RECOMMENDATION_INTERACTION_RULES[interactionType].rating,
      observedAt: validDate(
        completed && booking.completedAt,
        booking.decidedAt,
        booking.createdAt,
      ),
      sourceType,
    });
  }

  for (const review of reviews) {
    if (review.authorRole !== 'renter' || review.status !== 'published') continue;
    const sourceType = sourceFor(review.authorId, bookingSourceById.get(review.bookingId), review.listingId);
    if (!includeDemoSeed && sourceType === 'demo_seed') continue;
    retain({
      userId: review.authorId,
      listingId: review.listingId,
      interactionType: 'published_review',
      rating: review.overallRating,
      observedAt: validDate(review.createdAt, review.updatedAt),
      sourceType,
    });
  }

  return [...interactions.values()].sort((left, right) =>
    left.userId.localeCompare(right.userId) ||
    left.listingId.localeCompare(right.listingId));
}

export function modelInteraction(interaction) {
  return {
    user_id: recommendationUserId(interaction.userId),
    item_id: interaction.listingId,
    rating: interaction.rating,
    interaction_type: interaction.interactionType,
    observed_at: interaction.observedAt.toISOString(),
    source_type: interaction.sourceType,
  };
}
