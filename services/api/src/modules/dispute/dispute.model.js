import mongoose from 'mongoose';

export const DISPUTE_STATUSES = [
  'open',
  'awaiting_response',
  'under_review',
  'more_evidence_required',
  'escalated',
  'resolved',
  'dismissed',
];

export const PHYSICAL_DISPUTE_CATEGORIES = [
  'damaged_item',
  'return_condition',
  'missing_item',
  'deposit_deduction',
  'late_return',
];

export const SERVICE_DISPUTE_CATEGORIES = [
  'service_quality',
  'non_delivery',
  'scope_mismatch',
  'cancellation',
];

export const GENERAL_DISPUTE_CATEGORIES = ['communication', 'other'];

const responseSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true },
    role: { type: String, enum: ['renter', 'owner'], required: true },
    text: { type: String, required: true, trim: true, minlength: 5, maxlength: 2000 },
    evidence: {
      type: [{ type: String, trim: true, maxlength: 500 }],
      validate: [
        (items) => items.length <= 10,
        'A maximum of 10 evidence files is allowed',
      ],
      default: [],
    },
    submittedAt: { type: Date, default: Date.now },
  },
  { _id: true },
);

const resolutionSchema = new mongoose.Schema(
  {
    outcome: {
      type: String,
      enum: ['release_to_renter', 'split', 'release_to_owner', 'dismissed'],
    },
    renterAmount: { type: Number, min: 0, default: 0 },
    ownerAmount: { type: Number, min: 0, default: 0 },
    notes: { type: String, trim: true, maxlength: 2000 },
    resolvedBy: String,
    resolvedAt: Date,
    blockchainReference: String,
    blockchainStatus: {
      type: String,
      enum: ['unavailable', 'confirmed', 'failed'],
    },
    localBlockchainPrototype: { type: Boolean, default: true },
    simulatedSettlement: { type: Boolean, default: true },
  },
  { _id: false },
);

const disputeSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    rentalId: { type: String, required: true, unique: true, index: true },
    bookingId: { type: String, required: true, index: true },
    listingId: { type: String, required: true, index: true },
    listingTitle: { type: String, required: true, trim: true },
    listingType: { type: String, enum: ['physical', 'service'], required: true },
    raisedById: { type: String, required: true, index: true },
    raisedByName: { type: String, required: true, trim: true },
    raisedByRole: { type: String, enum: ['renter', 'owner'], required: true },
    respondentId: { type: String, required: true, index: true },
    respondentName: { type: String, required: true, trim: true },
    respondentRole: { type: String, enum: ['renter', 'owner'], required: true },
    category: { type: String, required: true, trim: true },
    summary: { type: String, required: true, trim: true, minlength: 5, maxlength: 160 },
    description: {
      type: String,
      required: true,
      trim: true,
      minlength: 20,
      maxlength: 3000,
    },
    evidence: {
      type: [{ type: String, trim: true, maxlength: 500 }],
      validate: [
        (items) => items.length <= 10,
        'A maximum of 10 evidence files is allowed',
      ],
      default: [],
    },
    status: { type: String, enum: DISPUTE_STATUSES, default: 'open', index: true },
    previousRentalStatus: { type: String, required: true },
    previousBookingStatus: { type: String, required: true },
    responses: { type: [responseSchema], default: [] },
    adminNote: { type: String, trim: true, maxlength: 2000, default: '' },
    resolution: resolutionSchema,
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

disputeSchema.pre('validate', function validateCategory() {
  const allowed =
    this.listingType === 'physical'
      ? [...PHYSICAL_DISPUTE_CATEGORIES, ...GENERAL_DISPUTE_CATEGORIES]
      : [...SERVICE_DISPUTE_CATEGORIES, ...GENERAL_DISPUTE_CATEGORIES];
  if (this.category && !allowed.includes(this.category)) {
    this.invalidate('category', `Category is not valid for a ${this.listingType} listing`);
  }
});

export const DisputeModel =
  mongoose.models.Dispute ?? mongoose.model('Dispute', disputeSchema);
