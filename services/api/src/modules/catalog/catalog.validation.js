import { query } from 'express-validator';
import { LISTING_CATEGORIES } from '../listing/listing.model.js';

const context = [
  query('category').isIn(LISTING_CATEGORIES.filter((item) => item !== 'Services')),
  query('subcategory').trim().isLength({ min: 2, max: 100 }),
];

const common = [
  ...context,
  query('query').trim().isLength({ min: 2, max: 80 }),
];

export const brandCatalogValidation = common;
export const modelCatalogValidation = [
  ...context,
  query('query').optional({ checkFalsy: true }).trim().isLength({ min: 2, max: 80 }),
  query('brand').trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().trim().isLength({ min: 3, max: 160 }),
];
export const searchCatalogValidation = [
  ...common,
  query('brand').optional().trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().trim().isLength({ min: 3, max: 160 }),
];
