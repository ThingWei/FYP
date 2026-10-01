import mongoose from 'mongoose';

const passwordResetSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    codeHash: { type: String, required: true, select: false },
    expiresAt: { type: Date, required: true, index: { expires: 0 } },
    attempts: { type: Number, min: 0, default: 0 },
    consumedAt: { type: Date, default: null },
  },
  { timestamps: true },
);

passwordResetSchema.index({ email: 1, createdAt: -1 });

export const PasswordResetModel =
  mongoose.models.PasswordReset ??
  mongoose.model('PasswordReset', passwordResetSchema);
