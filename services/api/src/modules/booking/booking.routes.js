import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { bookingController } from './booking.controller.js';
import {
  bookingIdValidation,
  cancellationValidation,
  createBookingValidation,
  decisionValidation,
  listBookingsValidation,
} from './booking.validation.js';

export const bookingRouter = Router();

bookingRouter.post(
  '/',
  authenticate,
  authorize('renter'),
  createBookingValidation,
  validate,
  bookingController.create,
);
bookingRouter.get(
  '/mine',
  authenticate,
  authorize('renter'),
  listBookingsValidation,
  validate,
  bookingController.listMine,
);
bookingRouter.get(
  '/owner',
  authenticate,
  authorize('owner'),
  listBookingsValidation,
  validate,
  bookingController.listOwner,
);
bookingRouter.get(
  '/admin',
  authenticate,
  authorize('admin'),
  listBookingsValidation,
  validate,
  bookingController.listAdmin,
);
bookingRouter.patch(
  '/:id/decision',
  authenticate,
  authorize('owner'),
  decisionValidation,
  validate,
  bookingController.decide,
);
bookingRouter.post(
  '/:id/cancel',
  authenticate,
  authorize('renter'),
  cancellationValidation,
  validate,
  bookingController.cancel,
);
bookingRouter.get(
  '/:id',
  authenticate,
  bookingIdValidation,
  validate,
  bookingController.get,
);
