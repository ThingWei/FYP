import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { reviewService } from './review.service.js';

export const reviewController = {
  create: asyncHandler(async (req, res) =>
    created(
      res,
      await reviewService.create(
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  edit: asyncHandler(async (req, res) =>
    ok(
      res,
      await reviewService.edit(
        req.params.id,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  listListing: asyncHandler(async (req, res) => {
    const result = await reviewService.listListing(req.params.listingId, req.query);
    return ok(res, result.items, result.meta);
  }),
  listMine: asyncHandler(async (req, res) => {
    const result = await reviewService.listMine(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listReceived: asyncHandler(async (req, res) => {
    const result = await reviewService.listReceived(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  flag: asyncHandler(async (req, res) =>
    ok(
      res,
      await reviewService.flag(
        req.params.id,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await reviewService.listAdmin(req.query);
    return ok(res, result.items, result.meta);
  }),
  moderate: asyncHandler(async (req, res) =>
    ok(
      res,
      await reviewService.moderate(
        req.params.id,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  summary: asyncHandler(async (req, res) =>
    ok(res, await reviewService.summary(req.params.subjectId)),
  ),
};
