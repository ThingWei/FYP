import { body, param, query } from 'express-validator';
import {
  LISTING_CATEGORIES,
  LISTING_STATUSES,
  LISTING_TYPES,
} from './listing.model.js';

const editableFields = new Set([
  'title',
  'description',
  'category',
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

const listingId = param('id')
  .trim()
  .matches(/^(?:[a-f\d]{24}|l-[a-z\d-]+)$/i)
  .withMessage('Invalid listing identifier');

const listingFields = [
  body('title').optional().trim().isLength({ min: 3, max: 120 }),
  body('description').optional().trim().isLength({ max: 3000 }),
  body('category').optional().isIn(LISTING_CATEGORIES),
  body('listingType').optional().isIn(LISTING_TYPES),
  body('dailyPrice').optional().isFloat({ min: 1, max: 1_000_000 }).toFloat(),
  body('priceUnit').optional().isIn(['day', 'hour', 'session', 'package']),
  body('condition')
    .optional()
    .isIn(['Fair', 'Good', 'Very good', 'Excellent', 'Like New']),
  body('securityDeposit')
    .optional()
    .isFloat({ min: 0, max: 1_000_000 })
    .toFloat(),
  body('damageWaiverAvailable').optional().isBoolean().toBoolean(),
  body('damageWaiverFee')
    .optional()
    .isFloat({ min: 0, max: 100_000 })
    .toFloat(),
  body('fulfilmentMethods').optional().isArray({ min: 1, max: 2 }),
  body('fulfilmentMethods.*').optional().isIn(['pickup', 'owner_delivery']),
  body('serviceDetails').optional().isObject(),
  body('serviceDetails.packageName')
    .optional()
    .trim()
    .isLength({ min: 2, max: 100 }),
  body('serviceDetails.durationMinutes')
    .optional()
    .isInt({ min: 15, max: 10_080 })
    .toInt(),
  body('serviceDetails.venueMode')
    .optional()
    .isIn(['owner_location', 'renter_location', 'online', 'flexible']),
  body('serviceDetails.inclusions').optional().isArray({ max: 30 }),
  body('serviceDetails.inclusions.*')
    .optional()
    .trim()
    .isLength({ min: 1, max: 160 }),
  body('location').optional().trim().isLength({ min: 2, max: 160 }),
  body('state').optional().trim().isLength({ max: 80 }),
  body('images').optional().isArray({ max: 10 }),
  body('images.*').optional().trim().isLength({ min: 1, max: 500 }),
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
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('search').optional().trim().isLength({ max: 100 }),
  query('category').optional().isIn(LISTING_CATEGORIES),
  query('type').optional().isIn(LISTING_TYPES),
  query('location').optional().trim().isLength({ max: 100 }),
  query('verified').optional().isBoolean(),
  query('minPrice').optional().isFloat({ min: 0 }),
  query('maxPrice').optional().isFloat({ min: 0 }),
  query('availableFrom').optional().isISO8601(),
  query('availableTo').optional().isISO8601(),
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
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('status').optional().isIn(LISTING_STATUSES),
];

export const availabilityValidation = [
  listingId,
  body('unavailableRanges').optional().isArray({ max: 100 }),
  body('unavailableRanges.*.start').optional().isISO8601().toDate(),
  body('unavailableRanges.*.end').optional().isISO8601().toDate(),
  body('unavailableRanges.*.reason').optional().trim().isLength({ max: 120 }),
  body('weeklyHours').optional().isArray({ max: 14 }),
  body('weeklyHours.*.weekday').optional().isInt({ min: 0, max: 6 }).toInt(),
  body('weeklyHours.*.startTime')
    .optional()
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('weeklyHours.*.endTime')
    .optional()
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/),
  body('minimumNoticeHours').optional().isInt({ min: 0, max: 8760 }).toInt(),
  body('bufferHours').optional().isInt({ min: 0, max: 168 }).toInt(),
];

export const moderationValidation = [
  listingId,
  body('status').isIn(['active', 'rejected']),
  body('reason').optional().trim().isLength({ max: 500 }),
];
