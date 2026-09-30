import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { userService } from './user.service.js';

export const userController = {
  startSession: asyncHandler(async (req, res) => {
    const result = await userService.startSession(req.user);
    return result.created ? created(res, result.user) : ok(res, result.user);
  }),

  me: asyncHandler(async (req, res) =>
    ok(res, await userService.getMe(req.user)),
  ),

  deactivateMe: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.deactivateMe(req.user, matchedData(req).reason),
    ),
  ),

  updateMe: asyncHandler(async (req, res) =>
    ok(res, await userService.updateMe(req.user, matchedData(req))),
  ),

  selectRole: asyncHandler(async (req, res) =>
    ok(res, await userService.selectRole(req.user, req.body.role)),
  ),

  submitVerification: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.submitVerification(req.user, matchedData(req)),
    ),
  ),

  reviewVerification: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.reviewVerification(
        req.params.userId,
        matchedData(req),
        req.user,
      ),
    ),
  ),

  blockUser: asyncHandler(async (req, res) =>
    ok(res, await userService.blockUser(req.user, req.params.userId)),
  ),

  unblockUser: asyncHandler(async (req, res) =>
    ok(res, await userService.unblockUser(req.user, req.params.userId)),
  ),

  savedListings: asyncHandler(async (req, res) =>
    ok(res, await userService.savedListings(req.user)),
  ),

  saveListing: asyncHandler(async (req, res) =>
    ok(res, await userService.saveListing(req.user, req.params.listingId)),
  ),

  removeSavedListing: asyncHandler(async (req, res) =>
    ok(res, await userService.removeSavedListing(req.user, req.params.listingId)),
  ),

  comparison: asyncHandler(async (req, res) =>
    ok(res, await userService.comparison(req.user)),
  ),

  updateComparison: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.updateComparison(req.user, req.body.listingIds),
    ),
  ),

  publicProfile: asyncHandler(async (req, res) =>
    ok(res, await userService.getPublic(req.params.id)),
  ),

  list: asyncHandler(async (req, res) => {
    const result = await userService.list(req.query);
    return ok(res, result.items, result.meta);
  }),

  changeAccountStatus: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.changeAccountStatus(
        req.params.id,
        req.body.status,
        req.body.reason,
        req.user,
      ),
    ),
  ),
};
