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
import { externalMarketComparables } from './marketPriceComparables.js';

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

function escapedPattern(value) {
  return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

function exactPattern(value) {
  const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^${escaped}$`, 'i');
}

const categoryPriceFallback = {
  Clothing: 28,
  Vehicles: 165,
  Devices: 75,
  Books: 12,
  Equipment: 95,
};

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
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
    const [candidates, bookings, reviews] = await Promise.all([
      ListingModel.find({ status: 'active', ownerId: { $ne: identity.authId } })
        .sort({ promoted: -1, rating: -1, createdAt: -1 })
        .limit(200),
      BookingModel.find({})
        .select('renterId listingId status')
        .limit(5000)
        .lean(),
      ReviewModel.find({ authorRole: 'renter', status: 'published' })
        .select('authorId listingId overallRating')
        .limit(5000)
        .lean(),
    ]);
    const interactionMap = new Map();
    for (const listingId of user.savedListingIds) {
      interactionMap.set(`${identity.authId}:${listingId}`, {
        userId: identity.authId,
        itemId: listingId,
        rating: 4,
      });
    }
    for (const booking of bookings) {
      interactionMap.set(`${booking.renterId}:${booking.listingId}`, {
        userId: booking.renterId,
        itemId: booking.listingId,
        rating: booking.status === 'completed' ? 4.5 : 4.2,
      });
    }
    for (const review of reviews) {
      interactionMap.set(`${review.authorId}:${review.listingId}`, {
        userId: review.authorId,
        itemId: review.listingId,
        rating: review.overallRating,
      });
    }
    const recommendations = await aiClient.recommendItems({
      user_id: identity.authId,
      limit,
      candidates: candidates.map((item) => ({
        item_id: item.publicId,
        title: item.title,
        category: item.category,
        description: item.description,
        location: item.location,
        condition: item.condition ?? '',
        price: item.dailyPrice,
        rating: item.rating,
        popularity: item.reviewCount + (item.promoted ? 5 : 0),
        available: true,
      })),
      interactions: [...interactionMap.values()].map((interaction) => ({
        user_id: interaction.userId,
        item_id: interaction.itemId,
        rating: interaction.rating,
      })),
      context: {},
    });
    if (!Array.isArray(recommendations) || !recommendations.length) {
      return candidates.slice(0, limit).map((item) => ({
        ...item.toJSON(),
        recommendation: {
          available: false,
          reason: 'AI ranking is unavailable; marketplace ordering is shown',
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
    const profile = input.itemProfile;
    const broadSimilarFilter = {
      status: 'active',
      category: profile.category,
      listingType: 'physical',
      ...(profile.state && { state: profile.state }),
    };
    const exactSimilarFilter = {
      ...broadSimilarFilter,
      ...(profile.subcategory && { subcategory: exactPattern(profile.subcategory) }),
      ...(profile.brand && { brand: exactPattern(profile.brand) }),
      ...(profile.product_model && { productModel: exactPattern(profile.product_model) }),
      ...(profile.condition && { condition: profile.condition }),
    };
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const [similar, completedBookings, ownerRating] = await Promise.all([
      ListingModel.aggregate([
        { $match: exactSimilarFilter },
        { $group: { _id: null, average: { $avg: '$dailyPrice' }, count: { $sum: 1 } } },
      ]),
      BookingModel.find({
        listingType: 'physical',
        status: 'completed',
        createdAt: { $gte: ninetyDaysAgo },
      })
        .select('listingId startDate endDate pricing.baseAmount')
        .limit(5000)
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
    ]);
    const completedListingIds = [
      ...new Set(completedBookings.map((booking) => booking.listingId)),
    ];
    const completedListings = await ListingModel.find({
      publicId: { $in: completedListingIds },
      category: profile.category,
      listingType: 'physical',
      ...(profile.state && { state: profile.state }),
      ...(profile.subcategory && { subcategory: exactPattern(profile.subcategory) }),
      ...(profile.brand && { brand: exactPattern(profile.brand) }),
      ...(profile.product_model && { productModel: exactPattern(profile.product_model) }),
      ...(profile.condition && { condition: profile.condition }),
    })
      .select('publicId')
      .lean();
    const eligibleIds = new Set(
      completedListings.map((listing) => listing.publicId),
    );
    const historicalDailyPrices = completedBookings
      .filter((booking) => eligibleIds.has(booking.listingId))
      .map((booking) => booking.pricing.baseAmount / rentalDays(booking));
    const fallback = categoryPriceFallback[profile.category] ?? 50;
    const similarAverage = similar[0]?.average ?? fallback;
    const historicalAverage = historicalDailyPrices.length
      ? historicalDailyPrices.reduce((sum, value) => sum + value, 0) /
        historicalDailyPrices.length
      : fallback;
    const supplyCount = similar[0]?.count ?? 0;
    const demandCount = historicalDailyPrices.length;
    const external = externalMarketComparables(
      profile,
      input.rentalDurationDays ?? 1,
    );
    const supplyDemandRatio = clamp(
      0.85 + demandCount / Math.max(supplyCount * 8, 8),
      0.75,
      1.45,
    );
    const recommendation = await aiClient.recommendPrice({
      item_profile: profile,
      similar_active_average: similarAverage,
      historical_completed_average: historicalAverage,
      supply_demand_ratio: supplyDemandRatio,
      seasonal_day_factor: 1,
      rental_duration_days: input.rentalDurationDays ?? 1,
      owner_trust_score: owner.trustScore,
      owner_average_rating: ownerRating[0]?.average ?? 0,
    });
    if (recommendation.available && external.adjustedAverage !== null) {
      const modelSuggestion = Number(recommendation.suggested_daily_price);
      const hasDirectRentalEvidence = external.directRentalCount > 0;
      const externalWeight = hasDirectRentalEvidence
        ? external.count >= 2
          ? 0.75
          : 0.65
        : external.count >= 2
          ? 0.5
          : 0.4;
      const blended =
        external.adjustedAverage * externalWeight +
        modelSuggestion * (1 - externalWeight);
      const spread = Math.max(
        blended * (external.count >= 2 ? 0.1 : 0.14),
        Number(recommendation.upper_bound ?? blended) - modelSuggestion,
      );
      recommendation.suggested_daily_price = Math.round(blended * 100) / 100;
      recommendation.lower_bound = Math.round(Math.max(1, blended - spread) * 100) / 100;
      recommendation.upper_bound = Math.round((blended + spread) * 100) / 100;
      recommendation.adapter = `${recommendation.adapter}+market-comparables-v1`;
      recommendation.explanation = [
        ...(hasDirectRentalEvidence
          ? [
              `Matched ${external.directRentalCount} dated Malaysian short-term rental comparable(s) for ${profile.brand} ${profile.product_model}`,
            ]
          : [
              `No exact rental listing was available; ${external.resaleDerivedCount} dated Malaysian resale comparable(s) were converted to a daily rental anchor`,
            ]),
        `Category, condition, item age and ${input.rentalDurationDays ?? 1}-day duration were applied to the market anchor`,
        ...(recommendation.explanation ?? []),
      ];
    }
    const localCoverage =
      (supplyCount > 0 ? 0.5 : 0) + (demandCount > 0 ? 0.5 : 0);
    const externalCoverage = external.directRentalCount
      ? external.count >= 2
        ? 1
        : 0.5
      : external.resaleDerivedCount >= 2
        ? 0.5
        : external.resaleDerivedCount === 1
          ? 0.25
          : 0;
    const marketCoverage = Math.max(localCoverage, externalCoverage);
    const confidence = recommendation.available
      ? Math.round(
          recommendation.confidence * (0.7 + 0.3 * marketCoverage) * 10_000,
        ) / 10_000
      : recommendation.confidence;
    return {
      ...recommendation,
      confidence,
      explanation: [
        ...(supplyCount === 0
          ? ['No active local comparable was available; a category baseline was used']
          : []),
        ...(demandCount === 0
          ? ['No recent matching completed rental was available; a category baseline was used']
          : []),
        ...(recommendation.explanation ?? []),
      ],
      market_context: {
        activeComparableCount: supplyCount,
        completedRentalCount: demandCount,
        supplyDemandRatio,
        ownerReviewCount: ownerRating[0]?.count ?? 0,
        externalComparableCount: external.count,
        externalComparableAverage: external.adjustedAverage,
        directRentalComparableCount: external.directRentalCount ?? 0,
        resaleDerivedComparableCount: external.resaleDerivedCount ?? 0,
        externalEvidenceTypes: external.evidenceTypes ?? [],
        externalSources: external.sources,
        coverage: marketCoverage,
      },
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
    return listingRepository.create({
      ...listingInput(input),
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
    listing.set(listingInput({ ...input, listingType: listing.listingType }));
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
