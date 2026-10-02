import mongoose from 'mongoose';

const attachmentSchema = new mongoose.Schema(
  {
    kind: { type: String, enum: ['image'], required: true },
    reference: {
      type: String,
      required: true,
      match: /^upload:\/\/UPL-[A-Z0-9]+$/i,
    },
    contentUrl: { type: String, required: true, trim: true },
    contentType: {
      type: String,
      enum: ['image/jpeg', 'image/png', 'image/webp'],
      required: true,
    },
    filename: { type: String, required: true, trim: true, maxlength: 180 },
    size: { type: Number, required: true, min: 1 },
  },
  { _id: false },
);

const messageSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    threadId: { type: String, required: true, index: true },
    senderId: { type: String, required: true, index: true },
    recipientId: { type: String, required: true, index: true },
    text: { type: String, trim: true, maxlength: 2000, default: '' },
    attachment: { type: attachmentSchema, default: undefined },
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

messageSchema.pre('validate', function validateContent() {
  if (!this.text?.trim() && !this.attachment) {
    this.invalidate('text', 'A message requires text or an attachment');
  }
});

messageSchema.index({ threadId: 1, createdAt: -1 });
messageSchema.index({ recipientId: 1, readAt: 1 });

export const MessageModel =
  mongoose.models.Message ?? mongoose.model('Message', messageSchema);
