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

const promotionSchema = new mongoose.Schema(
  {
    enabled: { type: Boolean, default: true },
    label: { type: String, required: true, trim: true, maxlength: 80 },
    discountPercent: { type: Number, required: true, min: 5, max: 80 },
    startsAt: { type: Date, required: true },
    endsAt: { type: Date, required: true },
  },
  { _id: false },
);

const bundleOfferSchema = new mongoose.Schema(
  {
    active: { type: Boolean, default: true },
    title: { type: String, required: true, trim: true, maxlength: 100 },
    listingIds: {
      type: [{ type: String, match: /^l-[a-z0-9-]+$/i }],
      required: true,
      validate: {
        validator: (ids) =>
          ids.length >= 2 && ids.length <= 5 && new Set(ids).size === ids.length,
        message: 'A bundle requires 2 to 5 unique listings',
      },
    },
    discountPercent: { type: Number, required: true, min: 5, max: 50 },
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
    ownerTrustScore: { type: Number, min: 0, max: 100, default: 50 },
    title: { type: String, required: true, trim: true, minlength: 3, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 3000, default: '' },
    category: { type: String, required: true, enum: LISTING_CATEGORIES, index: true },
    subcategory: { type: String, trim: true, maxlength: 100, default: '' },
    brand: { type: String, trim: true, maxlength: 100, default: '' },
    productModel: { type: String, trim: true, maxlength: 120, default: '' },
    canonicalProductId: { type: String, trim: true, maxlength: 160, default: null },
    catalogBrandId: { type: String, trim: true, maxlength: 160, default: null },
    productMatchType: {
      type: String,
      enum: [
        'exact_catalog_match',
        'fuzzy_catalog_match',
        'manual_entry',
        'catalog_brand_match_model_manual',
      ],
      default: 'manual_entry',
    },
    catalogSource: { type: String, trim: true, maxlength: 80, default: null },
    itemAgeYears: { type: Number, min: 0, max: 100 },
    listingType: { type: String, required: true, enum: LISTING_TYPES, index: true },
    sourceType: {
      type: String,
      enum: ['marketplace', 'demo_seed'],
      default: 'marketplace',
      index: true,
    },
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
    promotion: { type: promotionSchema, default: undefined },
    bundleOffer: { type: bundleOfferSchema, default: undefined },
    itemVerification: { type: mongoose.Schema.Types.Mixed, default: undefined },
    priceRecommendation: { type: mongoose.Schema.Types.Mixed, default: undefined },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      virtuals: true,
      transform: (_document, value) => {
        value.id = value.publicId;
        value.isService = value.listingType === 'service';
        const now = Date.now();
        const promotionActive = Boolean(
          value.promotion?.enabled &&
            new Date(value.promotion.startsAt).getTime() <= now &&
            new Date(value.promotion.endsAt).getTime() >= now,
        );
        value.promotionActive = promotionActive;
        value.effectiveDailyPrice = promotionActive
          ? Math.round(
              value.dailyPrice * (1 - value.promotion.discountPercent / 100) * 100,
            ) / 100
          : value.dailyPrice;
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

listingSchema.index(
  { canonicalProductId: 1, status: 1, state: 1 },
  {
    partialFilterExpression: { canonicalProductId: { $type: 'string' } },
    name: 'pricing_canonical_product_evidence',
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
  if (this.promotion?.startsAt >= this.promotion?.endsAt) {
    this.invalidate('promotion.endsAt', 'Promotion end must be after its start');
  }
  if (this.bundleOffer) {
    if (this.listingType !== 'physical') {
      this.invalidate('bundleOffer', 'Only physical items can use bundles');
    } else if (!this.bundleOffer.listingIds.includes(this.publicId)) {
      this.invalidate('bundleOffer.listingIds', 'Bundle must include this listing');
    }
  }
});

listingSchema.index({ title: 'text', description: 'text', location: 'text' });
listingSchema.index({
  status: 1,
  category: 1,
  subcategory: 1,
  brand: 1,
  productModel: 1,
  dailyPrice: 1,
});
listingSchema.index({ status: 1, rating: -1, createdAt: -1 });

export const ListingModel =
  mongoose.models.Listing ?? mongoose.model('Listing', listingSchema);
