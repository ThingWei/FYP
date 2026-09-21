import { AppError } from '../../core/errors.js';
import { PlatformSettingModel } from '../admin/platformSetting.model.js';
import { UserModel } from '../user/user.model.js';
import {
  LISTING_CATEGORIES,
  LISTING_STATUSES,
  ListingModel,
} from './listing.model.js';
import { listingRepository } from './listing.repository.js';

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

function escapedPattern(value) {
  return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

function listingInput(input) {
  const listingType =
    input.listingType ?? (input.category === 'Services' ? 'service' : 'physical');
  return {
    ...(input.title !== undefined && { title: input.title }),
    ...(input.description !== undefined && { description: input.description }),
    ...(input.category !== undefined && { category: input.category }),
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
