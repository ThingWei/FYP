import { Router } from 'express';
import { body, param } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { ok } from '../../core/respond.js';
import { checkoutRewards, applyCheckoutReward } from './checkoutRewards.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { loyaltyController } from './loyalty.controller.js';
import { paginationValidation } from '../communication/communication.validation.js';
import {
  adminLedgerValidation,
  adminReferralValidation,
  configValidation,
  redeemValidation,
  referralValidation,
} from './loyalty.validation.js';

export const loyaltyRouter = Router();
loyaltyRouter.use(authenticate);
const checkoutId = param('bookingId').matches(/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/);
loyaltyRouter.get('/checkout/:bookingId', authorize('renter'), checkoutId, validate, asyncHandler(async (req, res) => ok(res, await checkoutRewards(req.user, req.params.bookingId))));
loyaltyRouter.put('/checkout/:bookingId', authorize('renter'), checkoutId, body('rewardId').isString().isLength({ max: 100 }), validate, asyncHandler(async (req, res) => ok(res, await applyCheckoutReward(req.user, req.params.bookingId, req.body.rewardId))));
loyaltyRouter.get('/entries', paginationValidation, validate, loyaltyController.entries);
loyaltyRouter.get('/summary', loyaltyController.summary);
loyaltyRouter.post('/redeem', redeemValidation, validate, loyaltyController.redeem);
loyaltyRouter.post(
  '/referrals/apply',
  referralValidation,
  validate,
  loyaltyController.applyReferral,
);
loyaltyRouter.get(
  '/admin/config',
  authorize('admin'),
  loyaltyController.getConfig,
);
loyaltyRouter.put(
  '/admin/config',
  authorize('admin'),
  configValidation,
  validate,
  loyaltyController.updateConfig,
);
loyaltyRouter.get(
  '/admin/ledger',
  authorize('admin'),
  adminLedgerValidation,
  validate,
  loyaltyController.listAdminEntries,
);
loyaltyRouter.get(
  '/admin/referrals',
  authorize('admin'),
  adminReferralValidation,
  validate,
  loyaltyController.listReferrals,
);
