import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { uploadService } from './upload.service.js';

async function sendContent(res, asset) {
  const buffer = await uploadService.read(asset);
  res.set({
    'content-type': asset.contentType,
    'content-length': String(buffer.length),
    'content-disposition': `inline; filename="${asset.originalName.replaceAll('"', '')}"`,
    'cache-control': asset.visibility === 'public'
      ? 'public, max-age=31536000, immutable'
      : 'private, no-store',
  });
  return res.send(buffer);
}

export const uploadController = {
  create: asyncHandler(async (req, res) =>
    created(res, await uploadService.create(req.user, req.body.purpose, req.file)),
  ),
  publicContent: asyncHandler(async (req, res) =>
    sendContent(res, await uploadService.getPublic(req.params.id)),
  ),
  privateContent: asyncHandler(async (req, res) =>
    sendContent(res, await uploadService.getPrivate(req.user, req.params.id)),
  ),
  remove: asyncHandler(async (req, res) =>
    ok(res, await uploadService.remove(req.user, req.params.id)),
  ),
};
