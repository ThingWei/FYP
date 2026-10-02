import mongoose from 'mongoose';

export const UPLOAD_PURPOSES = [
  'listing_image',
  'avatar',
  'verification_document',
  'handover_evidence',
  'return_evidence',
  'dispute_evidence',
  'claim_evidence',
  'message_image',
];

const uploadAssetSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      unique: true,
      required: true,
      default: () => `UPL-${new mongoose.Types.ObjectId().toString().toUpperCase()}`,
    },
    uploadedBy: { type: String, required: true, index: true },
    purpose: { type: String, enum: UPLOAD_PURPOSES, required: true, index: true },
    visibility: { type: String, enum: ['public', 'private'], required: true },
    originalName: { type: String, required: true, trim: true, maxlength: 180 },
    contentType: {
      type: String,
      enum: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
      required: true,
    },
    size: { type: Number, required: true, min: 1 },
    storageProvider: { type: String, enum: ['local', 'firebase'], required: true },
    storagePath: { type: String, required: true, unique: true },
    sha256: { type: String, required: true, minlength: 64, maxlength: 64 },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        value.reference = `upload://${value.publicId}`;
        value.contentUrl = value.visibility === 'public'
          ? `/api/v1/uploads/public/${value.publicId}/content`
          : `/api/v1/uploads/${value.publicId}/content`;
        delete value._id;
        delete value.__v;
        delete value.storagePath;
        delete value.sha256;
        return value;
      },
    },
  },
);

uploadAssetSchema.index({ uploadedBy: 1, createdAt: -1 });

export const UploadAssetModel =
  mongoose.models.UploadAsset ?? mongoose.model('UploadAsset', uploadAssetSchema);
