import mongoose from 'mongoose';

export const CLAIM_STATUSES = ['pending', 'approved', 'rejected'];

const claimSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    disputeId: { type: String, required: true, index: true },
    rentalId: { type: String, required: true, unique: true, index: true },
    bookingId: { type: String, required: true, index: true },
    listingId: { type: String, required: true },
    listingTitle: { type: String, required: true, trim: true },
    ownerId: { type: String, required: true, index: true },
    renterId: { type: String, required: true, index: true },
    description: {
      type: String,
      required: true,
      trim: true,
      minlength: 20,
      maxlength: 3000,
    },
    amountRequested: { type: Number, required: true, min: 0.01 },
    evidence: {
      type: [{ type: String, trim: true, maxlength: 500 }],
      validate: [
        (items) => items.length > 0 && items.length <= 10,
        'Between 1 and 10 evidence files are required',
      ],
    },
    status: { type: String, enum: CLAIM_STATUSES, default: 'pending', index: true },
    decision: {
      reason: { type: String, trim: true, maxlength: 1000 },
      approvedAmount: { type: Number, min: 0, default: 0 },
      decidedBy: String,
      decidedAt: Date,
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

export const ClaimModel = mongoose.models.Claim ?? mongoose.model('Claim', claimSchema);
