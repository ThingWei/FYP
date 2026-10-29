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
    location: { type: new mongoose.Schema({
      latitude: { type: Number, required: true, min: -90, max: 90 },
      longitude: { type: Number, required: true, min: -180, max: 180 },
      label: { type: String, required: true, trim: true, maxlength: 250 },
    }, { _id: false }), default: undefined },
    deletedFor: { type: [String], default: [] },
    recalledAt: Date,
    editedAt: Date,
    revision: { type: Number, default: 0, min: 0 },
    clientMessageId: { type: String, maxlength: 120 },
    sendFingerprint: { type: String, select: false },
    originalContent: { type: mongoose.Schema.Types.Mixed, select: false },
    editHistory: { type: [mongoose.Schema.Types.Mixed], select: false, default: undefined },
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
        delete value.deletedFor;
        delete value.originalContent;
        delete value.editHistory;
        delete value.clientMessageId;
        delete value.sendFingerprint;
        if (value.recalledAt) { value.text = ''; delete value.attachment; delete value.location; }
        return value;
      },
    },
  },
);

messageSchema.pre('validate', function validateContent() {
  if (!this.recalledAt && !this.text?.trim() && !this.attachment && !this.location) {
    this.invalidate('text', 'A message requires text or an attachment');
  }
});

messageSchema.index({ threadId: 1, createdAt: -1 });
messageSchema.index({ threadId: 1, createdAt: -1, _id: -1 });
messageSchema.index({ recipientId: 1, readAt: 1 });
messageSchema.index({senderId:1,clientMessageId:1},{unique:true,partialFilterExpression:{clientMessageId:{$type:'string'}}});

export const MessageModel =
  mongoose.models.Message ?? mongoose.model('Message', messageSchema);
