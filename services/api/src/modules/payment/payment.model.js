import mongoose from 'mongoose';

export const PAYMENT_TYPES = [
  'authorization',
  'capture',
  'refund',
  'deposit_release',
  'deposit_deduction',
  'owner_settlement',
];
export const PAYMENT_STATUSES = [
  'pending',
  'authorized',
  'succeeded',
  'failed',
  'voided',
];

const paymentSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    bookingId: { type: String, required: true, index: true },
    payerId: { type: String, required: true, index: true },
    payeeId: { type: String, required: true, index: true },
    type: { type: String, enum: PAYMENT_TYPES, required: true, index: true },
    amount: { type: Number, required: true, min: 0 },
    currency: { type: String, enum: ['MYR'], default: 'MYR' },
    method: { type: String, enum: ['card', 'fpx', 'wallet', 'system'], required: true },
    status: { type: String, enum: PAYMENT_STATUSES, required: true, index: true },
    gatewayReference: { type: String, required: true, trim: true },
    idempotencyKey: { type: String, required: true, unique: true, trim: true },
    parentTransactionId: { type: String, trim: true, default: '' },
    reason: { type: String, trim: true, maxlength: 500, default: '' },
    simulated: { type: Boolean, default: true, immutable: true },
    metadata: { type: Map, of: String, default: {} },
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

paymentSchema.index({ bookingId: 1, type: 1, createdAt: -1 });

export const PaymentModel =
  mongoose.models.Payment ?? mongoose.model('Payment', paymentSchema);
