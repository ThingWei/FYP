import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { loyaltyController } from './loyalty.controller.js';
import {
  adminLedgerValidation,
  adminReferralValidation,
  configValidation,
  redeemValidation,
  referralValidation,
} from './loyalty.validation.js';

export const loyaltyRouter = Router();
loyaltyRouter.use(authenticate);
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
