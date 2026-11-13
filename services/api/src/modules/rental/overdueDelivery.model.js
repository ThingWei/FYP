import mongoose from 'mongoose';

// Private queue: contains account references and delivery state, never OCR,
// addresses, provider errors, credentials or serialized email content.
const schema = new mongoose.Schema({
  key: { type: String, required: true, unique: true },
  rentalId: { type: String, required: true, index: true },
  userId: { type: String, required: true },
  role: { type: String, enum: ['renter', 'owner', 'admin'], required: true },
  stage: { type: String, enum: ['initial', 'followup', 'admin'], required: true },
  channel: { type: String, enum: ['email', 'notification'], required: true },
  deadline: { type: Date, required: true },
  status: { type: String, enum: ['pending', 'sending', 'sent', 'retry', 'failed', 'uncertain', 'skipped', 'cancelled', 'superseded'], default: 'pending', index: true },
  attempts: { type: Number, default: 0 },
  nextAttemptAt: { type: Date, required: true, index: true },
  leaseToken: String,
  leaseUntil: Date,
  sentAt: Date,
  result: { type: String, enum: ['disabled', 'opted_out', 'recipient_unavailable', 'rejected', 'temporary_failure', 'unknown_delivery', 'state_changed', 'newer_reminder', 'delivered'] },
}, { timestamps: true, strict: 'throw' });
schema.index({ status: 1, nextAttemptAt: 1, _id: 1 });
export const OverdueDeliveryModel = mongoose.models.OverdueDelivery ?? mongoose.model('OverdueDelivery', schema);
