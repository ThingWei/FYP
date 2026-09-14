import mongoose from 'mongoose';

const threadSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    bookingId: { type: String, required: true, unique: true, index: true },
    listingId: { type: String, required: true, index: true },
    listingTitle: { type: String, required: true, trim: true },
    listingType: { type: String, enum: ['physical', 'service'], required: true },
    renterId: { type: String, required: true, index: true },
    ownerId: { type: String, required: true, index: true },
    participantIds: {
      type: [String],
      required: true,
      validate: {
        validator: (ids) => ids.length === 2 && new Set(ids).size === 2,
        message: 'A thread requires two unique participants',
      },
    },
    status: { type: String, enum: ['open', 'closed'], default: 'open' },
    lastMessageText: { type: String, trim: true, maxlength: 2000, default: '' },
    lastMessageSenderId: { type: String, trim: true, default: '' },
    lastMessageAt: Date,
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

threadSchema.index({ participantIds: 1, lastMessageAt: -1 });

export const ThreadModel =
  mongoose.models.CommunicationThread ??
  mongoose.model('CommunicationThread', threadSchema);
