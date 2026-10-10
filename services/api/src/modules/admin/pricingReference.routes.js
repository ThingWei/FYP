import { Router } from 'express';
import { asyncHandler } from '../../core/asyncHandler.js';
import { AppError } from '../../core/errors.js';
import { ok } from '../../core/respond.js';
import { PricingReferenceModel } from '../listing/pricingReference.model.js';
import { REFERENCE_TEMPLATE, previewPricingReferences, importPricingReferences } from '../listing/pricingReference.service.js';

export function pricingReferenceRouter(writeAudit) {
  const router = Router();
  router.get('/template', (_req, res) => ok(res, {
    fileName: 'renthub-rental-price-references.csv', content: REFERENCE_TEMPLATE,
  }));
  router.post('/preview', asyncHandler(async (req, res) =>
    ok(res, await previewPricingReferences(req.body?.csv))));
  router.post('/import', asyncHandler(async (req, res) => {
    if (req.body?.confirmed !== true) throw new AppError('Confirm that the prices are explicit Malaysian rental quotes, not sales prices or service bundles', 400, 'PRICE_REFERENCE_REVIEW_REQUIRED');
    const result = await importPricingReferences(req.body?.csv, req.user);
    await writeAudit({ actorId: req.user.authId, createdBy: req.user.authId,
      action: 'pricing_references.imported', targetType: 'pricing_reference_import',
      targetId: 'csv', metadata: result });
    return ok(res, result);
  }));
  router.get('/', asyncHandler(async (req, res) => {
    const pageText = req.query.page ?? '1';
    if (typeof pageText !== 'string' || !/^\d+$/.test(pageText) || Number(pageText) < 1 || Number(pageText) > 10000) {
      throw new AppError('Enter a valid page number', 400, 'VALIDATION_ERROR');
    }
    const page = Number(pageText), limit = 50;
    const [items, total] = await Promise.all([
      PricingReferenceModel.find().sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).select('-_id -__v -observationKey').lean(),
      PricingReferenceModel.countDocuments(),
    ]);
    return ok(res, { items, total, page, limit });
  }));
  router.patch('/:referenceId/deactivate', asyncHandler(async (req, res) => {
    if (!/^pr-[a-f0-9]{32}$/.test(req.params.referenceId) || req.body?.confirmed !== true) {
      throw new AppError('Confirm which reference to deactivate', 400, 'VALIDATION_ERROR');
    }
    const item = await PricingReferenceModel.findOneAndUpdate({ publicId: req.params.referenceId }, {
      $set: { active: false, deactivatedBy: req.user.authId, deactivatedAt: new Date() },
    }, { new: true }).select('-_id -__v -observationKey').lean();
    if (!item) throw new AppError('Price reference not found', 404, 'NOT_FOUND');
    await writeAudit({ actorId: req.user.authId, createdBy: req.user.authId,
      action: 'pricing_reference.deactivated', targetType: 'pricing_reference',
      targetId: item.publicId, metadata: {} });
    return ok(res, item);
  }));
  return router;
}
