import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { disputeController } from './dispute.controller.js';
import {
  claimCreateValidation,
  claimDecisionValidation,
  claimListValidation,
  createDisputeValidation,
  disputeDetailValidation,
  disputeListValidation,
  resolveValidation,
  responseValidation,
  reviewStatusValidation,
} from './dispute.validation.js';

export const disputeRouter = Router();
disputeRouter.use(authenticate);

disputeRouter.get('/mine', disputeListValidation, validate, disputeController.listMine);
disputeRouter.get(
  '/claims/mine',
  claimListValidation,
  validate,
  disputeController.listMyClaims,
);
disputeRouter.get(
  '/admin',
  authorize('admin'),
  disputeListValidation,
  validate,
  disputeController.listAdmin,
);
disputeRouter.get(
  '/claims/admin',
  authorize('admin'),
  claimListValidation,
  validate,
  disputeController.listAdminClaims,
);
disputeRouter.patch(
  '/claims/:claimId/decision',
  authorize('admin'),
  claimDecisionValidation,
  validate,
  disputeController.decideClaim,
);
disputeRouter.post('/', createDisputeValidation, validate, disputeController.create);
disputeRouter.get('/:id', disputeDetailValidation, validate, disputeController.get);
disputeRouter.post(
  '/:id/responses',
  responseValidation,
  validate,
  disputeController.respond,
);
disputeRouter.post(
  '/:id/claims',
  authorize('owner'),
  claimCreateValidation,
  validate,
  disputeController.createClaim,
);
disputeRouter.patch(
  '/:id/review-status',
  authorize('admin'),
  reviewStatusValidation,
  validate,
  disputeController.reviewStatus,
);
disputeRouter.patch(
  '/:id/resolve',
  authorize('admin'),
  resolveValidation,
  validate,
  disputeController.resolve,
);
