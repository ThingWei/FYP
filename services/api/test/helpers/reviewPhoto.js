import { UploadAssetModel } from '../../src/modules/upload/upload.model.js';
import { randomUUID } from 'node:crypto';

// Metadata-only private fixtures; never identity or vehicle images.
export async function reviewPhoto(ownerId, purpose = 'verification_holder_photo', publicId) {
  const id = publicId ?? `UPL-${randomUUID().replaceAll('-', '').toUpperCase()}`;
  await UploadAssetModel.create({ publicId: id, uploadedBy: ownerId, purpose, visibility: 'private', originalName: 'synthetic-review.png', contentType: 'image/png', size: 64, storageProvider: 'local', storagePath: `private/tests/${id}`, sha256: 'a'.repeat(64) });
  return `upload://${id}`;
}
