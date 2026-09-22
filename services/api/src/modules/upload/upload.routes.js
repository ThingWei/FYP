import { Router } from 'express';
import multer from 'multer';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { authenticate } from '../../middleware/auth.js';
import { uploadController } from './upload.controller.js';

const receiveFile = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: env.maxUploadBytes, files: 1, fields: 4 },
}).single('file');

const multipart = (req, res, next) => receiveFile(req, res, (error) => {
  if (!error) return next();
  if (error.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('File exceeds the upload size limit', 413, 'FILE_TOO_LARGE'));
  }
  return next(new AppError('Invalid file upload', 400, 'INVALID_UPLOAD'));
});

export const uploadRouter = Router();
uploadRouter.post('/', authenticate, multipart, uploadController.create);
uploadRouter.get('/public/:id/content', uploadController.publicContent);
uploadRouter.get('/:id/content', authenticate, uploadController.privateContent);
uploadRouter.delete('/:id', authenticate, uploadController.remove);
