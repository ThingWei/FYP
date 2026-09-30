import mongoose from 'mongoose';

export const NOTIFICATION_CATEGORIES = [
  'booking',
  'message',
  'payment',
  'rental',
  'review',
  'dispute',
  'loyalty',
  'verification',
  'account',
];

const notificationSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    userId: { type: String, required: true, index: true },
    category: {
      type: String,
      enum: NOTIFICATION_CATEGORIES,
      required: true,
      index: true,
    },
    type: { type: String, required: true, trim: true, maxlength: 80 },
    title: { type: String, required: true, trim: true, maxlength: 120 },
    body: { type: String, required: true, trim: true, maxlength: 500 },
    entityType: {
      type: String,
      enum: [
        'booking',
        'rental',
        'payment',
        'thread',
        'message',
        'review',
        'dispute',
        'claim',
        'reward',
        'referral',
        'user',
      ],
      required: true,
    },
    entityId: { type: String, required: true, trim: true, index: true },
    dedupeKey: { type: String, trim: true, maxlength: 180 },
    readAt: Date,
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        value.read = Boolean(value.readAt);
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

notificationSchema.index({ userId: 1, createdAt: -1 });
notificationSchema.index(
  { dedupeKey: 1 },
  { unique: true, sparse: true, name: 'unique_notification_dedupe_key' },
);

export const NotificationModel =
  mongoose.models.Notification ??
  mongoose.model('Notification', notificationSchema);
