import mongoose from 'mongoose';
import { Router } from 'express';
import { body, matchedData, param, query } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { AppError } from '../../core/errors.js';
import { ok } from '../../core/respond.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { ListingModel } from '../listing/listing.model.js';
import { ReviewModel } from '../review/review.model.js';
import { UserModel } from '../user/user.model.js';
import {
  ModerationReportModel,
  REPORT_REASONS,
  REPORT_TARGET_TYPES,
} from './moderationReport.model.js';
import { PlatformSettingModel } from './platformSetting.model.js';

const auditSchema = new mongoose.Schema(
  {
    actorId: { type: String, required: true, index: true },
    action: { type: String, required: true, trim: true, index: true },
    targetType: { type: String, required: true, trim: true },
    targetId: { type: String, required: true, trim: true, index: true },
    metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
    createdBy: { type: String, required: true },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value._id.toString();
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

const Model =
  mongoose.models.AdminAudit ?? mongoose.model('AdminAudit', auditSchema);

const repository = {
  create: (data) => Model.create(data),
  list: async ({ page, limit }) => {
    const [items, total] = await Promise.all([
      Model.find()
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      Model.countDocuments(),
    ]);
    return { items, total };
  },
};

const service = {
  create: repository.create,
  async list(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 50, 1), 100);
    const result = await repository.list({ page, limit });
    return { ...result, page, limit };
  },

  async createReport(input, identity) {
    const reporter = await UserModel.findOne({ authId: identity.authId });
    if (!reporter) {
      throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
    }
    if (reporter.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${reporter.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    let target;
    if (input.targetType === 'user') {
      const identifiers = [{ authId: input.targetId }];
      if (mongoose.isValidObjectId(input.targetId)) {
        identifiers.push({ _id: input.targetId });
      }
      target = await UserModel.findOne({ $or: identifiers });
    } else if (input.targetType === 'listing') {
      const identifiers = [{ publicId: input.targetId }];
      if (mongoose.isValidObjectId(input.targetId)) {
        identifiers.push({ _id: input.targetId });
      }
      target = await ListingModel.findOne({ $or: identifiers });
    } else {
      const identifiers = [{ publicId: input.targetId }];
      if (mongoose.isValidObjectId(input.targetId)) {
        identifiers.push({ _id: input.targetId });
      }
      target = await ReviewModel.findOne({ $or: identifiers });
    }
    if (!target) throw new AppError('Report target not found', 404, 'NOT_FOUND');
    if (input.targetType === 'user' && target.authId === reporter.authId) {
      throw new AppError(
        'You cannot report your own account',
        400,
        'INVALID_REPORT_TARGET',
      );
    }
    const existing = await ModerationReportModel.findOne({
      targetType: input.targetType,
      targetId: input.targetId,
      reporterId: identity.authId,
      status: 'open',
    });
    if (existing) return existing;
    const targetLabel =
      input.targetType === 'user'
        ? target.displayName
        : input.targetType === 'listing'
          ? target.title
          : `${target.listingTitle} review`;
    return ModerationReportModel.create({
      ...input,
      targetLabel,
      reporterId: identity.authId,
    });
  },

  async listReports(queryInput) {
    const page = Math.max(Number(queryInput.page) || 1, 1);
    const limit = Math.min(Math.max(Number(queryInput.limit) || 50, 1), 100);
    const filter = {};
    if (REPORT_TARGET_TYPES.includes(queryInput.targetType)) {
      filter.targetType = queryInput.targetType;
    }
    if (['open', 'resolved', 'dismissed'].includes(queryInput.status)) {
      filter.status = queryInput.status;
    }
    const [items, total] = await Promise.all([
      ModerationReportModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      ModerationReportModel.countDocuments(filter),
    ]);
    return { items, page, limit, total };
  },

  async resolveReport(id, input, identity) {
    const report = await ModerationReportModel.findOne({ publicId: id });
    if (!report) throw new AppError('Report not found', 404, 'NOT_FOUND');
    if (report.status !== 'open') {
      throw new AppError('Report was already reviewed', 409, 'REPORT_REVIEWED');
    }
    report.status = input.status;
    report.resolution = input.resolution;
    report.reviewedBy = identity.authId;
    report.reviewedAt = new Date();
    await report.save();
    await repository.create({
      actorId: identity.authId,
      action: `report.${input.status}`,
      targetType: 'moderation_report',
      targetId: report.publicId,
      metadata: {
        reportTargetType: report.targetType,
        reportTargetId: report.targetId,
        resolution: report.resolution,
      },
      createdBy: identity.authId,
    });
    return report;
  },

  async getSettings() {
    return (
      (await PlatformSettingModel.findOne({ key: 'platform' })) ??
      PlatformSettingModel.create({ key: 'platform' })
    );
  },

  async updateSettings(input, identity) {
    const settings = await PlatformSettingModel.findOneAndUpdate(
      { key: 'platform' },
      { $set: { ...input, updatedBy: identity.authId } },
      { new: true, upsert: true, runValidators: true, setDefaultsOnInsert: true },
    );
    await repository.create({
      actorId: identity.authId,
      action: 'platform.settings_updated',
      targetType: 'platform_settings',
      targetId: 'platform',
      metadata: { changedFields: Object.keys(input) },
      createdBy: identity.authId,
    });
    return settings;
  },
};

const router = Router();
const reportSubmissionValidation = [
  body('targetType').isIn(REPORT_TARGET_TYPES),
  body('targetId').trim().isLength({ min: 2, max: 100 }),
  body('reason').isIn(REPORT_REASONS),
  body('details').optional().trim().isLength({ max: 1000 }),
  body().custom((value) => {
    if (value.reason === 'other' && !value.details?.trim()) {
      throw new Error('Details are required for an other report');
    }
    return true;
  }),
];
const reportsValidation = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('targetType').optional().isIn(REPORT_TARGET_TYPES),
  query('status').optional().isIn(['open', 'resolved', 'dismissed']),
];
const reportDecisionValidation = [
  param('reportId').matches(/^RPT-MOD-[A-Z0-9-]+$/i),
  body('status').isIn(['resolved', 'dismissed']),
  body('resolution').trim().isLength({ min: 5, max: 1000 }),
];
const settingsValidation = [
  body('marketplaceFeePercent').optional().isFloat({ min: 0, max: 20 }).toFloat(),
  body('maintenanceMode').optional().isBoolean().toBoolean(),
  body('highValueKycEnabled').optional().isBoolean().toBoolean(),
  body('highValueThreshold')
    .optional()
    .isFloat({ min: 0, max: 1_000_000 })
    .toFloat(),
  body('reportAutoHideThreshold').optional().isInt({ min: 1, max: 100 }).toInt(),
  body('verificationOcrThreshold').optional().isInt({ min: 0, max: 100 }).toInt(),
  body('supportEmail').optional().isEmail().normalizeEmail(),
  body('bookingPolicy').optional().trim().isLength({ min: 10, max: 3000 }),
  body('contentPolicy').optional().trim().isLength({ min: 10, max: 3000 }),
  body('notificationTemplates').optional().isObject(),
  body('notificationTemplates.bookingApproved')
    .optional()
    .trim()
    .isLength({ min: 5, max: 300 }),
  body('notificationTemplates.verificationUpdate')
    .optional()
    .trim()
    .isLength({ min: 5, max: 300 }),
  body('notificationTemplates.reportResolved')
    .optional()
    .trim()
    .isLength({ min: 5, max: 300 }),
  body('categories').optional().isArray({ min: 6, max: 6 }),
  body('categories.*.name').optional().isIn([
    'Clothing',
    'Vehicles',
    'Services',
    'Devices',
    'Books',
    'Equipment',
  ]),
  body('categories.*.active').optional().isBoolean().toBoolean(),
];

router.post(
  '/reports',
  authenticate,
  reportSubmissionValidation,
  validate,
  asyncHandler(async (req, res) =>
    ok(
      res,
      await service.createReport(
        {
          targetType: req.body.targetType,
          targetId: req.body.targetId,
          reason: req.body.reason,
          details: req.body.details ?? '',
        },
        req.user,
      ),
    ),
  ),
);
router.use(authenticate, authorize('admin'));
router.get(
  '/reports',
  reportsValidation,
  validate,
  asyncHandler(async (req, res) => {
    const result = await service.listReports(req.query);
    return ok(res, result.items, {
      page: result.page,
      limit: result.limit,
      total: result.total,
    });
  }),
);
router.patch(
  '/reports/:reportId',
  reportDecisionValidation,
  validate,
  asyncHandler(async (req, res) =>
    ok(
      res,
      await service.resolveReport(
        req.params.reportId,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
);
router.get(
  '/settings',
  asyncHandler(async (_req, res) => ok(res, await service.getSettings())),
);
router.put(
  '/settings',
  settingsValidation,
  validate,
  asyncHandler(async (req, res) =>
    ok(
      res,
      await service.updateSettings(
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
);
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const result = await service.list(req.query);
    return ok(res, result.items, {
      page: result.page,
      limit: result.limit,
      total: result.total,
    });
  }),
);

export const adminModule = {
  Model,
  ModerationReportModel,
  PlatformSettingModel,
  repository,
  service,
  router,
};

