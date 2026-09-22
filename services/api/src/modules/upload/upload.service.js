import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { AppError } from '../../core/errors.js';
import { storageAdapter } from '../../integrations/storageAdapter.js';
import { ClaimModel } from '../dispute/claim.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { UserModel } from '../user/user.model.js';
import { UploadAssetModel, UPLOAD_PURPOSES } from './upload.model.js';

const PUBLIC_PURPOSES = new Set(['listing_image', 'avatar']);
const TYPES = [
  { type: 'image/jpeg', extension: '.jpg', matches: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  { type: 'image/png', extension: '.png', matches: (b) => b.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) },
  { type: 'image/webp', extension: '.webp', matches: (b) => b.subarray(0, 4).toString() === 'RIFF' && b.subarray(8, 12).toString() === 'WEBP' },
  { type: 'application/pdf', extension: '.pdf', matches: (b) => b.subarray(0, 5).toString() === '%PDF-' },
];

function detectedType(buffer) {
  return TYPES.find((candidate) => candidate.matches(buffer));
}

async function participantMayRead(identity, reference) {
  if (await RentalModel.exists({
    $and: [
      { $or: [{ renterId: identity.authId }, { ownerId: identity.authId }] },
      {
        $or: [
          { 'handover.evidence': reference },
          { 'returnSubmission.evidence': reference },
        ],
      },
    ],
  })) return true;
  if (await DisputeModel.exists({
    $and: [
      {
        $or: [
          { raisedById: identity.authId },
          { respondentId: identity.authId },
        ],
      },
      { $or: [{ evidence: reference }, { 'responses.evidence': reference }] },
    ],
  })) return true;
  return Boolean(await ClaimModel.exists({
    $or: [{ ownerId: identity.authId }, { renterId: identity.authId }],
    evidence: reference,
  }));
}

export const uploadService = {
  async assertOwnedReferences(identity, references, purposes) {
    const stored = (references ?? []).filter(
      (item) => item.startsWith('upload://') || item.startsWith('/api/v1/uploads/'),
    );
    if (!stored.length) return;
    const ids = stored.map((reference) => {
      const match = reference.match(/UPL-[A-Z0-9]+/i);
      return match?.[0];
    });
    if (ids.some((id) => !id)) {
      throw new AppError('Invalid upload reference', 400, 'INVALID_UPLOAD_REFERENCE');
    }
    const count = await UploadAssetModel.countDocuments({
      publicId: { $in: ids },
      uploadedBy: identity.authId,
      purpose: { $in: purposes },
    });
    if (count !== new Set(ids).size) {
      throw new AppError(
        'An upload is missing, belongs to another account, or has the wrong purpose',
        400,
        'INVALID_UPLOAD_REFERENCE',
      );
    }
  },

  async create(identity, purpose, file) {
    if (!UPLOAD_PURPOSES.includes(purpose)) {
      throw new AppError('Invalid upload purpose', 400, 'INVALID_UPLOAD_PURPOSE');
    }
    if (!file?.buffer?.length) {
      throw new AppError('A file is required', 400, 'FILE_REQUIRED');
    }
    const detected = detectedType(file.buffer);
    if (!detected) {
      throw new AppError('Only JPEG, PNG, WebP, and PDF files are accepted', 415, 'UNSUPPORTED_FILE');
    }
    if (purpose === 'listing_image' || purpose === 'avatar') {
      if (!detected.type.startsWith('image/')) {
        throw new AppError('This upload purpose requires an image', 415, 'IMAGE_REQUIRED');
      }
    }
    if (purpose === 'verification_document' && detected.type === 'application/pdf') {
      throw new AppError('Identity documents must be JPEG, PNG, or WebP images', 415, 'IMAGE_REQUIRED');
    }
    const publicId = `UPL-${randomUUID().replaceAll('-', '').toUpperCase()}`;
    const visibility = PUBLIC_PURPOSES.has(purpose) ? 'public' : 'private';
    const storagePath = `${visibility}/${identity.authId.replace(/[^a-z0-9_-]/gi, '_')}/${publicId}${detected.extension}`;
    const stored = await storageAdapter.upload({
      storagePath,
      buffer: file.buffer,
      contentType: detected.type,
      isPublic: visibility === 'public',
    });
    try {
      return await UploadAssetModel.create({
        publicId,
        uploadedBy: identity.authId,
        purpose,
        visibility,
        originalName: path
          .basename(file.originalname || `upload${detected.extension}`)
          .replace(/[\u0000-\u001f\u007f]/g, '_'),
        contentType: detected.type,
        size: file.size,
        storageProvider: stored.provider,
        storagePath,
        sha256: storageAdapter.checksum(file.buffer),
      });
    } catch (error) {
      await storageAdapter.delete(storagePath);
      throw error;
    }
  },

  async getPublic(id) {
    const asset = await UploadAssetModel.findOne({ publicId: id, visibility: 'public' });
    if (!asset) throw new AppError('Upload not found', 404, 'NOT_FOUND');
    return asset;
  },

  async getPrivate(identity, id) {
    const asset = await UploadAssetModel.findOne({ publicId: id, visibility: 'private' });
    if (!asset) throw new AppError('Upload not found', 404, 'NOT_FOUND');
    const isAdmin = identity.roles?.includes('admin');
    const reference = `upload://${asset.publicId}`;
    if (asset.uploadedBy !== identity.authId && !isAdmin && !(await participantMayRead(identity, reference))) {
      throw new AppError('You cannot access this upload', 403, 'FORBIDDEN');
    }
    return asset;
  },

  async remove(identity, id) {
    const asset = await UploadAssetModel.findOne({ publicId: id });
    if (!asset) throw new AppError('Upload not found', 404, 'NOT_FOUND');
    if (asset.uploadedBy !== identity.authId && !identity.roles?.includes('admin')) {
      throw new AppError('You cannot delete this upload', 403, 'FORBIDDEN');
    }
    const reference = `upload://${asset.publicId}`;
    const publicPath = `/api/v1/uploads/public/${asset.publicId}/content`;
    const used = await Promise.all([
      UserModel.exists({
        $or: [
          { avatarUrl: publicPath },
          { 'verification.documentRefs': reference },
        ],
      }),
      ListingModel.exists({ images: publicPath }),
      RentalModel.exists({
        $or: [
          { 'handover.evidence': reference },
          { 'returnSubmission.evidence': reference },
        ],
      }),
      DisputeModel.exists({
        $or: [{ evidence: reference }, { 'responses.evidence': reference }],
      }),
      ClaimModel.exists({ evidence: reference }),
    ]);
    if (used.some(Boolean)) {
      throw new AppError('This upload is already attached to a record', 409, 'UPLOAD_IN_USE');
    }
    await storageAdapter.delete(asset.storagePath);
    await asset.deleteOne();
    return { id: asset.publicId, deleted: true };
  },

  read(asset) {
    return storageAdapter.download(asset.storagePath);
  },
};
