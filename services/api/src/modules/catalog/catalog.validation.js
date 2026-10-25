import { textInput, wholeInput } from '../../core/inputValidation.js';
import { query } from 'express-validator';
import { LISTING_CATEGORIES } from '../listing/listing.model.js';
import { CATALOG_COVERAGE } from './catalog.coverage.js';
import { MAX_CATALOG_RESULTS } from './catalog.limits.js';

const context = [
  query('category').isIn(LISTING_CATEGORIES.filter((item) => item !== 'Services')),
  query('subcategory').custom(textInput).bail().trim().isLength({ min: 2, max: 100 }).bail()
    .custom((value, { req }) => CATALOG_COVERAGE.some((entry) =>
      entry.category === req.query.category && entry.subcategory === value))
    .withMessage('Choose a specific category that belongs to the selected category.'),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: MAX_CATALOG_RESULTS }),
  query('refresh').optional().custom((value) => value === 'true' || value === 'false'),
  query('preferCache').optional().custom((value) => value === 'true' || value === 'false'),
];

const common = [
  ...context,
  query('query').custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
];

export const brandCatalogValidation = [
  ...context,
  query('query').optional({ checkFalsy: true }).custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
];
export const modelCatalogValidation = [
  ...context,
  query('query').optional({ checkFalsy: true }).custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
  query('brand').custom(textInput).bail().trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().custom(textInput).bail().trim().isLength({ min: 3, max: 160 }),
];
export const searchCatalogValidation = [
  ...common,
  query('brand').optional().custom(textInput).bail().trim().isLength({ min: 1, max: 100 }),
  query('catalogBrandId').optional().custom(textInput).bail().trim().isLength({ min: 3, max: 160 }),
];
