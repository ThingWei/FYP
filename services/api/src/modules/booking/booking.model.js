import mongoose from 'mongoose';

export const BOOKING_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'cancelled',
  'expired',
  'active',
  'completed',
  'disputed',
];

const pricingSchema = new mongoose.Schema(
  {
    baseAmount: { type: Number, required: true, min: 0 },
    securityDeposit: { type: Number, required: true, min: 0, default: 0 },
    damageWaiverFee: { type: Number, required: true, min: 0, default: 0 },
    platformFee: { type: Number, required: true, min: 0, default: 0 },
    total: { type: Number, required: true, min: 0 },
    currency: { type: String, enum: ['MYR'], default: 'MYR' },
  },
  { _id: false },
);

const bookingSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      match: [/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/, 'Invalid booking identifier'],
    },
    listingId: { type: String, required: true, index: true },
    listingTitle: { type: String, required: true, trim: true },
    listingType: { type: String, enum: ['physical', 'service'], required: true },
    category: { type: String, immutable: true },
    requiredLicenceClass: { type: String, immutable: true },
    sourceType: {
      type: String,
      enum: ['marketplace', 'demo_seed'],
      default: 'marketplace',
      index: true,
    },
    renterId: { type: String, required: true, index: true },
    idempotencyKey: {
      type: String,
      trim: true,
      maxlength: 100,
      select: false,
    },
    idempotencyFingerprint: { type: String, trim: true, select: false },
    renterName: { type: String, required: true, trim: true },
    ownerId: { type: String, required: true, index: true },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    fulfilmentMethod: { type: String, enum: ['pickup', 'owner_delivery'] },
    serviceVenue: { type: String, trim: true, maxlength: 240 },
    damageWaiverSelected: { type: Boolean, default: false },
    pricing: { type: pricingSchema, required: true },
    paymentStatus: {
      type: String,
      enum: [
        'unpaid',
        'authorized',
        'captured',
        'partially_refunded',
        'refunded',
        'voided',
        'settled',
      ],
      default: 'unpaid',
      index: true,
    },
    paymentAuthorizationId: { type: String, trim: true, default: '' },
    status: { type: String, enum: BOOKING_STATUSES, default: 'pending', index: true },
    renterNote: { type: String, trim: true, maxlength: 1000, default: '' },
    agreement: {
      version: { type: String, trim: true },
      termsHash: { type: String, trim: true },
      acceptedAt: Date,
    },
    ownerDecisionReason: { type: String, trim: true, maxlength: 500, default: '' },
    cancellationReason: { type: String, trim: true, maxlength: 500, default: '' },
    decidedAt: Date,
    cancelledAt: Date,
    expiresAt: Date,
    expiredAt: Date,
    activatedAt: Date,
    completedAt: Date,
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      virtuals: true,
      transform: (_document, value) => {
        value.id = value.publicId;
        value.start = value.startDate;
        value.end = value.endDate;
        value.total = value.pricing?.total;
        delete value._id;
        delete value.__v;
        delete value.idempotencyKey;
        delete value.idempotencyFingerprint;
        return value;
      },
    },
  },
);

bookingSchema.pre('validate', function validateBooking() {
  if (this.endDate < this.startDate) {
    this.invalidate('endDate', 'End date must not be before start date');
  }
  if (this.renterId === this.ownerId) {
    this.invalidate('renterId', 'Owners cannot book their own listings');
  }
  if (this.listingType === 'physical') {
    if (!this.fulfilmentMethod) {
      this.invalidate('fulfilmentMethod', 'Fulfilment method is required');
    }
    this.serviceVenue = undefined;
  } else {
    if (!this.serviceVenue) {
      this.invalidate('serviceVenue', 'Service venue is required');
    }
    this.fulfilmentMethod = undefined;
    this.damageWaiverSelected = false;
  }
});

bookingSchema.index({ listingId: 1, status: 1, startDate: 1, endDate: 1 });
bookingSchema.index({ renterId: 1, createdAt: -1 });
bookingSchema.index({ ownerId: 1, createdAt: -1 });
bookingSchema.index(
  { renterId: 1, idempotencyKey: 1 },
  {
    unique: true,
    partialFilterExpression: { idempotencyKey: { $type: 'string' } },
    name: 'unique_renter_booking_idempotency',
  },
);

export const BookingModel =
  mongoose.models.Booking ?? mongoose.model('Booking', bookingSchema);
