import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { loyaltyService } from './loyalty.service.js';

function body(req) {
  const data = matchedData(req, { locations: ['body'] });
  delete data[''];
  return data;
}

export const loyaltyController = {
  summary: asyncHandler(async (req, res) =>
    ok(res, await loyaltyService.summary(req.user)),
  ),
  redeem: asyncHandler(async (req, res) =>
    created(res, await loyaltyService.redeem(body(req), req.user)),
  ),
  applyReferral: asyncHandler(async (req, res) =>
    created(res, await loyaltyService.applyReferral(body(req), req.user)),
  ),
  getConfig: asyncHandler(async (_req, res) =>
    ok(res, await loyaltyService.getConfig()),
  ),
  updateConfig: asyncHandler(async (req, res) =>
    ok(res, await loyaltyService.updateConfig(body(req), req.user)),
  ),
  listAdminEntries: asyncHandler(async (req, res) => {
    const result = await loyaltyService.listAdminEntries(req.query);
    return ok(res, result.items, result.meta);
  }),
  listReferrals: asyncHandler(async (req, res) => {
    const result = await loyaltyService.listReferrals(req.query);
    return ok(res, result.items, result.meta);
  }),
};
