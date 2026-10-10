import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { PAYMENT_STATUSES, PAYMENT_TYPES } from './payment.model.js';

export const authorizationValidation = [
  body('bookingId')
    .matches(/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/i)
    .withMessage('Invalid booking identifier'),
  body('method').isIn(['card', 'fpx', 'wallet']),
  body('idempotencyKey').custom(textInput).bail().trim()
    .isLength({ min: 8, max: 100 })
    .matches(/^[a-zA-Z0-9:_-]+$/),
];

export const bookingPaymentsValidation = [
  param('bookingId').matches(/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/i),
];

export const listPaymentsValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('bookingId')
    .optional()
    .matches(/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/i),
  query('type').optional().isIn(PAYMENT_TYPES),
  query('status').optional().isIn(PAYMENT_STATUSES),
];

export const refundValidation = [
  param('id').matches(/^(?:[a-f\d]{24}|TXN-[A-Z]+-[A-Z0-9-]+)$/i),
  body('amount').optional().custom(moneyInput).bail().isFloat({ min: 0.01 }).toFloat(),
  body('reason').custom(textInput).bail().trim().isLength({ min: 3, max: 500 }),
  body('idempotencyKey').custom(textInput).bail().trim()
    .isLength({ min: 8, max: 100 })
    .matches(/^[a-zA-Z0-9:_-]+$/),
];
