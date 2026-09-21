import mongoose from 'mongoose';
import { LISTING_CATEGORIES } from '../listing/listing.model.js';

const categorySchema = new mongoose.Schema(
  {
    name: { type: String, enum: LISTING_CATEGORIES, required: true },
    active: { type: Boolean, default: true },
  },
  { _id: false },
);

const platformSettingSchema = new mongoose.Schema(
  {
    key: { type: String, unique: true, default: 'platform', immutable: true },
    marketplaceFeePercent: { type: Number, min: 0, max: 20, default: 5 },
    maintenanceMode: { type: Boolean, default: false },
    highValueKycEnabled: { type: Boolean, default: true },
    highValueThreshold: { type: Number, min: 0, max: 1_000_000, default: 1000 },
    reportAutoHideThreshold: { type: Number, min: 1, max: 100, default: 3 },
    verificationOcrThreshold: { type: Number, min: 0, max: 100, default: 80 },
    supportEmail: {
      type: String,
      trim: true,
      lowercase: true,
      default: 'support@renthub.my',
    },
    bookingPolicy: {
      type: String,
      trim: true,
      maxlength: 3000,
      default: 'Bookings are confirmed only after Owner approval.',
    },
    contentPolicy: {
      type: String,
      trim: true,
      maxlength: 3000,
      default: 'Listings must be lawful, accurate, safe, and suitable for rental.',
    },
    notificationTemplates: {
      bookingApproved: {
        type: String,
        trim: true,
        maxlength: 300,
        default: 'Your booking has been approved by the Owner.',
      },
      verificationUpdate: {
        type: String,
        trim: true,
        maxlength: 300,
        default: 'Your identity-verification status has been updated.',
      },
      reportResolved: {
        type: String,
        trim: true,
        maxlength: 300,
        default: 'Your report has been reviewed by RentHub.',
      },
    },
    categories: {
      type: [categorySchema],
      default: () => LISTING_CATEGORIES.map((name) => ({ name, active: true })),
      validate: {
        validator: (categories) =>
          categories.length === LISTING_CATEGORIES.length &&
          new Set(categories.map((category) => category.name)).size ===
            LISTING_CATEGORIES.length &&
          LISTING_CATEGORIES.every((name) =>
            categories.some((category) => category.name === name),
          ),
        message: 'Every canonical category must appear exactly once',
      },
    },
    updatedBy: { type: String, trim: true, default: '' },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.key;
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

export const PlatformSettingModel =
  mongoose.models.PlatformSetting ??
  mongoose.model('PlatformSetting', platformSettingSchema);
