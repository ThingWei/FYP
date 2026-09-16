import { body, param, query } from 'express-validator';
import { REVIEW_STATUSES } from './review.model.js';

const reviewId = param('id')
  .trim()
  .matches(/^RH-REV-[A-Z0-9]+$/)
  .withMessage('Invalid review identifier');

const ratingFields = [
  body('overallRating').isInt({ min: 1, max: 5 }).toInt(),
  body('conditionRating').optional().isInt({ min: 1, max: 5 }).toInt(),
  body('communicationRating').isInt({ min: 1, max: 5 }).toInt(),
  body('valueRating').optional().isInt({ min: 1, max: 5 }).toInt(),
  body('text').trim().isLength({ min: 10, max: 1500 }),
];

export const createReviewValidation = [
  body().custom((value) => {
    const allowed = new Set([
      'rentalId',
      'overallRating',
      'conditionRating',
      'communicationRating',
      'valueRating',
      'text',
    ]);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('rentalId').trim().matches(/^RH-RNT-\d{4}-[A-Z0-9]+$/),
  ...ratingFields,
];

export const editReviewValidation = [reviewId, ...ratingFields];

export const flagReviewValidation = [
  reviewId,
  body('reason').trim().isLength({ min: 5, max: 500 }),
];

export const moderationValidation = [
  reviewId,
  body('status').isIn(REVIEW_STATUSES),
  body('reason').optional().trim().isLength({ max: 500 }),
];

export const reviewListValidation = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
];

export const adminReviewListValidation = [
  ...reviewListValidation,
  query('status').optional().isIn(REVIEW_STATUSES),
  query('flagged').optional().isBoolean(),
];

export const listingReviewsValidation = [
  param('listingId').trim().matches(/^l-[a-z\d-]+$/i),
  ...reviewListValidation,
];

export const subjectSummaryValidation = [
  param('subjectId').trim().isLength({ min: 2, max: 150 }),
];
