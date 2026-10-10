import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { MESSAGE_REPORT_REASONS } from './messageReport.model.js';
import { NOTIFICATION_CATEGORIES } from './notification.model.js';
import { PUSH_PLATFORMS } from './deviceRegistration.model.js';

const threadId = param('threadId')
  .matches(/^THR-[A-Z0-9-]+$/i)
  .withMessage('Invalid conversation identifier');

export const paginationValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
];

export const bookingThreadValidation = [
  param('bookingId').matches(/^RH-(?:BKG|SVC)-\d{4}-[A-Z0-9]+$/i),
];

export const threadMessagesValidation = [threadId, ...paginationValidation];

export const sendMessageValidation = [
  threadId,
  body().custom((value) => {
    const allowed = new Set(['text', 'attachmentRef']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('text').optional().custom(textInput).bail().trim().isLength({ max: 2000 }),
  body('attachmentRef')
    .optional().custom(textInput).bail().trim()
    .matches(/^upload:\/\/UPL-[A-Z0-9]+$/i)
    .withMessage('Invalid message image reference'),
  body().custom((value) => {
    if (!value.text?.trim() && !value.attachmentRef) {
      throw new Error('A message requires text or an image');
    }
    return true;
  }),
];

export const markReadValidation = [threadId];

export const reportMessageValidation = [
  param('messageId').matches(/^MSG-[A-Z0-9-]+$/i),
  body().custom((value) => {
    const allowed = new Set(['reason', 'details']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('reason').isIn(MESSAGE_REPORT_REASONS),
  body('details').optional().custom(textInput).bail().trim().isLength({ max: 1000 }),
  body().custom((value) => {
    if (value.reason === 'other' && !value.details?.trim()) {
      throw new Error('Details are required for an other report');
    }
    return true;
  }),
];

export const reportsValidation = [
  ...paginationValidation,
  query('status').optional().isIn(['open', 'resolved', 'dismissed']),
];

export const resolveReportValidation = [
  param('reportId').matches(/^RPT-MSG-[A-Z0-9-]+$/i),
  body().custom((value) => {
    const allowed = new Set(['status', 'resolution']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('status').isIn(['resolved', 'dismissed']),
  body('resolution').custom(textInput).bail().trim().isLength({ min: 3, max: 1000 }),
];

export const notificationsValidation = [
  ...paginationValidation,
  query('category').optional().isIn(NOTIFICATION_CATEGORIES),
  query('read').optional().isBoolean(),
];

export const notificationIdValidation = [
  param('notificationId').matches(/^NTF-[A-Z0-9-]+$/i),
];

export const deviceRegistrationValidation = [
  body().custom((value) => {
    const allowed = new Set(['deviceId', 'deviceName', 'platform', 'token']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('deviceId').custom(textInput).bail().trim().isLength({ min: 8, max: 120 }),
  body('deviceName').optional().custom(textInput).bail().trim().isLength({ max: 120 }),
  body('platform').isIn(PUSH_PLATFORMS),
  body('token').custom(textInput).bail().trim().isLength({ min: 20, max: 4096 }),
];

export const deviceIdValidation = [
  param('deviceId').custom(textInput).bail().trim()
    .isLength({ min: 8, max: 120 })
    .matches(/^[a-zA-Z0-9._:-]+$/),
];
