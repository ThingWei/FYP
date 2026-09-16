import mongoose from 'mongoose';
import { Router } from 'express';
import { asyncHandler } from '../../core/asyncHandler.js';
import { ok } from '../../core/respond.js';
import { authenticate, authorize } from '../../middleware/auth.js';

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
};

const router = Router();
router.use(authenticate, authorize('admin'));
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

export const adminModule = { Model, repository, service, router };

