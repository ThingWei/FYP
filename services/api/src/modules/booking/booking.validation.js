import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { BOOKING_STATUSES } from './booking.model.js';

const bookingId = param('id').custom(textInput).bail().trim()
  .matches(/^(?:[a-f\d]{24}|RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+)$/i)
  .withMessage('Invalid booking identifier');

export const createBookingValidation = [
  body().custom((value) => {
    const allowed = new Set([
      'listingId',
      'idempotencyKey',
      'startDate',
      'endDate',
      'fulfilmentMethod',
      'serviceVenue',
      'damageWaiverSelected',
      'renterNote',
      'agreementAccepted',
      'agreementVersion',
    ]);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('listingId').matches(/^l-[a-z\d-]+$/i),
  body('idempotencyKey').custom(textInput).bail().trim()
    .isLength({ min: 8, max: 100 })
    .matches(/^[a-zA-Z0-9:_-]+$/),
  // Keep the original representation. Physical rentals use calendar-date
  // semantics and are normalized only after the listing type is known.
  body('startDate').isISO8601({ strict: true }),
  body('endDate').isISO8601({ strict: true }),
  body('fulfilmentMethod').optional().isIn(['pickup', 'owner_delivery']),
  body('serviceVenue').optional().custom(textInput).bail().trim().isLength({ min: 2, max: 240 }),
  body('damageWaiverSelected').optional().isBoolean().toBoolean(),
  body('renterNote').optional().custom(textInput).bail().trim().isLength({ max: 1000 }),
  body('agreementAccepted')
    .custom((value) => value === true)
    .withMessage('The rental agreement must be accepted'),
  body('agreementVersion')
    .equals('renthub-booking-v1')
    .withMessage('The rental agreement version is no longer supported'),
  body().custom((value) => {
    if (new Date(value.endDate) < new Date(value.startDate)) {
      throw new Error('endDate must not be before startDate');
    }
    return true;
  }),
];

export const bookingIdValidation = [bookingId];

export const listBookingsValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('status').optional().isIn(BOOKING_STATUSES),
];

export const decisionValidation = [
  bookingId,
  body('status').isIn(['approved', 'rejected']),
  body('reason').optional().custom(textInput).bail().trim().isLength({ max: 500 }),
];

export const cancellationValidation = [
  bookingId,
  body('reason').custom(textInput).bail().trim().isLength({ min: 3, max: 500 }),
];
