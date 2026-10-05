import mongoose from 'mongoose';

export const LOYALTY_ENTRY_TYPES = [
  'bonus',
  'rental_completed',
  'service_completed',
  'referral_reward',
  'referral_welcome',
  'redemption',
];

const loyaltyAccountSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, unique: true, index: true },
    points: { type: Number, required: true, min: 0, default: 0 },
    referralCode: {
      type: String,
      required: true,
      unique: true,
      uppercase: true,
      trim: true,
      index: true,
    },
    totalEarned: { type: Number, required: true, min: 0, default: 0 },
    totalRedeemed: { type: Number, required: true, min: 0, default: 0 },
    appliedOperations: {
      type: [
        new mongoose.Schema(
          {
            sourceKey: { type: String, required: true, trim: true },
            balanceAfter: { type: Number, required: true, min: 0 },
            appliedAt: { type: Date, required: true },
          },
          { _id: false },
        ),
      ],
      default: [],
      select: false,
    },
  },
  { timestamps: true, strict: 'throw' },
);

const rewardSchema = new mongoose.Schema(
  {
    code: { type: String, trim: true },
    discountAmount: { type: Number, min: 0 },
    currency: { type: String, enum: ['MYR'], default: 'MYR' },
    status: {
      type: String,
      enum: ['available', 'used', 'expired'],
      default: 'available',
    },
  },
  { _id: false },
);

const rewardLedgerSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    userId: { type: String, required: true, index: true },
    type: { type: String, enum: LOYALTY_ENTRY_TYPES, required: true, index: true },
    points: { type: Number, required: true },
    balanceAfter: { type: Number, required: true, min: 0 },
    description: { type: String, required: true, trim: true, maxlength: 240 },
    sourceType: {
      type: String,
      enum: ['system', 'rental', 'referral', 'redemption'],
      required: true,
    },
    sourceId: { type: String, required: true, trim: true },
    sourceKey: { type: String, required: true, unique: true, index: true },
    reward: rewardSchema,
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

const referralSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    referralCode: { type: String, required: true, uppercase: true, trim: true },
    referrerId: { type: String, required: true, index: true },
    refereeId: { type: String, required: true, unique: true, index: true },
    status: {
      type: String,
      enum: ['pending', 'rewarded'],
      default: 'pending',
      index: true,
    },
    appliedAt: { type: Date, default: Date.now },
    rewardedAt: Date,
    qualifyingBookingId: { type: String, trim: true },
    qualifyingCompletedAt: Date,
    refereeRewardAmount: { type: Number, min: 0, default: 0 },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

const redemptionOptionSchema = new mongoose.Schema(
  {
    points: { type: Number, required: true, min: 1 },
    discountAmount: { type: Number, required: true, min: 0.01 },
  },
  { _id: false },
);

const loyaltyConfigSchema = new mongoose.Schema(
  {
    key: { type: String, unique: true, default: 'default' },
    enabled: { type: Boolean, default: true },
    physicalCompletionPoints: { type: Number, min: 0, default: 120 },
    serviceCompletionPoints: { type: Number, min: 0, default: 100 },
    referralRewardPoints: { type: Number, min: 0, default: 250 },
    refereeDiscountAmount: { type: Number, min: 0, default: 5 },
    redemptionOptions: {
      type: [redemptionOptionSchema],
      default: () => [
        { points: 500, discountAmount: 5 },
        { points: 1000, discountAmount: 10 },
      ],
      validate: [
        (items) =>
          items.length > 0 &&
          items.length <= 10 &&
          new Set(items.map((item) => item.points)).size === items.length,
        'Redemption point costs must be unique',
      ],
    },
    updatedBy: String,
  },
  { timestamps: true, strict: 'throw' },
);

export const LoyaltyAccountModel =
  mongoose.models.LoyaltyAccount ??
  mongoose.model('LoyaltyAccount', loyaltyAccountSchema);
export const RewardLedgerModel =
  mongoose.models.RewardLedger ??
  mongoose.model('RewardLedger', rewardLedgerSchema);
export const ReferralModel =
  mongoose.models.Referral ?? mongoose.model('Referral', referralSchema);
export const LoyaltyConfigModel =
  mongoose.models.LoyaltyConfig ??
  mongoose.model('LoyaltyConfig', loyaltyConfigSchema);
