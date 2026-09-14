import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { bookingService } from './booking.service.js';

export const bookingController = {
  create: asyncHandler(async (req, res) =>
    created(
      res,
      await bookingService.create(
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  get: asyncHandler(async (req, res) =>
    ok(res, await bookingService.get(req.params.id, req.user)),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await bookingService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listOwner: asyncHandler(async (req, res) => {
    const result = await bookingService.listOwner(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await bookingService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  decide: asyncHandler(async (req, res) =>
    ok(res, await bookingService.decide(req.params.id, req.body, req.user)),
  ),
  cancel: asyncHandler(async (req, res) =>
    ok(
      res,
      await bookingService.cancel(req.params.id, req.body.reason, req.user),
    ),
  ),
};
