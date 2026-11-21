import mongoose from 'mongoose';

const schema = new mongoose.Schema({
  publicId: { type: String, required: true, unique: true },
  disputeId: { type: String, required: true, index: true },
  senderId: { type: String, required: true },
  senderName: { type: String, required: true },
  role: { type: String, enum: ['renter', 'owner', 'admin'], required: true },
  text: { type: String, trim: true, maxlength: 2000, default: '' },
  evidence: { type: [String], default: [] },
  idempotencyKey: { type: String, required: true, select: false },
  payloadHash: { type: String, required: true, select: false },
}, { timestamps: true, strict: 'throw' });
schema.index({ disputeId: 1, senderId: 1, idempotencyKey: 1 }, { unique: true });
schema.index({ disputeId: 1, createdAt: -1, publicId: -1 });
schema.index({ evidence: 1, disputeId: 1 });

export const DisputeMessageModel = mongoose.models.DisputeMessage ?? mongoose.model('DisputeMessage', schema);
