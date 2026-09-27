import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { adminModule } from '../admin/index.js';
import { notifyUser } from '../communication/notification.service.js';
import { ListingModel } from '../listing/listing.model.js';
import { ACCOUNT_STATUSES, USER_ROLES } from './user.model.js';
import { userRepository } from './user.repository.js';
import { uploadService } from '../upload/upload.service.js';
import { aiClient } from '../../integrations/aiClient.js';

function preferredRole(roles) {
  return roles.includes('renter') ? 'renter' : roles[0];
}

function identityData(identity) {
  const claimedRoles = Array.isArray(identity.roles) ? identity.roles : [];
  const roles = claimedRoles.filter((role) => USER_ROLES.includes(role));
  if (!roles.length) roles.push('renter');
  return {
    authId: identity.authId,
    email: identity.email ?? `${identity.authId}@mock.renthub.my`,
    displayName: identity.displayName ?? 'RentHub User',
    roles: [...new Set(roles)],
  };
}

async function requireCurrentUser(identity) {
  const user = await userRepository.findByAuthId(identity.authId);
  if (!user) {
    throw new AppError(
      'User profile has not been created. Start a session first.',
      404,
      'USER_PROFILE_NOT_FOUND',
    );
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(
      `Account is ${user.accountStatus}`,
      403,
      'ACCOUNT_RESTRICTED',
    );
  }
  return user;
}

export const userService = {
  async startSession(identity) {
    const data = identityData(identity);
    let user = await userRepository.findByAuthId(data.authId);
    if (!user) {
      user = await userRepository.create({
        ...data,
        activeRole: preferredRole(data.roles),
        lastLoginAt: new Date(),
      });
      return { user, created: true };
    }
    if (user.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${user.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    user.roles = data.roles;
    user.email = data.email;
    if (!user.roles.includes(user.activeRole)) {
      user.activeRole = preferredRole(data.roles);
    }
    user.lastLoginAt = new Date();
    await user.save();
    return { user, created: false };
  },

  getMe: requireCurrentUser,

  async updateMe(identity, input) {
    const user = await requireCurrentUser(identity);
    if (input.avatarUrl?.startsWith('/api/v1/uploads/')) {
      await uploadService.assertOwnedReferences(identity, [input.avatarUrl], ['avatar']);
    }
    const allowed = {
      ...(input.displayName !== undefined && { displayName: input.displayName }),
      ...(input.phone !== undefined && { phone: input.phone }),
      ...(input.avatarUrl !== undefined && { avatarUrl: input.avatarUrl }),
      ...(input.addresses !== undefined && { addresses: input.addresses }),
      ...(input.settings !== undefined && { settings: input.settings }),
    };
    user.set(allowed);
    await user.save();
    return user;
  },

  async selectRole(identity, role) {
    const user = await requireCurrentUser(identity);
    if (!user.roles.includes(role)) {
      throw new AppError('Role is not assigned to this user', 403, 'ROLE_NOT_ASSIGNED');
    }
    user.activeRole = role;
    await user.save();
    return user;
  },

  async submitVerification(identity, input) {
    const user = await requireCurrentUser(identity);
    await uploadService.assertOwnedReferences(
      identity,
      input.documentRefs,
      ['verification_document'],
    );
    if (user.verification.status === 'pending') {
      throw new AppError(
        'Identity verification is already pending',
        409,
        'VERIFICATION_PENDING',
      );
    }
    if (user.verification.status === 'approved') {
      throw new AppError(
        'Identity is already verified',
        409,
        'ALREADY_VERIFIED',
      );
    }
    const images = await uploadService.readOwnedReferences(
      identity,
      input.documentRefs,
      ['verification_document'],
    );
    const analysis = await aiClient.verifyDocument({
      images,
      documentType: input.documentType,
      profileName: user.displayName,
    });
    user.verification = {
      status: 'pending',
      tier: 'none',
      documentType: input.documentType,
      documentRefs: input.documentRefs,
      ocrResult: analysis,
      reason: '',
      submittedAt: new Date(),
      reviewedAt: undefined,
      reviewedBy: '',
    };
    await user.save();
    return user;
  },

  async reviewVerification(id, input, identity) {
    const user = await userRepository.findById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (user.verification.status !== 'pending') {
      throw new AppError(
        'Only pending verification submissions can be reviewed',
        409,
        'INVALID_VERIFICATION_STATE',
      );
    }
    if (input.status !== 'approved' && !input.reason?.trim()) {
      throw new AppError(
        'A review reason is required',
        400,
        'REASON_REQUIRED',
      );
    }
    user.verification.status = input.status;
    user.verification.tier =
      input.status === 'approved' ? (input.tier ?? 'basic') : 'none';
    user.verification.reason = input.reason?.trim() ?? '';
    user.verification.reviewedAt = new Date();
    user.verification.reviewedBy = identity.authId;
    user.verification.ocrResult = {
      ...(user.verification.ocrResult ?? {}),
      administratorReview: {
        status: input.status,
        reviewedBy: identity.authId,
        reviewedAt: new Date(),
      },
    };
    await user.save();
    if (user.roles.includes('owner')) {
      await ListingModel.updateMany(
        { ownerId: user.authId },
        { verified: input.status === 'approved' },
      );
    }
    await Promise.all([
      adminModule.service.create({
        actorId: identity.authId,
        action: `verification.${input.status}`,
        targetType: 'user',
        targetId: user.authId,
        metadata: {
          tier: user.verification.tier,
          reason: user.verification.reason,
        },
        createdBy: identity.authId,
      }),
      notifyUser({
        userId: user.authId,
        category: 'verification',
        type: `verification_${input.status}`,
        title:
          input.status === 'approved'
            ? 'Identity verification approved'
            : 'Identity verification needs attention',
        body:
          input.status === 'approved'
            ? `Your ${user.verification.tier} verification is active.`
            : user.verification.reason,
        entityType: 'user',
        entityId: user.authId,
      }),
    ]);
    return user;
  },

  async blockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    if (targetId === user.authId || targetId === user.id) {
      throw new AppError('You cannot block your own account', 400, 'INVALID_TARGET');
    }
    const target = await userRepository.findPublicById(targetId);
    if (!target) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (!user.blockedUserIds.includes(target.authId)) {
      user.blockedUserIds.push(target.authId);
      await user.save();
    }
    return user;
  },

  async unblockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    user.blockedUserIds = user.blockedUserIds.filter((id) => id !== targetId);
    await user.save();
    return user;
  },

  async savedListings(identity) {
    const user = await requireCurrentUser(identity);
    return ListingModel.find({
      publicId: { $in: user.savedListingIds },
      status: 'active',
    }).sort({ updatedAt: -1 });
  },

  async saveListing(identity, listingId) {
    const user = await requireCurrentUser(identity);
    const listing = await ListingModel.findOne({ publicId: listingId, status: 'active' });
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    if (!user.savedListingIds.includes(listingId)) {
      if (user.savedListingIds.length >= 100) {
        throw new AppError('Wishlist limit reached', 409, 'WISHLIST_LIMIT');
      }
      user.savedListingIds.push(listingId);
      await user.save();
    }
    return listing;
  },

  async removeSavedListing(identity, listingId) {
    const user = await requireCurrentUser(identity);
    user.savedListingIds = user.savedListingIds.filter((id) => id !== listingId);
    await user.save();
    return { listingId, saved: false };
  },

  async comparison(identity) {
    const user = await requireCurrentUser(identity);
    return ListingModel.find({
      publicId: { $in: user.comparisonListingIds },
      status: 'active',
    });
  },

  async updateComparison(identity, listingIds) {
    const user = await requireCurrentUser(identity);
    const uniqueIds = [...new Set(listingIds)];
    const listings = await ListingModel.find({
      publicId: { $in: uniqueIds },
      status: 'active',
    });
    if (listings.length !== uniqueIds.length) {
      throw new AppError(
        'Every comparison item must be an active listing',
        400,
        'INVALID_COMPARISON',
      );
    }
    user.comparisonListingIds = uniqueIds;
    await user.save();
    const byId = new Map(listings.map((listing) => [listing.publicId, listing]));
    return uniqueIds.map((id) => byId.get(id));
  },

  async getPublic(id) {
    if (!mongoose.isValidObjectId(id) && !/^u-[a-z0-9-]+$/i.test(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    const user = await userRepository.findPublicById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    return user;
  },

  async list(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);
    const [items, total] = await userRepository.list({
      page,
      limit,
      search: query.search?.trim(),
      role: USER_ROLES.includes(query.role) ? query.role : undefined,
      status: ACCOUNT_STATUSES.includes(query.status) ? query.status : undefined,
    });
    return { items, meta: { page, limit, total } };
  },

  async changeAccountStatus(id, status, reason) {
    if (!mongoose.isValidObjectId(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    if (!ACCOUNT_STATUSES.includes(status)) {
      throw new AppError('Invalid account status', 400, 'INVALID_STATUS');
    }
    if (status !== 'active' && !reason?.trim()) {
      throw new AppError('A reason is required', 400, 'REASON_REQUIRED');
    }
    const user = await userRepository.updateById(id, {
      accountStatus: status,
      accountStatusReason: status === 'active' ? '' : reason.trim(),
    });
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    return user;
  },
};
