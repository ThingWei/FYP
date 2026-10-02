import mongoose from 'mongoose';

const localSessionSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    refreshTokenHash: { type: String, required: true, select: false },
    expiresAt: { type: Date, required: true, index: { expires: 0 } },
    revokedAt: { type: Date, default: null },
    lastUsedAt: Date,
    userAgent: { type: String, trim: true, maxlength: 500, default: '' },
    createdIp: { type: String, trim: true, maxlength: 120, default: '' },
    lastIp: { type: String, trim: true, maxlength: 120, default: '' },
  },
  { timestamps: true },
);

localSessionSchema.index({ userId: 1, revokedAt: 1, expiresAt: 1 });

export const LocalSessionModel =
  mongoose.models.LocalSession ??
  mongoose.model('LocalSession', localSessionSchema);
