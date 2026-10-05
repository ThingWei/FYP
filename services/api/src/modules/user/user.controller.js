import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { userService } from './user.service.js';

const sessionMetadata = (req) => ({
  ip: req.ip,
  userAgent: [req.get('x-renthub-client'), req.get('user-agent')]
    .filter(Boolean)
    .join(' | '),
});

export const userController = {
  localLogin: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.localLogin(matchedData(req), sessionMetadata(req)),
    )),
  localRegister: asyncHandler(async (req, res) =>
    created(
      res,
      await userService.localRegister(matchedData(req), sessionMetadata(req)),
    )),
  localRefresh: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.localRefresh(matchedData(req), sessionMetadata(req)),
    )),
  localLogout: asyncHandler(async (req, res) =>
    ok(res, await userService.localLogout(req.user))),
  localSessions: asyncHandler(async (req, res) =>
    ok(res, await userService.localSessions(req.user))),
  revokeLocalSession: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.revokeLocalSession(req.user, req.params.sessionId),
    )),
  revokeOtherLocalSessions: asyncHandler(async (req, res) =>
    ok(res, await userService.revokeOtherLocalSessions(req.user))),
  requestLocalPasswordReset: asyncHandler(async (req, res) =>
    ok(res, await userService.requestLocalPasswordReset(matchedData(req)))),
  confirmLocalPasswordReset: asyncHandler(async (req, res) =>
    ok(res, await userService.confirmLocalPasswordReset(matchedData(req)))),

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

  inspectVerificationFrame: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.inspectVerificationFrame(req.user, matchedData(req)),
    ),
  ),

  verificationRequirements: asyncHandler(async (req, res) =>
    ok(
      res,
      await userService.verificationRequirements(
        req.user,
        matchedData(req, { locations: ['query'] }),
      ),
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
