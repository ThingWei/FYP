import mongoose from 'mongoose';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { AppError } from '../../core/errors.js';
import { adminModule } from '../admin/index.js';
import { notifyUser } from '../communication/notification.service.js';
import { DeviceRegistrationModel } from '../communication/deviceRegistration.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ACCOUNT_STATUSES, USER_ROLES, UserModel } from './user.model.js';
import { PasswordResetModel } from './passwordReset.model.js';
import { userRepository } from './user.repository.js';
import { uploadService } from '../upload/upload.service.js';
import { aiClient } from '../../integrations/aiClient.js';
import { disconnectUser } from '../../socket/eventBus.js';
import { env } from '../../config/env.js';
import { hashPassword, verifyPassword } from '../../core/password.js';
import { emailClient } from '../../integrations/emailClient.js';
import { localSessionService } from './localSession.service.js';
import {
  MARKETPLACE_ROLES,
  isMarketplaceRole,
  normalizeStoredUserRoles,
  normalizeTrustedIdentityRoles,
} from './rolePolicy.js';

const OPEN_BOOKING_STATUSES = ['pending', 'approved', 'active', 'disputed'];
const OPEN_RENTAL_STATUSES = [
  'scheduled',
  'active',
  'overdue',
  'return_submitted',
  'completion_pending',
  'disputed',
];
const OPEN_DISPUTE_STATUSES = [
  'open',
  'awaiting_response',
  'under_review',
  'more_evidence_required',
  'escalated',
];

function preferredRole(roles) {
  return roles.includes('renter') ? 'renter' : roles[0];
}

const passwordResetResponse = () => ({
  message: 'If an eligible account exists, a reset code has been sent.',
  expiresInMinutes: env.passwordResetTtlMinutes,
});

function resetCodeHash(email, code) {
  return createHmac('sha256', env.passwordResetSecret)
    .update(`${email}:${code}`)
    .digest('hex');
}

function resetCodeMatches(actual, expected) {
  const actualBuffer = Buffer.from(actual, 'hex');
  const expectedBuffer = Buffer.from(expected, 'hex');
  return (
    actualBuffer.length === expectedBuffer.length &&
    timingSafeEqual(actualBuffer, expectedBuffer)
  );
}

function invalidResetCode() {
  return new AppError(
    'The reset code is invalid or has expired. Request a new code and try again.',
    400,
    'INVALID_RESET_CODE',
  );
}

function identityData(identity) {
  return {
    authId: identity.authId,
    email: identity.email ?? `${identity.authId}@mock.renthub.my`,
    displayName: identity.displayName ?? 'RentHub User',
    roles: normalizeTrustedIdentityRoles(identity.roles),
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
  async localLogin({ email, password, role }, metadata) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local login is disabled', 404, 'NOT_FOUND');
    }
    const user = await userRepository.findByEmailWithPassword(email);
    const valid = user?.passwordHash
      ? await verifyPassword(password, user.passwordHash)
      : false;
    if (!user || !valid) {
      throw new AppError(
        'Incorrect email or password',
        401,
        'INVALID_CREDENTIALS',
      );
    }
    if (user.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${user.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    const normalized = normalizeStoredUserRoles(user.roles, user.activeRole);
    user.roles = normalized.roles;
    user.activeRole = normalized.activeRole;
    if (!user.roles.includes(role)) {
      throw new AppError(
        `This account does not have the ${role} role`,
        403,
        'FORBIDDEN',
      );
    }
    user.activeRole = role;
    user.lastLoginAt = new Date();
    await user.save();
    return ['local', 'hybrid'].includes(env.authMode)
      ? localSessionService.create(user, metadata)
      : user;
  },

  async localRegister({ displayName, email, password, role }, metadata) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local registration is disabled', 404, 'NOT_FOUND');
    }
    if (await userRepository.findByEmailWithPassword(email)) {
      throw new AppError(
        'An account with this email already exists',
        409,
        'DUPLICATE_RECORD',
      );
    }
    const suffix = new mongoose.Types.ObjectId().toString();
    const user = await userRepository.create({
      authId: `u-${suffix}`,
      email,
      passwordHash: await hashPassword(password),
      displayName,
      roles: [...MARKETPLACE_ROLES],
      activeRole: role,
      lastLoginAt: new Date(),
    });
    return ['local', 'hybrid'].includes(env.authMode)
      ? localSessionService.create(user, metadata)
      : user;
  },

  async localRefresh({ refreshToken }, metadata) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local refresh is disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.refresh(refreshToken, metadata);
  },

  async localLogout(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local logout is disabled', 404, 'NOT_FOUND');
    }
    await localSessionService.revoke(identity.sessionId);
    return { signedOut: true };
  },

  async localSessions(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.list(identity);
  },

  async revokeLocalSession(identity, sessionId) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.revokeForUser(identity, sessionId);
  },

  async revokeOtherLocalSessions(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.revokeOthers(identity);
  },

  async requestLocalPasswordReset({ email }) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local password reset is disabled', 404, 'NOT_FOUND');
    }
    try {
      emailClient.assertConfigured();
    } catch {
      throw new AppError(
        'Password-reset email is temporarily unavailable. Please contact support.',
        503,
        'EMAIL_NOT_CONFIGURED',
      );
    }
    const normalizedEmail = email.toLowerCase();
    const cooldownStartedAt = new Date(
      Date.now() - env.passwordResetCooldownSeconds * 1000,
    );
    const recent = await PasswordResetModel.exists({
      email: normalizedEmail,
      consumedAt: null,
      createdAt: { $gte: cooldownStartedAt },
    });
    if (recent) return passwordResetResponse();

    const user = await userRepository.findByEmailWithPassword(normalizedEmail);
    if (!user || !user.passwordHash || user.accountStatus !== 'active') {
      return passwordResetResponse();
    }

    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await PasswordResetModel.deleteMany({ email: normalizedEmail });
    const reset = await PasswordResetModel.create({
      userId: user._id,
      email: normalizedEmail,
      codeHash: resetCodeHash(normalizedEmail, code),
      expiresAt: new Date(
        Date.now() + env.passwordResetTtlMinutes * 60 * 1000,
      ),
    });
    try {
      await emailClient.sendPasswordResetCode({
        email: normalizedEmail,
        displayName: user.displayName,
        code,
      });
    } catch (error) {
      await PasswordResetModel.deleteOne({ _id: reset._id });
      console.error('Password-reset email provider rejected the request:', error.message);
      throw new AppError(
        'The password-reset email could not be sent. Please try again later.',
        502,
        'EMAIL_DELIVERY_FAILED',
      );
    }
    return passwordResetResponse();
  },

  async confirmLocalPasswordReset({ email, code, password }) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local password reset is disabled', 404, 'NOT_FOUND');
    }
    if (!env.passwordResetSecret) throw invalidResetCode();
    const normalizedEmail = email.toLowerCase();
    const reset = await PasswordResetModel.findOne({
      email: normalizedEmail,
      consumedAt: null,
      expiresAt: { $gt: new Date() },
      attempts: { $lt: env.passwordResetMaxAttempts },
    })
      .sort({ createdAt: -1 })
      .select('+codeHash');
    if (!reset) throw invalidResetCode();

    reset.attempts += 1;
    await reset.save();
    const suppliedHash = resetCodeHash(normalizedEmail, code);
    if (!resetCodeMatches(suppliedHash, reset.codeHash)) {
      throw invalidResetCode();
    }

    const claimed = await PasswordResetModel.findOneAndUpdate(
      { _id: reset._id, consumedAt: null },
      { consumedAt: new Date() },
      { new: true },
    );
    if (!claimed) throw invalidResetCode();
    const user = await UserModel.findById(reset.userId).select('+passwordHash');
    if (!user || user.accountStatus !== 'active') throw invalidResetCode();
    user.passwordHash = await hashPassword(password);
    user.accessRevokedAt = new Date();
    await user.save();
    await Promise.all([
      PasswordResetModel.deleteMany({ userId: user._id }),
      localSessionService.revokeAllForUser(user._id),
    ]);
    disconnectUser(user.authId);
    return { message: 'Your password has been updated. You can now sign in.' };
  },

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
    normalizeStoredUserRoles(user.roles, user.activeRole);
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

  async deactivateMe(identity, reason) {
    const user = await requireCurrentUser(identity);
    const participant = {
      $or: [{ renterId: user.authId }, { ownerId: user.authId }],
    };
    const disputeParticipant = {
      $or: [{ raisedById: user.authId }, { respondentId: user.authId }],
    };
    const [openBookings, openRentals, openDisputes] = await Promise.all([
      BookingModel.countDocuments({
        ...participant,
        status: { $in: OPEN_BOOKING_STATUSES },
      }),
      RentalModel.countDocuments({
        ...participant,
        status: { $in: OPEN_RENTAL_STATUSES },
      }),
      DisputeModel.countDocuments({
        ...disputeParticipant,
        status: { $in: OPEN_DISPUTE_STATUSES },
      }),
    ]);
    if (openBookings || openRentals || openDisputes) {
      throw new AppError(
        'Resolve active bookings, rentals, and disputes before deactivating your account.',
        409,
        'ACCOUNT_HAS_OPEN_OBLIGATIONS',
      );
    }
    if (
      user.roles.includes('admin') &&
      (await user.constructor.countDocuments({
        roles: 'admin',
        accountStatus: 'active',
      })) <= 1
    ) {
      throw new AppError(
        'The final active administrator cannot deactivate their account.',
        409,
        'LAST_ACTIVE_ADMIN',
      );
    }
    const now = new Date();
    user.accountStatus = 'deactivated';
    user.accountStatusReason = reason.trim();
    user.accountStatusChangedAt = now;
    user.accountStatusChangedBy = user.authId;
    user.deactivatedAt = now;
    user.deactivatedBy = user.authId;
    user.accessRevokedAt = now;
    await user.save();
    await Promise.all([
      ListingModel.updateMany(
        { ownerId: user.authId, status: { $in: ['active', 'pending_review'] } },
        { status: 'inactive' },
      ),
      DeviceRegistrationModel.deleteMany({ userId: user.authId }),
      localSessionService.revokeAllForUser(user._id),
      adminModule.service.create({
        actorId: user.authId,
        action: 'account.self_deactivated',
        targetType: 'user',
        targetId: user.authId,
        metadata: { reason: user.accountStatusReason },
        createdBy: user.authId,
      }),
    ]);
    disconnectUser(user.authId);
    return {
      accountStatus: user.accountStatus,
      deactivatedAt: user.deactivatedAt,
    };
  },

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
    const normalized = normalizeStoredUserRoles(user.roles, user.activeRole);
    user.roles = normalized.roles;
    user.activeRole = normalized.activeRole;
    if (!isMarketplaceRole(role) || user.roles.includes('admin')) {
      throw new AppError(
        'Role switching is available only to marketplace accounts',
        403,
        'ROLE_SWITCH_NOT_AVAILABLE',
      );
    }
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

  async changeAccountStatus(id, status, reason, identity) {
    if (!mongoose.isValidObjectId(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    if (!ACCOUNT_STATUSES.includes(status)) {
      throw new AppError('Invalid account status', 400, 'INVALID_STATUS');
    }
    if (status !== 'active' && !reason?.trim()) {
      throw new AppError('A reason is required', 400, 'REASON_REQUIRED');
    }
    const user = await userRepository.findById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (status !== 'active' && user.authId === identity.authId) {
      throw new AppError(
        'Administrators cannot restrict their own account from this screen.',
        409,
        'SELF_RESTRICTION_NOT_ALLOWED',
      );
    }
    if (
      status !== 'active' &&
      user.roles.includes('admin') &&
      (await user.constructor.countDocuments({
        roles: 'admin',
        accountStatus: 'active',
      })) <= 1
    ) {
      throw new AppError(
        'The final active administrator cannot be restricted.',
        409,
        'LAST_ACTIVE_ADMIN',
      );
    }
    const previousStatus = user.accountStatus;
    const now = new Date();
    user.accountStatus = status;
    user.accountStatusReason = status === 'active' ? '' : reason.trim();
    user.accountStatusChangedAt = now;
    user.accountStatusChangedBy = identity.authId;
    if (status === 'active') user.reactivatedAt = now;
    if (status === 'deactivated') {
      user.deactivatedAt = now;
      user.deactivatedBy = identity.authId;
    }
    if (status !== 'active') user.accessRevokedAt = now;
    await user.save();
    if (status !== 'active') {
      await Promise.all([
        ListingModel.updateMany(
          {
            ownerId: user.authId,
            status: { $in: ['active', 'pending_review'] },
          },
          { status: 'inactive' },
        ),
        DeviceRegistrationModel.deleteMany({ userId: user.authId }),
        localSessionService.revokeAllForUser(user._id),
      ]);
      disconnectUser(user.authId);
    }
    await Promise.all([
      adminModule.service.create({
        actorId: identity.authId,
        action: `account.${status}`,
        targetType: 'user',
        targetId: user.authId,
        metadata: { previousStatus, reason: user.accountStatusReason },
        createdBy: identity.authId,
      }),
      notifyUser({
        userId: user.authId,
        category: 'account',
        type: `account_${status}`,
        title: status === 'active' ? 'Account reactivated' : `Account ${status}`,
        body:
          status === 'active'
            ? 'Your RentHub account is active again. Please sign in with a new session.'
            : user.accountStatusReason,
        entityType: 'user',
        entityId: user.authId,
      }),
    ]);
    return user;
  },
};
