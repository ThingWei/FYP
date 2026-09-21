import mongoose from 'mongoose';

export const USER_ROLES = ['renter', 'owner', 'admin'];
export const ACCOUNT_STATUSES = ['active', 'suspended', 'banned'];
export const VERIFICATION_STATUSES = [
  'unverified',
  'pending',
  'approved',
  'rejected',
  'resubmission_required',
];

const addressSchema = new mongoose.Schema(
  {
    label: { type: String, required: true, trim: true, maxlength: 40 },
    line1: { type: String, required: true, trim: true, maxlength: 120 },
    line2: { type: String, trim: true, maxlength: 120, default: '' },
    city: { type: String, required: true, trim: true, maxlength: 80 },
    state: { type: String, required: true, trim: true, maxlength: 80 },
    postcode: {
      type: String,
      required: true,
      trim: true,
      match: [/^\d{5}$/, 'Postcode must contain 5 digits'],
    },
    isDefault: { type: Boolean, default: false },
  },
  { _id: true },
);

const userSchema = new mongoose.Schema(
  {
    authId: { type: String, required: true, unique: true, trim: true },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      match: [/^[^\s@]+@[^\s@]+\.[^\s@]+$/, 'Email is invalid'],
    },
    displayName: {
      type: String,
      required: true,
      trim: true,
      minlength: 2,
      maxlength: 80,
    },
    phone: { type: String, trim: true, maxlength: 24, default: '' },
    avatarUrl: { type: String, trim: true, default: '' },
    roles: {
      type: [{ type: String, enum: USER_ROLES }],
      required: true,
      validate: {
        validator: (roles) => roles.length > 0 && new Set(roles).size === roles.length,
        message: 'At least one unique role is required',
      },
    },
    activeRole: { type: String, enum: USER_ROLES, required: true },
    trustScore: { type: Number, min: 0, max: 100, default: 50 },
    accountStatus: {
      type: String,
      enum: ACCOUNT_STATUSES,
      default: 'active',
      index: true,
    },
    accountStatusReason: { type: String, trim: true, maxlength: 500, default: '' },
    verification: {
      status: {
        type: String,
        enum: VERIFICATION_STATUSES,
        default: 'unverified',
      },
      tier: { type: String, enum: ['none', 'basic', 'enhanced'], default: 'none' },
      documentType: {
        type: String,
        enum: ['mykad', 'passport'],
        default: undefined,
      },
      documentRefs: {
        type: [String],
        default: [],
        validate: {
          validator: (references) => references.length <= 2,
          message: 'A maximum of two identity-document references is allowed',
        },
      },
      ocrResult: { type: mongoose.Schema.Types.Mixed, default: {} },
      reason: { type: String, trim: true, maxlength: 500, default: '' },
      submittedAt: Date,
      reviewedAt: Date,
      reviewedBy: { type: String, trim: true, default: '' },
    },
    addresses: {
      type: [addressSchema],
      validate: {
        validator: (addresses) => addresses.length <= 10,
        message: 'A maximum of 10 addresses is allowed',
      },
      default: [],
    },
    blockedUserIds: { type: [String], default: [] },
    savedListingIds: {
      type: [{ type: String, match: /^l-[a-z0-9-]+$/i }],
      default: [],
      validate: {
        validator: (ids) => ids.length <= 100 && new Set(ids).size === ids.length,
        message: 'Saved listings must contain at most 100 unique items',
      },
    },
    comparisonListingIds: {
      type: [{ type: String, match: /^l-[a-z0-9-]+$/i }],
      default: [],
      validate: {
        validator: (ids) => ids.length <= 4 && new Set(ids).size === ids.length,
        message: 'Comparison must contain at most 4 unique items',
      },
    },
    settings: {
      language: { type: String, enum: ['en', 'ms'], default: 'en' },
      pushNotifications: { type: Boolean, default: true },
      emailNotifications: { type: Boolean, default: true },
    },
    lastLoginAt: Date,
  },
  { timestamps: true, strict: 'throw' },
);

userSchema.pre('validate', function validateActiveRole() {
  if (this.activeRole && !this.roles.includes(this.activeRole)) {
    this.invalidate('activeRole', 'Active role must be assigned to the user');
  }
  const defaults = this.addresses.filter((address) => address.isDefault);
  if (defaults.length > 1) {
    this.invalidate('addresses', 'Only one address can be the default');
  }
});

userSchema.index({ displayName: 'text', email: 'text' });

export const UserModel =
  mongoose.models.User ?? mongoose.model('User', userSchema);
