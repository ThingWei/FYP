import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { disputeService } from './dispute.service.js';

function body(req) {
  return matchedData(req, { locations: ['body'] });
}

export const disputeController = {
  create: asyncHandler(async (req, res) =>
    created(res, await disputeService.create(body(req), req.user)),
  ),
  get: asyncHandler(async (req, res) =>
    ok(res, await disputeService.get(req.params.id, req.user)),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await disputeService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  respond: asyncHandler(async (req, res) =>
    ok(res, await disputeService.respond(req.params.id, body(req), req.user)),
  ),
  createClaim: asyncHandler(async (req, res) =>
    created(res, await disputeService.createClaim(req.params.id, body(req), req.user)),
  ),
  listMyClaims: asyncHandler(async (req, res) => {
    const result = await disputeService.listMyClaims(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await disputeService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  listAdminClaims: asyncHandler(async (req, res) => {
    const result = await disputeService.listAdminClaims(req.query);
    return ok(res, result.items, result.meta);
  }),
  reviewStatus: asyncHandler(async (req, res) =>
    ok(
      res,
      await disputeService.reviewStatus(req.params.id, body(req), req.user),
    ),
  ),
  resolve: asyncHandler(async (req, res) =>
    ok(res, await disputeService.resolve(req.params.id, body(req), req.user)),
  ),
  decideClaim: asyncHandler(async (req, res) =>
    ok(
      res,
      await disputeService.decideClaim(req.params.claimId, body(req), req.user),
    ),
  ),
};
