import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { listingController } from './listing.controller.js';
import {
  availabilityValidation,
  createListingValidation,
  listingIdValidation,
  listListingsValidation,
  listMineValidation,
  moderationValidation,
  updateListingValidation,
} from './listing.validation.js';

export const listingRouter = Router();

listingRouter.get(
  '/',
  listListingsValidation,
  validate,
  listingController.list,
);
listingRouter.get(
  '/owner/mine',
  authenticate,
  authorize('owner'),
  listMineValidation,
  validate,
  listingController.listMine,
);
listingRouter.get(
  '/admin',
  authenticate,
  authorize('admin'),
  listMineValidation,
  validate,
  listingController.listAdmin,
);
listingRouter.post(
  '/',
  authenticate,
  authorize('owner'),
  createListingValidation,
  validate,
  listingController.create,
);
listingRouter.patch(
  '/:id/moderation',
  authenticate,
  authorize('admin'),
  moderationValidation,
  validate,
  listingController.moderate,
);
listingRouter.put(
  '/:id/availability',
  authenticate,
  authorize('owner'),
  availabilityValidation,
  validate,
  listingController.setAvailability,
);
listingRouter.get(
  '/:id/availability',
  listingIdValidation,
  validate,
  listingController.getAvailability,
);
listingRouter.post(
  '/:id/submit',
  authenticate,
  authorize('owner'),
  listingIdValidation,
  validate,
  listingController.submit,
);
listingRouter.delete(
  '/:id',
  authenticate,
  authorize('owner'),
  listingIdValidation,
  validate,
  listingController.deactivate,
);
listingRouter.patch(
  '/:id',
  authenticate,
  authorize('owner'),
  updateListingValidation,
  validate,
  listingController.update,
);
listingRouter.get(
  '/:id',
  listingIdValidation,
  validate,
  listingController.get,
);
