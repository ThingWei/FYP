import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { reviewController } from './review.controller.js';
import {
  adminReviewListValidation,
  createReviewValidation,
  editReviewValidation,
  flagReviewValidation,
  listingReviewsValidation,
  moderationValidation,
  reviewListValidation,
  subjectSummaryValidation,
} from './review.validation.js';

export const reviewRouter = Router();

reviewRouter.get(
  '/listing/:listingId',
  listingReviewsValidation,
  validate,
  reviewController.listListing,
);
reviewRouter.get(
  '/subjects/:subjectId/summary',
  subjectSummaryValidation,
  validate,
  reviewController.summary,
);

reviewRouter.use(authenticate);
reviewRouter.get('/mine', reviewListValidation, validate, reviewController.listMine);
reviewRouter.get(
  '/received',
  reviewListValidation,
  validate,
  reviewController.listReceived,
);
reviewRouter.get(
  '/admin',
  authorize('admin'),
  adminReviewListValidation,
  validate,
  reviewController.listAdmin,
);
reviewRouter.post('/', createReviewValidation, validate, reviewController.create);
reviewRouter.patch('/:id', editReviewValidation, validate, reviewController.edit);
reviewRouter.post(
  '/:id/flag',
  flagReviewValidation,
  validate,
  reviewController.flag,
);
reviewRouter.patch(
  '/:id/moderation',
  authorize('admin'),
  moderationValidation,
  validate,
  reviewController.moderate,
);
