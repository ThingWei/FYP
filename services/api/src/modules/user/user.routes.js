import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { userController } from './user.controller.js';
import {
  accountStatusValidation,
  accountDeactivationValidation,
  comparisonValidation,
  listValidation,
  profileValidation,
  publicUserValidation,
  roleValidation,
  savedListingValidation,
  targetUserValidation,
  verificationDecisionValidation,
  verificationSubmissionValidation,
} from './user.validation.js';

export const userRouter = Router();

userRouter.post('/session', authenticate, userController.startSession);
userRouter.get('/me', authenticate, userController.me);
userRouter.post(
  '/me/deactivate',
  authenticate,
  accountDeactivationValidation,
  validate,
  userController.deactivateMe,
);
userRouter.patch(
  '/me',
  authenticate,
  profileValidation,
  validate,
  userController.updateMe,
);
userRouter.patch(
  '/me/active-role',
  authenticate,
  roleValidation,
  validate,
  userController.selectRole,
);
userRouter.post(
  '/me/verification',
  authenticate,
  verificationSubmissionValidation,
  validate,
  userController.submitVerification,
);
userRouter.post(
  '/me/blocked-users/:userId',
  authenticate,
  targetUserValidation,
  validate,
  userController.blockUser,
);
userRouter.delete(
  '/me/blocked-users/:userId',
  authenticate,
  targetUserValidation,
  validate,
  userController.unblockUser,
);
userRouter.get(
  '/me/saved-listings',
  authenticate,
  userController.savedListings,
);
userRouter.put(
  '/me/saved-listings/:listingId',
  authenticate,
  savedListingValidation,
  validate,
  userController.saveListing,
);
userRouter.delete(
  '/me/saved-listings/:listingId',
  authenticate,
  savedListingValidation,
  validate,
  userController.removeSavedListing,
);
userRouter.get('/me/comparison', authenticate, userController.comparison);
userRouter.put(
  '/me/comparison',
  authenticate,
  comparisonValidation,
  validate,
  userController.updateComparison,
);
userRouter.get(
  '/public/:id',
  publicUserValidation,
  validate,
  userController.publicProfile,
);
userRouter.get(
  '/',
  authenticate,
  authorize('admin'),
  listValidation,
  validate,
  userController.list,
);
userRouter.patch(
  '/:userId/verification',
  authenticate,
  authorize('admin'),
  verificationDecisionValidation,
  validate,
  userController.reviewVerification,
);
userRouter.patch(
  '/:id/status',
  authenticate,
  authorize('admin'),
  accountStatusValidation,
  validate,
  userController.changeAccountStatus,
);
