import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { listingService } from './listing.service.js';

const bodyData = (req) => matchedData(req, { locations: ['body'] });

export const listingController = {
  list: asyncHandler(async (req, res) => {
    const result = await listingService.list(req.query);
    return ok(res, result.items, result.meta);
  }),
  get: asyncHandler(async (req, res) =>
    ok(res, await listingService.get(req.params.id)),
  ),
  create: asyncHandler(async (req, res) =>
    created(res, await listingService.create(bodyData(req), req.user)),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await listingService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await listingService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  update: asyncHandler(async (req, res) =>
    ok(res, await listingService.update(req.params.id, bodyData(req), req.user)),
  ),
  submit: asyncHandler(async (req, res) =>
    ok(res, await listingService.submit(req.params.id, req.user)),
  ),
  deactivate: asyncHandler(async (req, res) =>
    ok(res, await listingService.deactivate(req.params.id, req.user)),
  ),
  getAvailability: asyncHandler(async (req, res) =>
    ok(res, await listingService.getAvailability(req.params.id)),
  ),
  setAvailability: asyncHandler(async (req, res) =>
    ok(
      res,
      await listingService.setAvailability(
        req.params.id,
        bodyData(req),
        req.user,
      ),
    ),
  ),
  moderate: asyncHandler(async (req, res) =>
    ok(
      res,
      await listingService.moderate(
        req.params.id,
        req.body.status,
        req.body.reason,
      ),
    ),
  ),
};
