import mongoose from 'mongoose';

const schema = new mongoose.Schema({
  sourceId: { type: String, required: true, unique: true },
  enabled: { type: Boolean, default: false },
  leaseToken: String,
  leaseUntil: Date,
  lastAttemptAt: Date,
  lastSuccessAt: Date,
  nextRunAt: Date,
  status: { type: String, default: 'disabled' },
  errorCode: { type: String, default: '' },
  consecutiveFailures: { type: Number, default: 0 },
  acceptedCount: { type: Number, default: 0 },
  skippedCount: { type: Number, default: 0 },
  skipReasons: { type: [String], default: [] },
  accessCheckedAt: Date,
  accessCheckedBy: String,
}, { timestamps: true, strict: 'throw', collection: 'pricing_sources' });

export const PriceSourceModel = mongoose.models.PriceSource ?? mongoose.model('PriceSource', schema);
