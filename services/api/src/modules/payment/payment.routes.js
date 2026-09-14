import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { paymentController } from './payment.controller.js';
import {
  authorizationValidation,
  bookingPaymentsValidation,
  listPaymentsValidation,
  refundValidation,
} from './payment.validation.js';

export const paymentRouter = Router();

paymentRouter.post(
  '/authorizations',
  authenticate,
  authorize('renter'),
  authorizationValidation,
  validate,
  paymentController.authorize,
);
paymentRouter.get(
  '/mine',
  authenticate,
  listPaymentsValidation,
  validate,
  paymentController.listMine,
);
paymentRouter.get(
  '/booking/:bookingId',
  authenticate,
  bookingPaymentsValidation,
  validate,
  paymentController.listBooking,
);
paymentRouter.get(
  '/',
  authenticate,
  authorize('admin'),
  listPaymentsValidation,
  validate,
  paymentController.listAdmin,
);
paymentRouter.post(
  '/:id/refunds',
  authenticate,
  authorize('admin'),
  refundValidation,
  validate,
  paymentController.refund,
);
