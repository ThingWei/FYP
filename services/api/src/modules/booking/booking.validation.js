import { physicalRentalDate } from '../../core/calendarDate.js';
import { validateLocation } from '../../core/location.js';
import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { BOOKING_STATUSES } from './booking.model.js';
import { agreementVersions } from './agreementTerms.js';

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
      'pickupTime', 'returnTime',
      'fulfilmentMethod',
      'serviceVenue',
      'serviceLocation',
      'deliveryLocation',
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
  ...['pickupTime', 'returnTime'].map(field => body(field).optional().custom(textInput).bail().matches(/^([01]\d|2[0-3]):[0-5]\d$/)),
  body('fulfilmentMethod').optional().isIn(['pickup', 'owner_delivery']),
  body('serviceLocation').optional().custom(validateLocation),
  body('deliveryLocation').optional().custom(validateLocation),
  body('serviceVenue').optional().custom(textInput).bail().trim().isLength({ min: 2, max: 240 }),
  body('damageWaiverSelected').optional().isBoolean().toBoolean(),
  body('renterNote').optional().custom(textInput).bail().trim().isLength({ max: 1000 }),
  body('agreementAccepted')
    .custom((value) => value === true)
    .withMessage('The rental agreement must be accepted'),
  body('agreementVersion')
    .isIn(agreementVersions)
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
  query('q').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('listingType').optional().isIn(['physical', 'service']),
  query('paymentStatus').optional().isIn(['unpaid', 'authorized', 'captured', 'partially_refunded', 'refunded', 'voided', 'settled']),
  query('category').optional().isIn(['Devices', 'Vehicles', 'Equipment', 'Books', 'Clothing', 'Services']),
  query('sort').optional().isIn(['newest', 'oldest', 'start_soonest', 'start_latest']),
  ...['fromDate', 'toDate'].map((key) => query(key).optional().custom((value) => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Use a valid calendar date');
    physicalRentalDate(value);
    return true;
  })),
  query().custom((value) => {
    if (value.fromDate && value.toDate && value.fromDate > value.toDate) throw new Error('The end date must not be before the start date');
    return true;
  }),
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
