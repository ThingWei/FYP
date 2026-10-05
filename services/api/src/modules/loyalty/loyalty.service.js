import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { adminModule } from '../admin/index.js';
import { BookingModel } from '../booking/booking.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { UserModel } from '../user/user.model.js';
import { LOYALTY_ENTRY_TYPES } from './loyalty.model.js';
import { loyaltyRepository } from './loyalty.repository.js';

function id(prefix) {
  return `${prefix}-${new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase()}`;
}

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 50, 1), 100),
  };
}

async function activeUser(identity) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  return user;
}

function referralCode(user) {
  const name = user.displayName.replace(/[^a-z\d]/gi, '').toUpperCase().slice(0, 6);
  const suffix = new mongoose.Types.ObjectId().toString().slice(-4).toUpperCase();
  return `RH-${name || 'MEMBER'}${suffix}`;
}

export async function ensureLoyaltyAccount(userId) {
  let account = await loyaltyRepository.findAccount(userId);
  if (account) return account;
  const user = await UserModel.findOne({ authId: userId });
  if (!user) throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  try {
    account = await loyaltyRepository.createAccount({
      userId,
      referralCode: referralCode(user),
    });
  } catch (error) {
    if (error.code !== 11000) throw error;
    account = await loyaltyRepository.findAccount(userId);
  }
  return account;
}

async function grantPoints({
  userId,
  points,
  type,
  description,
  sourceType,
  sourceId,
  sourceKey,
  reward,
}) {
  const existing = await loyaltyRepository.findEntryBySourceKey(sourceKey);
  if (existing) return existing;
  await ensureLoyaltyAccount(userId);
  let account = await loyaltyRepository.applyAccountOperation({
    userId,
    sourceKey,
    points,
  });
  if (!account) {
    account = await loyaltyRepository.findAccountWithOperations(userId);
    const operation = account?.appliedOperations?.find(
      (item) => item.sourceKey === sourceKey,
    );
    if (!operation) {
      if (points < 0) {
        throw new AppError('Not enough loyalty points', 409, 'INSUFFICIENT_POINTS');
      }
      throw new AppError(
        'The loyalty operation could not be applied',
        409,
        'LOYALTY_OPERATION_FAILED',
      );
    }
  }
  const operation = account.appliedOperations.find(
    (item) => item.sourceKey === sourceKey,
  );
  return loyaltyRepository.upsertEntry({
    publicId: id('RH-RWD'),
    userId,
    type,
    points,
    balanceAfter: operation.balanceAfter,
    description,
    sourceType,
    sourceId,
    sourceKey,
    reward,
  });
}

function referralDocument(referral) {
  return referral?.toJSON ? referral.toJSON() : referral;
}

function referralProgress({ referral, config, completedBooking, openBooking }) {
  if (!referral) return null;
  const value = referralDocument(referral);
  let progressState;
  let nextAction;
  let nextActionMessage;
  if (value.status === 'rewarded') {
    progressState = 'rewarded';
    nextAction = 'view_reward';
    nextActionMessage = 'Your referral reward is ready in your rewards history.';
  } else if (!config.enabled) {
    progressState = 'programme_paused';
    nextAction = 'wait_for_programme';
    nextActionMessage =
      'The loyalty programme is paused. Your pending referral is retained and will be checked when it resumes.';
  } else if (
    completedBooking?.completedAt &&
    new Date(completedBooking.completedAt) < new Date(value.appliedAt)
  ) {
    progressState = 'invalid_application';
    nextAction = 'none';
    nextActionMessage =
      'This referral was applied after the first completed booking and cannot qualify automatically.';
  } else if (completedBooking) {
    progressState = 'eligible_for_reconciliation';
    nextAction = 'none';
    nextActionMessage = 'Your completed booking is being checked for referral rewards.';
  } else if (openBooking) {
    progressState = 'waiting_for_completion';
    nextAction = 'view_booking';
    nextActionMessage =
      'Complete your first RentHub booking to unlock the referral rewards. No separate approval is required.';
  } else {
    progressState = 'waiting_for_booking';
    nextAction = 'browse_listings';
    nextActionMessage =
      'Complete your first RentHub booking to unlock the referral rewards. No separate approval is required.';
  }
  return {
    ...value,
    completionTrigger: 'first_completed_booking',
    progressState,
    nextAction,
    nextActionMessage,
  };
}

async function bookingProgress(refereeId) {
  const [completedBooking, openBooking] = await Promise.all([
    BookingModel.findOne({
      renterId: refereeId,
      status: 'completed',
      completedAt: { $type: 'date' },
    })
      .sort({ completedAt: 1, publicId: 1 })
      .lean(),
    BookingModel.findOne({
      renterId: refereeId,
      status: { $in: ['pending', 'approved', 'active', 'disputed'] },
    })
      .sort({ createdAt: 1, publicId: 1 })
      .lean(),
  ]);
  return { completedBooking, openBooking };
}

export async function reconcileReferralForReferee(refereeId, suppliedConfig) {
  const referral = await loyaltyRepository.findReferralForReferee(refereeId);
  if (!referral || referral.status !== 'pending') return referral;
  const config = suppliedConfig ?? (await loyaltyRepository.ensureConfig());
  if (!config.enabled) return referral;
  const { completedBooking } = await bookingProgress(refereeId);
  if (!completedBooking) return referral;
  if (new Date(completedBooking.completedAt) < new Date(referral.appliedAt)) {
    return referral;
  }
  referral.qualifyingBookingId = completedBooking.publicId;
  referral.qualifyingCompletedAt = completedBooking.completedAt;
  await referral.save();
  await grantPoints({
    userId: referral.referrerId,
    points: config.referralRewardPoints,
    type: 'referral_reward',
    description: 'Successful referral reward',
    sourceType: 'referral',
    sourceId: referral.publicId,
    sourceKey: `referral:referrer:${referral.publicId}`,
  });
  const welcomeCode = `WELCOME-${referral.publicId.replace('RH-REF-', '')}`;
  await grantPoints({
    userId: referral.refereeId,
    points: 0,
    type: 'referral_welcome',
    description: 'Referral welcome reward',
    sourceType: 'referral',
    sourceId: referral.publicId,
    sourceKey: `referral:referee:${referral.publicId}`,
    reward: {
      code: welcomeCode,
      discountAmount: config.refereeDiscountAmount,
      currency: 'MYR',
      status: 'available',
    },
  });
  referral.status = 'rewarded';
  referral.rewardedAt = new Date();
  referral.refereeRewardAmount = config.refereeDiscountAmount;
  await referral.save();
  const notifications = await Promise.allSettled([
    notifyUser({
      userId: referral.referrerId,
      category: 'loyalty',
      type: 'referral_rewarded',
      title: 'Referral reward earned',
      body: `You earned ${config.referralRewardPoints} loyalty points.`,
      entityType: 'referral',
      entityId: referral.publicId,
      dedupeKey: `referral:${referral.publicId}:referrer`,
    }),
    notifyUser({
      userId: referral.refereeId,
      category: 'loyalty',
      type: 'referral_welcome_reward',
      title: 'Welcome reward unlocked',
      body: `Your RM ${config.refereeDiscountAmount.toFixed(2)} referral reward is ready.`,
      entityType: 'reward',
      entityId: welcomeCode,
      dedupeKey: `referral:${referral.publicId}:referee`,
    }),
  ]);
  for (const result of notifications) {
    if (result.status === 'rejected') {
      console.error('Referral notification delivery failed', {
        referralId: referral.publicId,
        message: result.reason?.message,
      });
    }
  }
  return referral;
}

export async function awardRentalCompletion(rental, booking) {
  const config = await loyaltyRepository.ensureConfig();
  if (!config.enabled) return null;
  const sourceKey = `completion:${rental.publicId}`;
  const existing = await loyaltyRepository.findEntryBySourceKey(sourceKey);
  if (existing) {
    await reconcileReferralForReferee(booking.renterId, config);
    return existing;
  }
  const points =
    rental.listingType === 'service'
      ? config.serviceCompletionPoints
      : config.physicalCompletionPoints;
  const entry = await grantPoints({
    userId: rental.renterId,
    points,
    type:
      rental.listingType === 'service'
        ? 'service_completed'
        : 'rental_completed',
    description: `${booking.listingTitle} completed`,
    sourceType: 'rental',
    sourceId: rental.publicId,
    sourceKey,
  });
  if (points > 0) {
    await notifyUser({
      userId: rental.renterId,
      category: 'loyalty',
      type: 'completion_points',
      title: 'Loyalty points earned',
      body: `You earned ${points} points for completing ${booking.listingTitle}.`,
      entityType: 'reward',
      entityId: entry.publicId,
      dedupeKey: `loyalty:${sourceKey}`,
    });
  }
  await reconcileReferralForReferee(booking.renterId, config);
  return entry;
}

async function summaryFor(userId) {
  const config = await loyaltyRepository.ensureConfig();
  if (config.enabled) {
    try {
      await reconcileReferralForReferee(userId, config);
    } catch (error) {
      console.error('Referral reconciliation failed', {
        refereeId: userId,
        message: error.message,
      });
    }
  }
  const [account, entries, referral, progress] = await Promise.all([
    ensureLoyaltyAccount(userId),
    loyaltyRepository.listEntries(userId),
    loyaltyRepository.findReferralForReferee(userId),
    bookingProgress(userId),
  ]);
  return {
    points: account.points,
    referralCode: account.referralCode,
    totalEarned: account.totalEarned,
    totalRedeemed: account.totalRedeemed,
    ledger: entries,
    redemptionOptions: config.redemptionOptions,
    referral: referralProgress({ referral, config, ...progress }),
    canApplyReferral: Boolean(
      config.enabled && !referral && !progress.completedBooking,
    ),
    rules: {
      enabled: config.enabled,
      physicalCompletionPoints: config.physicalCompletionPoints,
      serviceCompletionPoints: config.serviceCompletionPoints,
      referralRewardPoints: config.referralRewardPoints,
      refereeDiscountAmount: config.refereeDiscountAmount,
    },
  };
}

export const loyaltyService = {
  async summary(identity) {
    await activeUser(identity);
    return summaryFor(identity.authId);
  },

  async redeem(input, identity) {
    await activeUser(identity);
    const config = await loyaltyRepository.ensureConfig();
    if (!config.enabled) {
      throw new AppError('The loyalty programme is currently disabled', 409, 'LOYALTY_DISABLED');
    }
    const option = config.redemptionOptions.find(
      (item) => item.points === input.points,
    );
    if (!option) {
      throw new AppError('This reward option is unavailable', 400, 'INVALID_REWARD');
    }
    const account = await ensureLoyaltyAccount(identity.authId);
    if (account.points < option.points) {
      throw new AppError('Not enough loyalty points', 409, 'INSUFFICIENT_POINTS');
    }
    const redemptionId = id('RH-RDM');
    const entry = await grantPoints({
      userId: identity.authId,
      points: -option.points,
      type: 'redemption',
      description: `RM ${option.discountAmount.toFixed(2)} booking discount redeemed`,
      sourceType: 'redemption',
      sourceId: redemptionId,
      sourceKey: `redemption:${redemptionId}`,
      reward: {
        code: redemptionId,
        discountAmount: option.discountAmount,
        currency: 'MYR',
        status: 'available',
      },
    });
    const updatedAccount = await loyaltyRepository.findAccount(identity.authId);
    updatedAccount.totalRedeemed += option.points;
    await updatedAccount.save();
    await notifyUser({
      userId: identity.authId,
      category: 'loyalty',
      type: 'reward_redeemed',
      title: 'Reward redeemed',
      body: `Your RM ${option.discountAmount.toFixed(2)} booking reward is ready.`,
      entityType: 'reward',
      entityId: entry.publicId,
    });
    return summaryFor(identity.authId);
  },

  async applyReferral(input, identity) {
    await activeUser(identity);
    const config = await loyaltyRepository.ensureConfig();
    if (!config.enabled) {
      throw new AppError(
        'The loyalty programme is currently disabled',
        409,
        'LOYALTY_DISABLED',
      );
    }
    if (await loyaltyRepository.findReferralForReferee(identity.authId)) {
      throw new AppError('A referral code was already applied', 409, 'REFERRAL_EXISTS');
    }
    const completed = await BookingModel.exists({
      renterId: identity.authId,
      status: 'completed',
    });
    if (completed) {
      throw new AppError(
        'Referral codes must be applied before the first completed booking',
        409,
        'REFERRAL_WINDOW_ENDED',
      );
    }
    const referrer = await loyaltyRepository.findAccountByCode(
      input.referralCode.toUpperCase(),
    );
    if (!referrer) throw new AppError('Referral code not found', 404, 'NOT_FOUND');
    if (referrer.userId === identity.authId) {
      throw new AppError('You cannot use your own referral code', 400, 'SELF_REFERRAL');
    }
    const referral = await loyaltyRepository.createReferral({
      publicId: id('RH-REF'),
      referralCode: referrer.referralCode,
      referrerId: referrer.userId,
      refereeId: identity.authId,
      status: 'pending',
    });
    const progress = await bookingProgress(identity.authId);
    return referralProgress({ referral, config, ...progress });
  },

  async getConfig() {
    return loyaltyRepository.ensureConfig();
  },

  async updateConfig(input, identity) {
    const config = await loyaltyRepository.updateConfig({
      ...input,
      redemptionOptions: [...input.redemptionOptions].sort(
        (first, second) => first.points - second.points,
      ),
      updatedBy: identity.authId,
    });
    await adminModule.Model.create({
      actorId: identity.authId,
      action: 'loyalty.config_updated',
      targetType: 'loyalty_config',
      targetId: 'default',
      metadata: input,
      createdBy: identity.authId,
    });
    return config;
  },

  async listAdminEntries(query) {
    const { page, limit } = pageOptions(query);
    const type = LOYALTY_ENTRY_TYPES.includes(query.type) ? query.type : undefined;
    const [items, total] = await loyaltyRepository.listAdminEntries({
      page,
      limit,
      type,
    });
    return { items, meta: { page, limit, total } };
  },

  async listReferrals(query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await loyaltyRepository.listReferrals({
      page,
      limit,
      status: query.status,
    });
    const config = await loyaltyRepository.ensureConfig();
    const decorated = await Promise.all(
      items.map(async (referral) => ({
        ...referralProgress({
          referral,
          config,
          ...(await bookingProgress(referral.refereeId)),
        }),
      })),
    );
    return { items: decorated, meta: { page, limit, total } };
  },
};
