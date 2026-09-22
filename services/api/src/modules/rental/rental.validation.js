import { body, param, query } from 'express-validator';
import { RENTAL_STATUSES } from './rental.model.js';
import { isUploadReference } from '../../core/uploadReference.js';

const rentalId = param('id')
  .trim()
  .matches(
    /^(?:[a-f\d]{24}|RH-(?:RNT|BKG|SVC)-\d{4}-[A-Z0-9]+)$/i,
  )
  .withMessage('Invalid rental identifier');

const evidenceFields = [
  body('condition').trim().isLength({ min: 2, max: 120 }),
  body('notes').optional().trim().isLength({ max: 1000 }),
  body('evidence').isArray({ min: 1, max: 10 }),
  body('evidence.*')
    .trim()
    .custom((value) => isUploadReference(value))
    .withMessage('Each item must reference an uploaded evidence file'),
];

export const rentalIdValidation = [rentalId];

export const listRentalsValidation = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('status').optional().isIn(RENTAL_STATUSES),
];

export const handoverValidation = [rentalId, ...evidenceFields];
export const returnSubmissionValidation = [rentalId, ...evidenceFields];

export const extensionRequestValidation = [
  rentalId,
  body('requestedEndDate').isISO8601().toDate(),
  body('reason').trim().isLength({ min: 3, max: 500 }),
];

export const extensionDecisionValidation = [
  rentalId,
  body('status').isIn(['approved', 'rejected']),
  body('reason').optional().trim().isLength({ max: 500 }),
];

export const returnConfirmationValidation = [
  rentalId,
  body('condition').trim().isLength({ min: 2, max: 120 }),
  body('notes').optional().trim().isLength({ max: 1000 }),
  body('depositDeduction').isFloat({ min: 0 }).toFloat(),
];
