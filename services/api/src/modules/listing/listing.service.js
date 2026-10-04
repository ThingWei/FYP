import { AppError } from '../../core/errors.js';
import { env } from '../../config/env.js';
import { aiClient } from '../../integrations/aiClient.js';
import { PlatformSettingModel } from '../admin/platformSetting.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { ReviewModel } from '../review/review.model.js';
import { UserModel } from '../user/user.model.js';
import {
  LISTING_CATEGORIES,
  LISTING_STATUSES,
  ListingModel,
} from './listing.model.js';
import { listingRepository } from './listing.repository.js';
import { uploadService } from '../upload/upload.service.js';
import { resolveProductIdentity } from '../catalog/catalog.service.js';
import {
  buildRecommendationInteractions,
  modelInteraction,
  recommendationUserId,
} from './recommendationInteractions.js';
import {
  PRICING_EVIDENCE_QUERY_LIMIT,
  PRICING_EVIDENCE_WINDOW_DAYS,
  PRICING_FALLBACK_MIN_OBSERVATIONS,
  PRICING_COMPLETED_PAYMENT_STATUSES,
  evidenceCounts,
  robustPriceStats,
  selectComparableTier,
  statisticalFallback,
  statisticalFallbackConfidence,
} from './pricingEvidence.js';

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

function escapedPattern(value) {
  return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

function rentalDays(booking) {
  const milliseconds = new Date(booking.endDate) - new Date(booking.startDate);
  return Math.max(1, Math.floor(milliseconds / 86_400_000) + 1);
}

function listingInput(input) {
  const listingType =
    input.listingType ?? (input.category === 'Services' ? 'service' : 'physical');
  return {
    ...(input.title !== undefined && { title: input.title }),
    ...(input.description !== undefined && { description: input.description }),
    ...(input.category !== undefined && { category: input.category }),
    ...(input.subcategory !== undefined && { subcategory: input.subcategory }),
    ...(input.brand !== undefined && { brand: input.brand }),
    ...(input.productModel !== undefined && { productModel: input.productModel }),
    ...(input.canonicalProductId !== undefined && {
      canonicalProductId: input.canonicalProductId,
    }),
    ...(input.catalogBrandId !== undefined && { catalogBrandId: input.catalogBrandId }),
    ...(input.productMatchType !== undefined && {
      productMatchType: input.productMatchType,
    }),
    ...(input.catalogSource !== undefined && { catalogSource: input.catalogSource }),
    ...(input.itemAgeYears !== undefined && { itemAgeYears: input.itemAgeYears }),
    listingType,
    ...(input.dailyPrice !== undefined && { dailyPrice: input.dailyPrice }),
    ...(input.priceUnit !== undefined && { priceUnit: input.priceUnit }),
    ...(input.condition !== undefined && { condition: input.condition }),
    ...(input.securityDeposit !== undefined && {
      securityDeposit: input.securityDeposit,
    }),
    ...(input.damageWaiverAvailable !== undefined && {
      damageWaiverAvailable: input.damageWaiverAvailable,
    }),
    ...(input.damageWaiverFee !== undefined && {
      damageWaiverFee: input.damageWaiverFee,
    }),
    ...(input.fulfilmentMethods !== undefined && {
      fulfilmentMethods: input.fulfilmentMethods,
    }),
    ...(input.serviceDetails !== undefined && {
      serviceDetails: input.serviceDetails,
    }),
    ...(input.location !== undefined && { location: input.location }),
    ...(input.state !== undefined && { state: input.state }),
    ...(input.images !== undefined && { images: input.images }),
  };
}

async function withResolvedProductIdentity(input, existing = {}) {
  const listingType = input.listingType ?? existing.listingType ??
    (input.category === 'Services' ? 'service' : 'physical');
  if (listingType !== 'physical') return input;
  const requestedMatchType = input.productMatchType ?? existing.productMatchType;
  const manualProduct = requestedMatchType === 'manual_entry';
  const manualModel = requestedMatchType === 'catalog_brand_match_model_manual';
  const identity = await resolveProductIdentity({
    category: input.category ?? existing.category,
    subcategory: input.subcategory ?? existing.subcategory,
    brand: input.brand ?? existing.brand,
    productModel: input.productModel ?? existing.productModel,
    // A user can deliberately switch a previously recognised listing back to
    // manual entry. Do not silently resurrect its old canonical identifiers.
    canonicalProductId: manualProduct || manualModel
      ? null
      : input.canonicalProductId ?? existing.canonicalProductId,
    catalogBrandId: manualProduct
      ? null
      : input.catalogBrandId ?? existing.catalogBrandId,
    productMatchType: requestedMatchType,
  });
  return {
    ...input,
    brand: identity.brand,
    productModel: identity.model,
    canonicalProductId: identity.canonicalProductId,
    catalogBrandId: identity.catalogBrandId,
    productMatchType: identity.productMatchType,
    catalogSource: identity.catalogSource,
  };
}

async function requireOwner(identity) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) {
    throw new AppError('Owner profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  if (!user.roles.includes('owner')) {
    throw new AppError('Owner role is required', 403, 'FORBIDDEN');
  }
  return user;
}

async function requireOwnedListing(id, identity) {
  await requireOwner(identity);
  const listing = await listingRepository.findOwnedById(id, identity.authId);
  if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
  return listing;
}

export const listingService = {
  async recommended(identity, query) {
    const user = await UserModel.findOne({ authId: identity.authId });
    if (!user || !user.roles.includes('renter')) {
      throw new AppError('Renter role is required', 403, 'FORBIDDEN');
    }
    const limit = Math.min(Math.max(Number(query.limit) || 10, 1), 30);
    const restrictedOwnerIds = await UserModel.distinct('authId', {
      accountStatus: { $ne: 'active' },
    });
    const excludedOwnerIds = [...new Set([
      identity.authId,
      ...(user.blockedUserIds ?? []),
      ...restrictedOwnerIds,
    ])];
    const [candidates, interactionUsers, bookings, reviews] = await Promise.all([
      ListingModel.find({
        status: 'active',
        ownerId: { $nin: excludedOwnerIds },
      })
        .sort({ promoted: -1, rating: -1, createdAt: -1 })
        .limit(200),
      UserModel.find({ 'savedListingIds.0': { $exists: true } })
        .select('authId savedListingIds createdAt updatedAt')
        .limit(5000)
        .lean(),
      BookingModel.find({})
        .select([
          'publicId',
          'renterId',
          'listingId',
          'status',
          'sourceType',
          'createdAt',
          'decidedAt',
          'completedAt',
        ].join(' '))
        .sort({ createdAt: -1 })
        .limit(5000)
        .lean(),
      ReviewModel.find({ authorRole: 'renter', status: 'published' })
        .select([
          'bookingId',
          'authorId',
          'authorRole',
          'listingId',
          'overallRating',
          'status',
          'createdAt',
          'updatedAt',
        ].join(' '))
        .sort({ createdAt: -1 })
        .limit(5000)
        .lean(),
    ]);
    const interactions = buildRecommendationInteractions({
      users: interactionUsers,
      bookings,
      reviews,
      includeDemoSeed: env.recommendationIncludeDemoSeed,
    });
    const recommendations = await aiClient.recommendItems({
      user_id: recommendationUserId(identity.authId),
      limit,
      candidates: candidates.map((item) => ({
        item_id: item.publicId,
        title: item.title,
        category: item.category,
        subcategory: item.subcategory,
        brand: item.brand,
        product_model: item.productModel,
        description: item.description,
        location: item.location,
        condition: item.condition ?? '',
        price: item.dailyPrice,
        rating: item.rating,
        popularity: item.reviewCount + (item.promoted ? 5 : 0),
        available: true,
      })),
      interactions: interactions.map(modelInteraction),
      context: {},
    });
    if (!Array.isArray(recommendations) || !recommendations.length) {
      return candidates.slice(0, limit).map((item) => ({
        ...item.toJSON(),
        recommendation: {
          available: false,
          adapter: 'marketplace-ordering-fallback-v1',
          reason: 'Personalized ranking is unavailable; active marketplace highlights are shown',
        },
      }));
    }
    const byId = new Map(candidates.map((item) => [item.publicId, item]));
    return recommendations.flatMap((recommendation) => {
      const item = byId.get(recommendation.item_id);
      return item ? [{ ...item.toJSON(), recommendation }] : [];
    });
  },

  async recommendPrice(input, identity) {
    const owner = await requireOwner(identity);
    const requestedProfile = input.itemProfile;
    const productIdentity = await resolveProductIdentity(requestedProfile);
    const profile = {
      ...requestedProfile,
      brand: productIdentity.brand,
      product_model: productIdentity.model,
      canonicalProductId: productIdentity.canonicalProductId,
      catalogBrandId: productIdentity.catalogBrandId,
      productMatchType: productIdentity.productMatchType,
      catalogSource: productIdentity.catalogSource,
      rental_duration_days: input.rentalDurationDays ?? 1,
    };
    const productMatch = {
      type: profile.productMatchType,
      brand: profile.brand,
      model: profile.product_model,
      canonicalProductId: profile.canonicalProductId,
      source: profile.catalogSource,
    };
    const evidenceStart = new Date(
      Date.now() - PRICING_EVIDENCE_WINDOW_DAYS * 24 * 60 * 60 * 1000,
    );
    const [activeCandidates, completedBookings, ownerRating, ownerCompletedRentals] =
      await Promise.all([
        ListingModel.find({
          status: 'active',
          category: profile.category,
          listingType: 'physical',
          ...(input.excludeListingId && {
            $nor: [{
              publicId: input.excludeListingId,
              ownerId: owner.authId,
            }],
          }),
        })
          .select(
            'publicId subcategory brand productModel canonicalProductId condition itemAgeYears location state dailyPrice updatedAt',
          )
          .sort({ updatedAt: -1 })
          .limit(PRICING_EVIDENCE_QUERY_LIMIT)
          .lean(),
      BookingModel.find({
        listingType: 'physical',
        status: 'completed',
        ...(env.pricingIncludeDemoSeed
          ? { sourceType: { $in: ['marketplace', 'demo_seed'] } }
          : { sourceType: { $ne: 'demo_seed' } }),
        paymentStatus: { $in: PRICING_COMPLETED_PAYMENT_STATUSES },
        'pricing.baseAmount': { $gt: 0 },
        $or: [
          { completedAt: { $gte: evidenceStart } },
          { completedAt: { $exists: false }, createdAt: { $gte: evidenceStart } },
        ],
      })
        .select('listingId startDate endDate pricing.baseAmount completedAt sourceType')
        .sort({ completedAt: -1 })
        .limit(PRICING_EVIDENCE_QUERY_LIMIT)
        .lean(),
      ReviewModel.aggregate([
        {
          $match: {
            subjectId: owner.authId,
            subjectRole: 'owner',
            status: 'published',
          },
        },
        {
          $group: {
            _id: null,
            average: { $avg: '$overallRating' },
            count: { $sum: 1 },
          },
        },
      ]),
      BookingModel.countDocuments({
        ownerId: owner.authId,
        status: 'completed',
        paymentStatus: { $in: PRICING_COMPLETED_PAYMENT_STATUSES },
      }),
    ]);
    const completedListingIds = [
      ...new Set(completedBookings.map((booking) => booking.listingId)),
    ];
    const completedListings = await ListingModel.find({
      publicId: { $in: completedListingIds },
      category: profile.category,
      listingType: 'physical',
    })
      .select('publicId subcategory brand productModel canonicalProductId condition itemAgeYears location state')
      .lean();
    const activeTier = selectComparableTier(activeCandidates, profile);
    const completedById = new Map(
      completedListings.map((listing) => [listing.publicId, listing]),
    );
    const completedCandidates = completedBookings.flatMap((booking) => {
      const listing = completedById.get(booking.listingId);
      if (!listing) return [];
      const dailyPrice = booking.pricing.baseAmount / rentalDays(booking);
      return Number.isFinite(dailyPrice) && dailyPrice > 0
        ? [{
            ...listing,
            dailyPrice,
            rentalDurationDays: rentalDays(booking),
            observedAt: booking.completedAt,
            sourceType: booking.sourceType ?? 'marketplace',
          }]
        : [];
    });
    const historicalTier = selectComparableTier(completedCandidates, profile);
    const activeEvidenceCounts = evidenceCounts(activeCandidates, profile);
    const historicalEvidenceCounts = evidenceCounts(completedCandidates, profile);
    const marketplaceCompletedCount = historicalTier.items.filter(
      (item) => item.sourceType !== 'demo_seed',
    ).length;
    const demoSeedCompletedCount = historicalTier.items.filter(
      (item) => item.sourceType === 'demo_seed',
    ).length;
    const activeStats = robustPriceStats(
      activeTier.items.map((listing) => listing.dailyPrice),
    );
    const historicalStats = robustPriceStats(
      historicalTier.items.map((listing) => listing.dailyPrice),
    );
    const evidenceDates = [
      ...activeTier.items.map((listing) => listing.updatedAt),
      ...historicalTier.items.map((listing) => listing.observedAt),
    ].filter(Boolean);
    const freshest = evidenceDates.length
      ? Math.max(...evidenceDates.map((date) => new Date(date).getTime()))
      : null;
    const marketEvidence = {
      comparable_active_count: activeStats.count,
      comparable_active_median: activeStats.median,
      comparable_active_mean: activeStats.mean,
      comparable_active_iqr: activeStats.iqr,
      historical_rental_count: historicalStats.count,
      historical_rental_median: historicalStats.median,
      historical_rental_mean: historicalStats.mean,
      historical_rental_iqr: historicalStats.iqr,
      exact_active_count: activeEvidenceCounts.exact,
      similar_active_count: activeEvidenceCounts.similar,
      exact_completed_rental_count: historicalEvidenceCounts.exact,
      similar_completed_rental_count: historicalEvidenceCounts.similar,
      marketplace_completed_rental_count: marketplaceCompletedCount,
      demo_seed_completed_rental_count: demoSeedCompletedCount,
      market_freshness_days: freshest === null
        ? null
        : Math.max(0, Math.floor((Date.now() - freshest) / 86_400_000)),
      demand_supply_ratio: historicalStats.count / Math.max(activeStats.count, 1),
      active_comparable_tier: activeTier.name,
      historical_comparable_tier: historicalTier.name,
      evidence_window_days: PRICING_EVIDENCE_WINDOW_DAYS,
    };
    const recommendation = await aiClient.recommendPrice({
      schema_version: 'renthub-price-v2',
      item_profile: profile,
      market_evidence: marketEvidence,
      rental_duration_days: input.rentalDurationDays ?? 1,
      owner_trust_score: owner.trustScore,
      owner_average_rating: ownerRating[0]?.average ?? 0,
      owner_completed_rentals: ownerCompletedRentals,
      prediction_month: new Date().getUTCMonth() + 1,
    });
    if (recommendation.available) {
      return { ...recommendation, product_match: productMatch };
    }
    const fallback = statisticalFallback(activeStats, historicalStats);
    if (!fallback) {
      return {
        ...recommendation,
        model_source: 'insufficient_data',
        evidence: marketEvidence,
        product_match: productMatch,
        warnings: [
          ...(recommendation.warnings ?? []),
          'Not enough current marketplace evidence for a statistical fallback.',
        ],
      };
    }
    const fallbackUsesHistory = historicalStats.count >= PRICING_FALLBACK_MIN_OBSERVATIONS;
    const fallbackStats = fallbackUsesHistory ? historicalStats : activeStats;
    const fallbackConfidence = statisticalFallbackConfidence(
      fallbackStats,
      marketEvidence.market_freshness_days,
      profile.productMatchType,
    );
    return {
      available: true,
      ...fallback,
      confidence: fallbackConfidence.score,
      confidence_label: fallbackConfidence.label,
      currency: 'MYR',
      adapter: 'market-statistical-fallback-v1',
      model_source: fallback.source,
      model_version: null,
      evidence: marketEvidence,
      product_match: productMatch,
      evaluation: {},
      explanation: [
        `The AI model was unavailable, so the ${fallback.source.replaceAll('_', ' ')} was used.`,
        `Evidence tier: ${fallbackUsesHistory ? historicalTier.name : activeTier.name}.`,
      ],
      warnings: [
        'This is a market-statistical fallback, not an AI prediction.',
        ...(recommendation.error ? [recommendation.error] : []),
      ],
      similar_listing_average: activeStats.mean,
      historical_average: historicalStats.mean,
    };
  },

  async list(query) {
    const { page, limit } = pageOptions(query);
    const filter = {};
    const platform = await PlatformSettingModel.findOne({ key: 'platform' })
      .select('categories')
      .lean();
    const activeCategories = platform?.categories
      ?.filter((category) => category.active)
      .map((category) => category.name);
    if (query.search?.trim()) {
      const pattern = escapedPattern(query.search.trim());
      filter.$or = [
        { title: pattern },
        { description: pattern },
        { location: pattern },
      ];
    }
    if (LISTING_CATEGORIES.includes(query.category)) {
      filter.category =
        activeCategories && !activeCategories.includes(query.category)
          ? { $in: [] }
          : query.category;
    } else if (activeCategories) {
      filter.category = { $in: activeCategories };
    }
    if (['physical', 'service'].includes(query.type)) filter.listingType = query.type;
    if (query.location?.trim()) filter.location = escapedPattern(query.location.trim());
    if (query.verified !== undefined) filter.verified = query.verified === 'true';
    if (query.promoted === 'true') {
      const now = new Date();
      filter['promotion.enabled'] = true;
      filter['promotion.startsAt'] = { $lte: now };
      filter['promotion.endsAt'] = { $gte: now };
    }
    if (query.minPrice !== undefined || query.maxPrice !== undefined) {
      filter.dailyPrice = {
        ...(query.minPrice !== undefined && { $gte: Number(query.minPrice) }),
        ...(query.maxPrice !== undefined && { $lte: Number(query.maxPrice) }),
      };
    }
    let unavailableIds = [];
    if (query.availableFrom && query.availableTo) {
      unavailableIds = await listingRepository.findUnavailableListingIds(
        new Date(query.availableFrom),
        new Date(query.availableTo),
      );
    }
    const [items, total] = await listingRepository.listPublic({
      page,
      limit,
      filter,
      unavailableIds,
      sort: {
        recommended: { promoted: -1, rating: -1, createdAt: -1 },
        price_asc: { dailyPrice: 1, createdAt: -1 },
        price_desc: { dailyPrice: -1, createdAt: -1 },
        rating: { rating: -1, reviewCount: -1, createdAt: -1 },
        newest: { createdAt: -1 },
        trust: { ownerTrustScore: -1, rating: -1, createdAt: -1 },
      }[query.sort ?? 'recommended'],
    });
    return { items, meta: { page, limit, total } };
  },

  async get(id) {
    const listing = await listingRepository.findPublicById(id);
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    return listing;
  },

  async create(input, identity) {
    const owner = await requireOwner(identity);
    await uploadService.assertOwnedReferences(identity, input.images, ['listing_image']);
    const normalizedInput = await withResolvedProductIdentity(input);
    return listingRepository.create({
      ...listingInput(normalizedInput),
      ownerId: owner.authId,
      ownerName: owner.displayName,
      ownerTrustScore: owner.trustScore,
      verified: owner.verification.status === 'approved',
      status: 'draft',
    });
  },

  async listMine(identity, query) {
    await requireOwner(identity);
    const { page, limit } = pageOptions(query);
    const status = LISTING_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await listingRepository.listOwned({
      ownerId: identity.authId,
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async listAdmin(query) {
    const { page, limit } = pageOptions(query);
    const status = LISTING_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await listingRepository.listAdmin({
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async update(id, input, identity) {
    const listing = await requireOwnedListing(id, identity);
    await uploadService.assertOwnedReferences(identity, input.images, ['listing_image']);
    if (listing.status === 'pending_review') {
      throw new AppError(
        'A listing cannot be edited while under review',
        409,
        'INVALID_LISTING_STATE',
      );
    }
    const normalizedInput = await withResolvedProductIdentity(input, listing);
    listing.set(listingInput({
      ...normalizedInput,
      listingType: listing.listingType,
    }));
    if (listing.status === 'active' || listing.status === 'rejected') {
      listing.status = 'draft';
      listing.moderationReason = '';
    }
    await listing.save();
    return listing;
  },

  async submit(id, identity) {
    const listing = await requireOwnedListing(id, identity);
    if (!['draft', 'rejected'].includes(listing.status)) {
      throw new AppError(
        'Only draft or rejected listings can be submitted',
        409,
        'INVALID_LISTING_STATE',
      );
    }
    if (listing.listingType === 'physical' && listing.images.length < 3) {
      throw new AppError(
        'At least three item images are required before submission',
        400,
        'ITEM_IMAGES_REQUIRED',
      );
    }
    if (listing.listingType === 'physical') {
      const images = await uploadService.readOwnedReferences(
        identity,
        listing.images,
        ['listing_image'],
      );
      listing.itemVerification = await aiClient.verifyItem({
        images,
        category: listing.category,
        listingType: listing.listingType,
      });
      if (
        env.aiEnforcementMode === 'strict' &&
        listing.itemVerification.outcome !== 'approved'
      ) {
        throw new AppError(
          'Item verification must pass before submission',
          409,
          'ITEM_VERIFICATION_REQUIRED',
          listing.itemVerification,
        );
      }
    }
    listing.status = 'pending_review';
    listing.moderationReason = '';
    await listing.save();
    return listing;
  },

  async deactivate(id, identity) {
    const listing = await requireOwnedListing(id, identity);
    listing.status = 'inactive';
    await listing.save();
    return listing;
  },

  async moderate(id, status, reason) {
    const listing = await listingRepository.findById(id);
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    if (listing.status !== 'pending_review') {
      throw new AppError(
        'Only pending listings can be moderated',
        409,
        'INVALID_LISTING_STATE',
      );
    }
    if (status === 'rejected' && !reason?.trim()) {
      throw new AppError('A rejection reason is required', 400, 'REASON_REQUIRED');
    }
    listing.status = status;
    listing.moderationReason = status === 'rejected' ? reason.trim() : '';
    await listing.save();
    return listing;
  },

  async getAvailability(id) {
    const listing = await listingRepository.findPublicById(id);
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    return (
      (await listingRepository.findAvailability(listing.publicId)) ?? {
        listingId: listing.publicId,
        unavailableRanges: [],
        weeklyHours: [],
        minimumNoticeHours: 0,
        bufferHours: 0,
      }
    );
  },

  async setAvailability(id, input, identity) {
    const listing = await requireOwnedListing(id, identity);
    const data = {
      unavailableRanges: input.unavailableRanges ?? [],
      weeklyHours: listing.listingType === 'service' ? input.weeklyHours ?? [] : [],
      minimumNoticeHours: input.minimumNoticeHours ?? 0,
      bufferHours: input.bufferHours ?? 0,
    };
    return listingRepository.saveAvailability(
      listing.publicId,
      identity.authId,
      data,
    );
  },

  async setPromotion(id, input, identity) {
    const listing = await requireOwnedListing(id, identity);
    listing.promotion = {
      enabled: input.enabled ?? true,
      label: input.label,
      discountPercent: input.discountPercent,
      startsAt: input.startsAt,
      endsAt: input.endsAt,
    };
    listing.promoted = input.enabled ?? true;
    await listing.save();
    return listing;
  },

  async clearPromotion(id, identity) {
    const listing = await requireOwnedListing(id, identity);
    listing.promotion = undefined;
    listing.promoted = false;
    await listing.save();
    return listing;
  },

  async setBundle(id, input, identity) {
    const listing = await requireOwnedListing(id, identity);
    if (listing.listingType !== 'physical') {
      throw new AppError(
        'Only physical items can use bundles',
        400,
        'INVALID_BUNDLE_TYPE',
      );
    }
    const listingIds = [...new Set(input.listingIds)];
    if (!listingIds.includes(listing.publicId)) {
      throw new AppError(
        'Bundle must include the selected listing',
        400,
        'INVALID_BUNDLE',
      );
    }
    const ownedItems = await ListingModel.find({
      publicId: { $in: listingIds },
      ownerId: identity.authId,
      listingType: 'physical',
      status: 'active',
    }).select('publicId');
    if (ownedItems.length !== listingIds.length) {
      throw new AppError(
        'Every bundle item must be an active physical listing owned by you',
        400,
        'INVALID_BUNDLE_ITEMS',
      );
    }
    listing.bundleOffer = {
      active: input.active ?? true,
      title: input.title,
      listingIds,
      discountPercent: input.discountPercent,
    };
    await listing.save();
    return listing;
  },

  async clearBundle(id, identity) {
    const listing = await requireOwnedListing(id, identity);
    listing.bundleOffer = undefined;
    await listing.save();
    return listing;
  },
};
