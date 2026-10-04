import { query } from 'express-validator';
import { LISTING_CATEGORIES } from '../listing/listing.model.js';

const common = [
  query('category').isIn(LISTING_CATEGORIES.filter((item) => item !== 'Services')),
  query('subcategory').trim().isLength({ min: 2, max: 100 }),
  query('query').trim().isLength({ min: 2, max: 80 }),
];

export const brandCatalogValidation = common;
export const modelCatalogValidation = [
  ...common,
  query('brand').trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().trim().isLength({ min: 3, max: 160 }),
];
export const searchCatalogValidation = [
  ...common,
  query('brand').optional().trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().trim().isLength({ min: 3, max: 160 }),
];
