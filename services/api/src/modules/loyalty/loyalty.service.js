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
  const account = await ensureLoyaltyAccount(userId);
  account.points += points;
  if (points > 0) account.totalEarned += points;
  if (account.points < 0) {
    throw new AppError('Not enough loyalty points', 409, 'INSUFFICIENT_POINTS');
  }
  await account.save();
  return loyaltyRepository.createEntry({
    publicId: id('RH-RWD'),
    userId,
    type,
    points,
    balanceAfter: account.points,
    description,
    sourceType,
    sourceId,
    sourceKey,
    reward,
  });
}

async function completeReferral(booking, config) {
  const referral = await loyaltyRepository.findReferralForReferee(booking.renterId);
  if (!referral || referral.status !== 'pending') return;
  const completedBookings = await BookingModel.countDocuments({
    renterId: booking.renterId,
    status: 'completed',
  });
  if (completedBookings !== 1) return;
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
  await Promise.all([
    notifyUser({
      userId: referral.referrerId,
      category: 'loyalty',
      type: 'referral_rewarded',
      title: 'Referral reward earned',
      body: `You earned ${config.referralRewardPoints} loyalty points.`,
      entityType: 'referral',
      entityId: referral.publicId,
    }),
    notifyUser({
      userId: referral.refereeId,
      category: 'loyalty',
      type: 'referral_welcome_reward',
      title: 'Welcome reward unlocked',
      body: `Your RM ${config.refereeDiscountAmount.toFixed(2)} referral reward is ready.`,
      entityType: 'reward',
      entityId: welcomeCode,
    }),
  ]);
}

export async function awardRentalCompletion(rental, booking) {
  const config = await loyaltyRepository.ensureConfig();
  if (!config.enabled) return null;
  const sourceKey = `completion:${rental.publicId}`;
  const existing = await loyaltyRepository.findEntryBySourceKey(sourceKey);
  if (existing) {
    await completeReferral(booking, config);
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
    });
  }
  await completeReferral(booking, config);
  return entry;
}

async function summaryFor(userId) {
  const [account, entries, config, referral, completedBooking] = await Promise.all([
    ensureLoyaltyAccount(userId),
    loyaltyRepository.listEntries(userId),
    loyaltyRepository.ensureConfig(),
    loyaltyRepository.findReferralForReferee(userId),
    BookingModel.exists({ renterId: userId, status: 'completed' }),
  ]);
  return {
    points: account.points,
    referralCode: account.referralCode,
    totalEarned: account.totalEarned,
    totalRedeemed: account.totalRedeemed,
    ledger: entries,
    redemptionOptions: config.redemptionOptions,
    referral,
    canApplyReferral: !referral && !completedBooking,
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
    return referral;
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
    return { items, meta: { page, limit, total } };
  },
};
