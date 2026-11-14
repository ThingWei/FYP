import { AppError } from '../../core/errors.js';
import { UploadAssetModel } from './upload.model.js';

export async function requirePrivateReviewPhoto(ownerId, reference, purpose) {
  if (typeof reference !== 'string' || !/^upload:\/\/UPL-[A-Z0-9]+$/.test(reference) ||
      !await UploadAssetModel.exists({ publicId: reference.slice(9), uploadedBy: ownerId, purpose, visibility: 'private', contentType: { $in: ['image/jpeg', 'image/png', 'image/webp'] } })) {
    throw new AppError('Add an owned, private photo for this review. Choose the correct photo upload field.', 422, 'PRIVATE_REVIEW_PHOTO_REQUIRED');
  }
}
