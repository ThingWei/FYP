import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { RENTAL_STATUSES } from './rental.model.js';
import { isUploadReference } from '../../core/uploadReference.js';

const rentalId = param('id').custom(textInput).bail().trim()
  .matches(
    /^(?:[a-f\d]{24}|RH-(?:RNT|BKG|SVC)-\d{4}-[A-Z0-9]+)$/i,
  )
  .withMessage('Invalid rental identifier');

const evidenceFields = [
  body('condition').custom(textInput).bail().trim().isLength({ min: 2, max: 120 }),
  body('notes').optional().custom(textInput).bail().trim().isLength({ max: 1000 }),
  body('evidence').isArray({ min: 1, max: 10 }),
  body('evidence.*').custom(textInput).bail().trim()
    .custom((value) => isUploadReference(value))
    .withMessage('Each item must reference an uploaded evidence file'),
];

export const rentalIdValidation = [rentalId];

export const listRentalsValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('status').optional().isIn(RENTAL_STATUSES),
];

export const handoverValidation = [rentalId, ...evidenceFields];
export const returnSubmissionValidation = [rentalId, ...evidenceFields];

export const extensionRequestValidation = [
  rentalId,
  body('requestedEndDate').isISO8601({ strict: true }),
  body('reason').custom(textInput).bail().trim().isLength({ min: 3, max: 500 }),
];

export const extensionDecisionValidation = [
  rentalId,
  body('status').isIn(['approved', 'rejected']),
  body('reason').optional().custom(textInput).bail().trim().isLength({ max: 500 }),
];

export const returnConfirmationValidation = [
  rentalId,
  body('condition').custom(textInput).bail().trim().isLength({ min: 2, max: 120 }),
  body('notes').optional().custom(textInput).bail().trim().isLength({ max: 1000 }),
  body('depositDeduction').custom(moneyInput).bail().isFloat({ min: 0 }).toFloat(),
];
