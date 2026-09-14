import mongoose from 'mongoose';

export const LISTING_CATEGORIES = [
  'Clothing',
  'Vehicles',
  'Services',
  'Devices',
  'Books',
  'Equipment',
];
export const LISTING_TYPES = ['physical', 'service'];
export const LISTING_STATUSES = [
  'draft',
  'pending_review',
  'active',
  'inactive',
  'rejected',
];

const serviceDetailsSchema = new mongoose.Schema(
  {
    packageName: { type: String, trim: true, maxlength: 100 },
    durationMinutes: { type: Number, min: 15, max: 10_080 },
    venueMode: {
      type: String,
      enum: ['owner_location', 'renter_location', 'online', 'flexible'],
      default: 'flexible',
    },
    inclusions: [{ type: String, trim: true, maxlength: 160 }],
  },
  { _id: false },
);

const listingSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      match: [/^l-[a-z0-9-]+$/i, 'Invalid listing identifier'],
      default: () => `l-${new mongoose.Types.ObjectId()}`,
    },
    ownerId: { type: String, required: true, trim: true, index: true },
    ownerName: { type: String, required: true, trim: true, maxlength: 80 },
    title: { type: String, required: true, trim: true, minlength: 3, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 3000, default: '' },
    category: { type: String, required: true, enum: LISTING_CATEGORIES, index: true },
    listingType: { type: String, required: true, enum: LISTING_TYPES, index: true },
    dailyPrice: { type: Number, required: true, min: 1, max: 1_000_000 },
    priceUnit: {
      type: String,
      enum: ['day', 'hour', 'session', 'package'],
      default: 'day',
    },
    condition: {
      type: String,
      enum: ['Fair', 'Good', 'Very good', 'Excellent', 'Like New'],
    },
    securityDeposit: { type: Number, min: 0, max: 1_000_000, default: 0 },
    damageWaiverAvailable: { type: Boolean, default: false },
    damageWaiverFee: { type: Number, min: 0, max: 100_000, default: 0 },
    fulfilmentMethods: {
      type: [{ type: String, enum: ['pickup', 'owner_delivery'] }],
      default: [],
    },
    serviceDetails: { type: serviceDetailsSchema },
    location: { type: String, required: true, trim: true, maxlength: 160 },
    state: { type: String, trim: true, maxlength: 80, default: '' },
    images: {
      type: [{ type: String, trim: true, maxlength: 500 }],
      validate: {
        validator: (images) => images.length <= 10,
        message: 'A maximum of 10 images is allowed',
      },
      default: [],
    },
    verified: { type: Boolean, default: false, index: true },
    rating: { type: Number, min: 0, max: 5, default: 0 },
    reviewCount: { type: Number, min: 0, default: 0 },
    status: { type: String, enum: LISTING_STATUSES, default: 'draft', index: true },
    moderationReason: { type: String, trim: true, maxlength: 500, default: '' },
    promoted: { type: Boolean, default: false },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      virtuals: true,
      transform: (_document, value) => {
        value.id = value.publicId;
        value.isService = value.listingType === 'service';
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

listingSchema.pre('validate', function validateListingType() {
  if (this.category === 'Services' && this.listingType !== 'service') {
    this.invalidate('listingType', 'Services category requires a service listing');
  }
  if (this.category !== 'Services' && this.listingType !== 'physical') {
    this.invalidate('listingType', 'Only the Services category can be a service');
  }
  if (this.listingType === 'physical') {
    if (!this.condition) this.invalidate('condition', 'Condition is required');
    if (!this.fulfilmentMethods.length) {
      this.invalidate('fulfilmentMethods', 'A fulfilment method is required');
    }
    this.serviceDetails = undefined;
    if (this.priceUnit !== 'day') {
      this.invalidate('priceUnit', 'Physical items must be priced per day');
    }
  } else {
    if (!this.serviceDetails?.packageName) {
      this.invalidate('serviceDetails.packageName', 'Package name is required');
    }
    if (!this.serviceDetails?.durationMinutes) {
      this.invalidate('serviceDetails.durationMinutes', 'Duration is required');
    }
    this.condition = undefined;
    this.securityDeposit = 0;
    this.damageWaiverAvailable = false;
    this.damageWaiverFee = 0;
    this.fulfilmentMethods = [];
  }
});

listingSchema.index({ title: 'text', description: 'text', location: 'text' });
listingSchema.index({ status: 1, category: 1, listingType: 1, dailyPrice: 1 });

export const ListingModel =
  mongoose.models.Listing ?? mongoose.model('Listing', listingSchema);
