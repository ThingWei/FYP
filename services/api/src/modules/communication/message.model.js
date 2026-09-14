import mongoose from 'mongoose';

const messageSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    threadId: { type: String, required: true, index: true },
    senderId: { type: String, required: true, index: true },
    recipientId: { type: String, required: true, index: true },
    text: { type: String, required: true, trim: true, minlength: 1, maxlength: 2000 },
    readAt: Date,
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

messageSchema.index({ threadId: 1, createdAt: -1 });
messageSchema.index({ recipientId: 1, readAt: 1 });

export const MessageModel =
  mongoose.models.Message ?? mongoose.model('Message', messageSchema);
