import { uploadRouter } from './upload.routes.js';
import { UploadAssetModel } from './upload.model.js';
import { uploadService } from './upload.service.js';

export const uploadModule = {
  Model: UploadAssetModel,
  service: uploadService,
  router: uploadRouter,
};
