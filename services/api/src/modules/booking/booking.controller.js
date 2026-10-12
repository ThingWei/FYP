import { presentBooking } from '../../core/location.js';
import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { bookingService } from './booking.service.js';

export const bookingController = {
  locations: asyncHandler(async (req, res) => ok(res, await bookingService.locations(req.params.id, req.user))),
  create: asyncHandler(async (req, res) =>
    created(
      res,
      presentBooking(await bookingService.create(
        matchedData(req, { locations: ['body'] }),
        req.user,
      ), req.user),
    ),
  ),
  get: asyncHandler(async (req, res) =>
    ok(res, presentBooking(await bookingService.get(req.params.id, req.user), req.user)),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await bookingService.listMine(req.user, req.query);
    return ok(res, result.items.map((item) => presentBooking(item, req.user)), result.meta);
  }),
  listOwner: asyncHandler(async (req, res) => {
    const result = await bookingService.listOwner(req.user, req.query);
    return ok(res, result.items.map((item) => presentBooking(item, req.user)), result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await bookingService.listAdmin(req.query);
    return ok(res, result.items.map((item) => presentBooking(item, req.user)), result.meta);
  }),
  decide: asyncHandler(async (req, res) =>
    ok(res, presentBooking(await bookingService.decide(req.params.id, req.body, req.user), req.user)),
  ),
  cancel: asyncHandler(async (req, res) =>
    ok(
      res,
      presentBooking(await bookingService.cancel(req.params.id, req.body.reason, req.user), req.user),
    ),
  ),
};
