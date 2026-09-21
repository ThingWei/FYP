import mongoose from 'mongoose';

export const REPORT_TARGET_TYPES = ['user', 'listing', 'review'];
export const REPORT_REASONS = [
  'misleading',
  'prohibited',
  'scam',
  'harassment',
  'inappropriate',
  'other',
];

const moderationReportSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      index: true,
      default: () => `RPT-MOD-${new mongoose.Types.ObjectId()}`,
    },
    targetType: { type: String, enum: REPORT_TARGET_TYPES, required: true, index: true },
    targetId: { type: String, required: true, trim: true, index: true },
    targetLabel: { type: String, required: true, trim: true, maxlength: 160 },
    reporterId: { type: String, required: true, trim: true, index: true },
    reason: { type: String, enum: REPORT_REASONS, required: true },
    details: { type: String, trim: true, maxlength: 1000, default: '' },
    status: {
      type: String,
      enum: ['open', 'resolved', 'dismissed'],
      default: 'open',
      index: true,
    },
    resolution: { type: String, trim: true, maxlength: 1000, default: '' },
    reviewedBy: { type: String, trim: true, default: '' },
    reviewedAt: Date,
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

moderationReportSchema.index(
  { targetType: 1, targetId: 1, reporterId: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: 'open' } },
);

export const ModerationReportModel =
  mongoose.models.ModerationReport ??
  mongoose.model('ModerationReport', moderationReportSchema);
