import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { paymentService } from './payment.service.js';

export const paymentController = {
  authorize: asyncHandler(async (req, res) =>
    created(
      res,
      await paymentService.authorize(
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await paymentService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listBooking: asyncHandler(async (req, res) =>
    ok(
      res,
      await paymentService.listBooking(req.params.bookingId, req.user),
    ),
  ),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await paymentService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  refund: asyncHandler(async (req, res) =>
    created(
      res,
      await paymentService.refund(
        req.params.id,
        matchedData(req, { locations: ['body'] }),
      ),
    ),
  ),
};
