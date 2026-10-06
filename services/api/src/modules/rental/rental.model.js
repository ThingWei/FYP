import mongoose from 'mongoose';

export const RENTAL_STATUSES = [
  'scheduled',
  'active',
  'overdue',
  'return_submitted',
  'completion_pending',
  'completed',
  'disputed',
  'cancelled',
];

const evidenceSchema = new mongoose.Schema(
  {
    condition: { type: String, trim: true, maxlength: 120 },
    notes: { type: String, trim: true, maxlength: 1000, default: '' },
    evidence: {
      type: [{ type: String, trim: true, maxlength: 500 }],
      validate: {
        validator: (items) => items.length <= 10,
        message: 'A maximum of 10 evidence files is allowed',
      },
      default: [],
    },
    recordedAt: Date,
  },
  { _id: false },
);

const extensionSchema = new mongoose.Schema(
  {
    requestedEndDate: Date,
    reason: { type: String, trim: true, maxlength: 500, default: '' },
    status: {
      type: String,
      enum: ['none', 'pending', 'approved', 'rejected'],
      default: 'none',
    },
    ownerReason: { type: String, trim: true, maxlength: 500, default: '' },
    requestedAt: Date,
    decidedAt: Date,
  },
  { _id: false },
);

const rentalSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true },
    bookingId: { type: String, required: true, unique: true, index: true },
    listingId: { type: String, required: true, index: true },
    listingType: { type: String, enum: ['physical', 'service'], required: true },
    category: { type: String, immutable: true },
    requiredLicenceClass: { type: String, immutable: true },
    renterId: { type: String, required: true, index: true },
    ownerId: { type: String, required: true, index: true },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    status: { type: String, enum: RENTAL_STATUSES, default: 'scheduled', index: true },
    handover: { type: evidenceSchema },
    returnSubmission: { type: evidenceSchema },
    returnOutcome: {
      condition: { type: String, trim: true, maxlength: 120 },
      notes: { type: String, trim: true, maxlength: 1000, default: '' },
      depositDeduction: { type: Number, min: 0, default: 0 },
      confirmedAt: Date,
    },
    serviceDeliveredAt: Date,
    serviceCompletedAt: Date,
    extension: { type: extensionSchema, default: () => ({ status: 'none' }) },
    automation: {
      startReminderSentAt: Date,
      dueReminderSentAt: Date,
      overdueNotifiedAt: Date,
      serviceDueReminderSentAt: Date,
      completionReminderSentAt: Date,
      lastProcessedAt: Date,
    },
    contractAddress: String,
    transactionHash: String,
    blockchain: {
      mode: { type: String, enum: ['disabled', 'ganache'], default: 'disabled' },
      status: {
        type: String,
        enum: ['unavailable', 'confirmed', 'failed'],
        default: 'unavailable',
      },
      localPrototype: { type: Boolean, default: true },
      network: { type: String, trim: true, default: 'ganache-local' },
      action: { type: String, trim: true, default: 'none' },
      contractAddress: { type: String, trim: true, default: '' },
      deploymentTransactionHash: { type: String, trim: true, default: '' },
      lastTransactionHash: { type: String, trim: true, default: '' },
      signatureTransactionHashes: { type: [String], default: [] },
      contractState: { type: String, trim: true, default: '' },
      unitPolicy: { type: String, trim: true, default: '' },
      error: { type: String, trim: true, default: '' },
      updatedAt: Date,
    },
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

rentalSchema.pre('validate', function validateEvidence() {
  if (this.listingType === 'service') {
    this.handover = undefined;
    this.returnSubmission = undefined;
    this.returnOutcome = undefined;
  }
});

export const RentalModel =
  mongoose.models.Rental ?? mongoose.model('Rental', rentalSchema);
