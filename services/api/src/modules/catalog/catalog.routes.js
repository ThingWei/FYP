import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { catalogController } from './catalog.controller.js';
import {
  brandCatalogValidation,
  modelCatalogValidation,
  searchCatalogValidation,
} from './catalog.validation.js';

export const catalogRouter = Router();
catalogRouter.use(authenticate, authorize('owner'));
catalogRouter.get('/brands', brandCatalogValidation, validate, catalogController.brands);
catalogRouter.get('/models', modelCatalogValidation, validate, catalogController.models);
catalogRouter.get('/search', searchCatalogValidation, validate, catalogController.search);
