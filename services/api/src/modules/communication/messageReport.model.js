import mongoose from 'mongoose';

export const MESSAGE_REPORT_REASONS = [
  'harassment',
  'scam',
  'spam',
  'inappropriate',
  'other',
];

const messageReportSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    messageId: { type: String, required: true, index: true },
    threadId: { type: String, required: true, index: true },
    reporterId: { type: String, required: true, index: true },
    reportedUserId: { type: String, required: true, index: true },
    messageText: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 2000,
    },
    reason: { type: String, enum: MESSAGE_REPORT_REASONS, required: true },
    details: { type: String, trim: true, maxlength: 1000, default: '' },
    status: { type: String, enum: ['open', 'resolved', 'dismissed'], default: 'open' },
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

messageReportSchema.index({ messageId: 1, reporterId: 1 }, { unique: true });

export const MessageReportModel =
  mongoose.models.MessageReport ??
  mongoose.model('MessageReport', messageReportSchema);
