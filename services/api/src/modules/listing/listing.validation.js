import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { LICENCE_CLASSES } from '../user/drivingEligibility.js';
import {
  LISTING_CATEGORIES,
  LISTING_STATUSES,
  LISTING_TYPES,
} from './listing.model.js';
import { isUploadReference } from '../../core/uploadReference.js';

const editableFields = new Set([
  'title',
  'description',
  'category',
  'subcategory',
  'requiredLicenceClass',
  'brand',
  'productModel',
  'canonicalProductId',
  'catalogBrandId',
  'productMatchType',
  'catalogSource',
  'itemAgeYears',
  'listingType',
  'dailyPrice',
  'priceUnit',
  'condition',
  'securityDeposit',
  'damageWaiverAvailable',
  'damageWaiverFee',
  'fulfilmentMethods',
  'serviceDetails',
  'location',
  'state',
  'images',
]);

function onlyEditableFields(value) {
  const unknown = Object.keys(value).filter((field) => !editableFields.has(field));
  if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
  return true;
}

const listingId = param('id').custom(textInput).bail().trim()
  .matches(/^(?:[a-f\d]{24}|l-[a-z\d-]+)$/i)
  .withMessage('Invalid listing identifier');

const listingFields = [
  body('title').optional().custom(textInput).bail().trim().isLength({ min: 3, max: 120 }),
  body('description').optional().custom(textInput).bail().trim().isLength({ max: 3000 }),
  body('category').optional().isIn(LISTING_CATEGORIES),
  body('subcategory').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  body('requiredLicenceClass').optional().isIn(['', ...LICENCE_CLASSES]),
  body('brand').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  body('productModel').optional().custom(textInput).bail().trim().isLength({ max: 120 }),
  body('canonicalProductId')
    .optional({ nullable: true }).custom(textInput).bail().trim()
    .isLength({ min: 3, max: 160 }),
  body('catalogBrandId')
    .optional({ nullable: true }).custom(textInput).bail().trim()
    .isLength({ min: 3, max: 160 }),
  body('productMatchType')
    .optional()
    .isIn([
      'exact_catalog_match',
      'fuzzy_catalog_match',
      'manual_entry',
      'catalog_brand_match_model_manual',
    ]),
  body('catalogSource').optional({ nullable: true }).custom(textInput).bail().trim().isLength({ max: 80 }),
  body('itemAgeYears').optional().custom(numericInput).bail().isFloat({ min: 0, max: 100 }).toFloat(),
  body('listingType').optional().isIn(LISTING_TYPES),
  body('dailyPrice').optional().custom(moneyInput).bail().isFloat({ min: 1, max: 1_000_000 }).toFloat(),
  body('priceUnit').optional().isIn(['day', 'hour', 'session', 'package']),
  body('condition')
    .optional()
    .isIn(['Fair', 'Good', 'Very good', 'Excellent', 'Like New']),
  body('securityDeposit')
    .optional()
    .custom(moneyInput).bail().isFloat({ min: 0, max: 1_000_000 })
    .toFloat(),
  body('damageWaiverAvailable').optional().isBoolean().toBoolean(),
  body('damageWaiverFee')
    .optional()
    .custom(moneyInput).bail().isFloat({ min: 0, max: 100_000 })
    .toFloat(),
  body('fulfilmentMethods').optional().isArray({ min: 1, max: 2 }),
  body('fulfilmentMethods.*').optional().isIn(['pickup', 'owner_delivery']),
  body('serviceDetails').optional().isObject(),
  body('serviceDetails.packageName')
    .optional().custom(textInput).bail().trim()
    .isLength({ min: 2, max: 100 }),
  body('serviceDetails.durationMinutes')
    .optional()
    .custom(wholeInput).bail().isInt({ min: 15, max: 10_080 })
    .toInt(),
  body('serviceDetails.venueMode')
    .optional()
    .isIn(['owner_location', 'renter_location', 'online', 'flexible']),
  body('serviceDetails.inclusions').optional().isArray({ max: 30 }),
  body('serviceDetails.inclusions.*')
    .optional().custom(textInput).bail().trim()
    .isLength({ min: 1, max: 160 }),
  body('location').optional().custom(textInput).bail().trim().isLength({ min: 2, max: 160 }),
  body('state').optional().custom(textInput).bail().trim().isLength({ max: 80 }),
  body('images').optional().isArray({ max: 10 }),
  body('images.*')
    .optional().custom(textInput).bail().trim()
    .custom((value) => isUploadReference(value, { publicOnly: true }))
    .withMessage('Each image must reference a public upload'),
];

export const createListingValidation = [
  body().custom(onlyEditableFields),
  body('title').exists(),
  body('category').exists(),
  body('dailyPrice').exists(),
  body('location').exists(),
  body().custom((value) => {
    const type = value.listingType ?? (value.category === 'Services' ? 'service' : 'physical');
    if (type === 'physical') {
      if (!value.condition) throw new Error('Condition is required for physical items');
      if (!value.fulfilmentMethods?.length) {
        throw new Error('A fulfilment method is required for physical items');
      }
    } else if (!value.serviceDetails?.packageName || !value.serviceDetails?.durationMinutes) {
      throw new Error('Package name and duration are required for services');
    }
    return true;
  }),
  ...listingFields,
];

export const updateListingValidation = [
  listingId,
  body().custom(onlyEditableFields),
  body().custom((value) => {
    if (!Object.keys(value).length) throw new Error('At least one listing field is required');
    return true;
  }),
  ...listingFields,
];

export const listingIdValidation = [listingId];

export const listListingsValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('search').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('category').optional().isIn(LISTING_CATEGORIES),
  query('type').optional().isIn(LISTING_TYPES),
  query('location').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('verified').optional().isBoolean(),
  query('promoted').optional().isBoolean(),
  query('sort')
    .optional()
    .isIn(['recommended', 'price_asc', 'price_desc', 'rating', 'newest', 'trust']),
  query('minPrice').optional().custom(moneyInput).bail().isFloat({ min: 0 }),
  query('maxPrice').optional().custom(moneyInput).bail().isFloat({ min: 0 }),
  query('availableFrom').optional().isISO8601({ strict: true }),
  query('availableTo').optional().isISO8601({ strict: true }),
  query().custom((value) => {
    if (value.minPrice && value.maxPrice && Number(value.minPrice) > Number(value.maxPrice)) {
      throw new Error('minPrice cannot exceed maxPrice');
    }
    if ((value.availableFrom && !value.availableTo) || (!value.availableFrom && value.availableTo)) {
      throw new Error('availableFrom and availableTo must be used together');
    }
    if (value.availableFrom && new Date(value.availableFrom) >= new Date(value.availableTo)) {
      throw new Error('availableTo must be after availableFrom');
    }
    return true;
  }),
];

export const listMineValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('status').optional().isIn(LISTING_STATUSES),
];

export const recommendationValidation = [
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 30 }).toInt(),
  query('search').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('category').optional().isIn(LISTING_CATEGORIES),
  query('type').optional().isIn(LISTING_TYPES),
  query('location').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('verified').optional().isBoolean(),
  query('promoted').optional().isBoolean(),
  query('minPrice').optional().custom(moneyInput).bail().isFloat({ min: 0 }),
  query('maxPrice').optional().custom(moneyInput).bail().isFloat({ min: 0 }),
  query('availableFrom').optional().isISO8601({ strict: true }),
  query('availableTo').optional().isISO8601({ strict: true }),
  query().custom((value) => {
    if (value.minPrice && value.maxPrice && Number(value.minPrice) > Number(value.maxPrice)) {
      throw new Error('minPrice cannot exceed maxPrice');
    }
    if ((value.availableFrom && !value.availableTo) || (!value.availableFrom && value.availableTo)) {
      throw new Error('availableFrom and availableTo must be used together');
    }
    if (value.availableFrom && new Date(value.availableFrom) >= new Date(value.availableTo)) {
      throw new Error('availableTo must be after availableFrom');
    }
    return true;
  }),
];

export const priceRecommendationValidation = [
  body('itemProfile').isObject(),
  body('excludeListingId').optional().custom(textInput).bail().trim().matches(/^l-[a-z\d-]+$/i),
  body('itemProfile.category').isIn(
    LISTING_CATEGORIES.filter((category) => category !== 'Services'),
  ),
  body('itemProfile.subcategory').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  body('itemProfile.condition')
    .isIn(['Fair', 'Good', 'Very good', 'Excellent', 'Like New']),
  body('itemProfile.brand').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  body('itemProfile.product_model').optional().custom(textInput).bail().trim().isLength({ max: 120 }),
  body('itemProfile.canonicalProductId')
    .optional({ nullable: true }).custom(textInput).bail().trim()
    .isLength({ min: 3, max: 160 }),
  body('itemProfile.catalogBrandId')
    .optional({ nullable: true }).custom(textInput).bail().trim()
    .isLength({ min: 3, max: 160 }),
  body('itemProfile.productMatchType')
    .optional()
    .isIn([
      'exact_catalog_match',
      'fuzzy_catalog_match',
      'manual_entry',
      'catalog_brand_match_model_manual',
    ]),
  body('itemProfile.catalogSource')
    .optional({ nullable: true }).custom(textInput).bail().trim()
    .isLength({ max: 80 }),
  body('itemProfile.location').optional().custom(textInput).bail().trim().isLength({ max: 160 }),
  body('itemProfile.state').optional().custom(textInput).bail().trim().isLength({ max: 80 }),
  body('itemProfile.item_age_years')
    .optional()
    .custom(numericInput).bail().isFloat({ min: 0, max: 100 })
    .toFloat(),
  body('rentalDurationDays')
    .optional()
    .custom(wholeInput).bail().isInt({ min: 1, max: 365 })
    .toInt(),
];

export const availabilityValidation = [
  listingId,
  body('unavailableRanges').optional().custom((ranges) => {
    if (!Array.isArray(ranges) || ranges.some((range) => !range?.start || !range?.end ||
        !Number.isFinite(Date.parse(range.start)) || !Number.isFinite(Date.parse(range.end)) ||
        new Date(range.start) >= new Date(range.end))) {
      throw new Error('Every unavailable range needs a valid start before its end');
    }
    return true;
  }),
  body('weeklyHours').optional().custom((hours) => {
    if (!Array.isArray(hours) || hours.some((row) => row?.weekday === undefined ||
        !/^([01]\d|2[0-3]):[0-5]\d$/.test(row?.startTime) ||
        !/^([01]\d|2[0-3]):[0-5]\d$/.test(row?.endTime) || row.startTime >= row.endTime)) {
      throw new Error('Every weekly interval needs a weekday and start time before end time');
    }
    return true;
  }),
  body('unavailableRanges').optional().isArray({ max: 100 }),
  body('unavailableRanges.*.start').optional().isISO8601({ strict: true }),
  body('unavailableRanges.*.end').optional().isISO8601({ strict: true }),
  body('unavailableRanges.*.reason').optional().custom(textInput).bail().trim().isLength({ max: 120 }),
  body('weeklyHours').optional().isArray({ max: 14 }),
  body('weeklyHours.*.weekday').optional().custom(wholeInput).bail().isInt({ min: 0, max: 6 }).toInt(),
  body('weeklyHours.*.startTime')
    .optional()
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('weeklyHours.*.endTime')
    .optional()
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('minimumNoticeHours').optional().custom(wholeInput).bail().isInt({ min: 0, max: 8760 }).toInt(),
  body('bufferHours').optional().custom(wholeInput).bail().isInt({ min: 0, max: 168 }).toInt(),
];

export const promotionValidation = [
  listingId,
  body().custom((value) => {
    const allowed = new Set([
      'enabled',
      'label',
      'discountPercent',
      'startsAt',
      'endsAt',
    ]);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('enabled').optional().isBoolean().toBoolean(),
  body('label').custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
  body('discountPercent').custom(numericInput).bail().isFloat({ min: 5, max: 80 }).toFloat(),
  body('startsAt').isISO8601({ strict: true }).toDate(),
  body('endsAt').isISO8601({ strict: true }).toDate(),
  body().custom((value) => {
    if (new Date(value.startsAt) >= new Date(value.endsAt)) {
      throw new Error('endsAt must be after startsAt');
    }
    return true;
  }),
];

export const bundleValidation = [
  listingId,
  body().custom((value) => {
    const allowed = new Set([
      'active',
      'title',
      'listingIds',
      'discountPercent',
    ]);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('active').optional().isBoolean().toBoolean(),
  body('title').custom(textInput).bail().trim().isLength({ min: 3, max: 100 }),
  body('listingIds').isArray({ min: 2, max: 5 }),
  body('listingIds.*').matches(/^l-[a-z\d-]+$/i),
  body('discountPercent').custom(numericInput).bail().isFloat({ min: 5, max: 50 }).toFloat(),
];

export const moderationValidation = [
  listingId,
  body('status').isIn(['active', 'rejected']),
  body('reason').optional().custom(textInput).bail().trim().isLength({ max: 500 }),
];
