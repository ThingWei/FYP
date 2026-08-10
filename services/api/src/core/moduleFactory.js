import mongoose from 'mongoose';
import { Router } from 'express';
import { body } from 'express-validator';
import { asyncHandler } from './asyncHandler.js';
import { created, ok } from './respond.js';
import { AppError } from './errors.js';
import { authenticate } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

export function createModule(name, fields = {}) {
  const schema = new mongoose.Schema({ ...fields, createdBy: String }, { timestamps: true, strict: false });
  const Model = mongoose.models[name] ?? mongoose.model(name, schema);
  const repository = {
    list: ({ page = 1, limit = 20 }) => Promise.all([Model.find().skip((page - 1) * limit).limit(limit).lean(), Model.countDocuments()]),
    get: (id) => Model.findById(id).lean(),
    create: (data) => Model.create(data),
    update: (id, data) => Model.findByIdAndUpdate(id, data, { new: true, runValidators: true }).lean(),
  };
  const service = {
    list: (query) => repository.list({ page: Math.max(Number(query.page) || 1, 1), limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100) }),
    async get(id) { const item = await repository.get(id); if (!item) throw new AppError(`${name} not found`, 404, 'NOT_FOUND'); return item; },
    create: (data, user) => repository.create({ ...data, createdBy: user.id }),
    async update(id, data) { const item = await repository.update(id, data); if (!item) throw new AppError(`${name} not found`, 404, 'NOT_FOUND'); return item; },
  };
  const controller = {
    list: asyncHandler(async (req, res) => { const [items, total] = await service.list(req.query); const page = Number(req.query.page) || 1; const limit = Number(req.query.limit) || 20; ok(res, items, { page, limit, total }); }),
    get: asyncHandler(async (req, res) => ok(res, await service.get(req.params.id))),
    create: asyncHandler(async (req, res) => created(res, await service.create(req.body, req.user))),
    update: asyncHandler(async (req, res) => ok(res, await service.update(req.params.id, req.body))),
  };
  const validation = [body().isObject().withMessage('JSON object required')];
  const router = Router();
  router.get('/', controller.list); router.get('/:id', controller.get);
  router.post('/', authenticate, validation, validate, controller.create);
  router.patch('/:id', authenticate, validation, validate, controller.update);
  return { Model, repository, service, controller, validation, router };
}

