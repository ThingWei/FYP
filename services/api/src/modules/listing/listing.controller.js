import { ownedListing } from '../../core/location.js';
import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { listingService } from './listing.service.js';

const bodyData = (req) => matchedData(req, { locations: ['body'] });

export const listingController = {
  recommended: asyncHandler(async (req, res) =>
    ok(res, await listingService.recommended(req.user, req.query)),
  ),
  recommendPrice: asyncHandler(async (req, res) =>
    ok(res, await listingService.recommendPrice(bodyData(req), req.user)),
  ),
  list: asyncHandler(async (req, res) => {
    const result = await listingService.list(req.query);
    return ok(res, result.items, result.meta);
  }),
  get: asyncHandler(async (req, res) =>
    ok(res, await listingService.get(req.params.id)),
  ),
  create: asyncHandler(async (req, res) =>
    created(res, ownedListing(await listingService.create(bodyData(req), req.user))),
  ),
  listMine: asyncHandler(async (req, res) => {
    const result = await listingService.listMine(req.user, req.query);
    return ok(res, result.items.map(ownedListing), result.meta);
  }),
  listAdmin: asyncHandler(async (req, res) => {
    const result = await listingService.listAdmin(req.query);
    return ok(res, result.items.map(ownedListing), result.meta);
  }),
  update: asyncHandler(async (req, res) =>
    ok(res, ownedListing(await listingService.update(req.params.id, bodyData(req), req.user))),
  ),
  submit: asyncHandler(async (req, res) =>
    ok(res, ownedListing(await listingService.submit(req.params.id, req.user))),
  ),
  deactivate: asyncHandler(async (req, res) =>
    ok(res, ownedListing(await listingService.deactivate(req.params.id, req.user))),
  ),
  getAvailability: asyncHandler(async (req, res) =>
    ok(res, await listingService.getAvailability(req.params.id)),
  ),
  setAvailability: asyncHandler(async (req, res) =>
    ok(
      res,
      ownedListing(await listingService.setAvailability(
        req.params.id,
        bodyData(req),
        req.user,
      )),
    ),
  ),
  setPromotion: asyncHandler(async (req, res) =>
    ok(
      res,
      ownedListing(await listingService.setPromotion(
        req.params.id,
        bodyData(req),
        req.user,
      )),
    ),
  ),
  clearPromotion: asyncHandler(async (req, res) =>
    ok(res, ownedListing(await listingService.clearPromotion(req.params.id, req.user))),
  ),
  setBundle: asyncHandler(async (req, res) =>
    ok(
      res,
      ownedListing(await listingService.setBundle(req.params.id, bodyData(req), req.user)),
    ),
  ),
  clearBundle: asyncHandler(async (req, res) =>
    ok(res, ownedListing(await listingService.clearBundle(req.params.id, req.user))),
  ),
  moderate: asyncHandler(async (req, res) =>
    ok(
      res,
      ownedListing(await listingService.moderate(
        req.params.id,
        req.body.status,
        req.body.reason,
      )),
    ),
  ),
};
