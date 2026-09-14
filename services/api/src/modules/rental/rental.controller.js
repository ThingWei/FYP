import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { ok } from '../../core/respond.js';
import { rentalService } from './rental.service.js';

const bodyData = (req) => matchedData(req, { locations: ['body'] });

export const rentalController = {
  get: asyncHandler(async (req, res) =>
    ok(res, await rentalService.get(req.params.id, req.user)),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await rentalService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listOwner: asyncHandler(async (req, res) => {
    const result = await rentalService.listOwner(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await rentalService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  confirmHandover: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.confirmHandover(
        req.params.id,
        bodyData(req),
        req.user,
      ),
    ),
  ),
  startService: asyncHandler(async (req, res) =>
    ok(res, await rentalService.startService(req.params.id, req.user)),
  ),
  requestExtension: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.requestExtension(
        req.params.id,
        bodyData(req),
        req.user,
      ),
    ),
  ),
  decideExtension: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.decideExtension(
        req.params.id,
        req.body,
        req.user,
      ),
    ),
  ),
  submitReturn: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.submitReturn(
        req.params.id,
        bodyData(req),
        req.user,
      ),
    ),
  ),
  confirmReturn: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.confirmReturn(
        req.params.id,
        bodyData(req),
        req.user,
      ),
    ),
  ),
  markServiceDelivered: asyncHandler(async (req, res) =>
    ok(res, await rentalService.markServiceDelivered(req.params.id, req.user)),
  ),
  confirmServiceCompletion: asyncHandler(async (req, res) =>
    ok(
      res,
      await rentalService.confirmServiceCompletion(req.params.id, req.user),
    ),
  ),
};
