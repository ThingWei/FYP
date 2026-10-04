import { asyncHandler } from '../../core/asyncHandler.js';
import { ok } from '../../core/respond.js';
import { catalogService } from './catalog.service.js';

function respond(res, result) {
  return ok(res, result.items, {
    provider: result.provider,
    providerAvailable: result.providerAvailable,
    stale: result.stale,
    ...(result.warning && { warning: result.warning }),
  });
}

export const catalogController = {
  brands: asyncHandler(async (req, res) => respond(res, await catalogService.brands(req.query))),
  models: asyncHandler(async (req, res) => respond(res, await catalogService.models(req.query))),
  search: asyncHandler(async (req, res) => respond(res, await catalogService.search(req.query))),
};
