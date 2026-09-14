import { body, param, query } from 'express-validator';
import {
  ACCOUNT_STATUSES,
  USER_ROLES,
} from './user.model.js';

const userId = param('id')
  .trim()
  .matches(/^(?:[a-f\d]{24}|u-[a-z\d-]+)$/i)
  .withMessage('Invalid user identifier');

export const profileValidation = [
  body().custom((value) => {
    const fields = ['displayName', 'phone', 'avatarUrl', 'addresses', 'settings'];
    if (!fields.some((field) => value[field] !== undefined)) {
      throw new Error('At least one profile field is required');
    }
    return true;
  }),
  body('displayName').optional().trim().isLength({ min: 2, max: 80 }),
  body('phone').optional().trim().isLength({ max: 24 }),
  body('avatarUrl')
    .optional()
    .trim()
    .custom((value) => value === '' || URL.canParse(value))
    .withMessage('avatarUrl must be empty or a valid URL'),
  body('addresses').optional().isArray({ max: 10 }),
  body('addresses.*.label').optional().trim().notEmpty().isLength({ max: 40 }),
  body('addresses.*.line1').optional().trim().notEmpty().isLength({ max: 120 }),
  body('addresses.*.line2').optional().trim().isLength({ max: 120 }),
  body('addresses.*.city').optional().trim().notEmpty().isLength({ max: 80 }),
  body('addresses.*.state').optional().trim().notEmpty().isLength({ max: 80 }),
  body('addresses.*.postcode')
    .optional()
    .trim()
    .matches(/^\d{5}$/),
  body('addresses.*.isDefault').optional().isBoolean(),
  body('settings').optional().isObject(),
  body('settings.language').optional().isIn(['en', 'ms']),
  body('settings.pushNotifications').optional().isBoolean(),
  body('settings.emailNotifications').optional().isBoolean(),
];

export const roleValidation = [body('role').isIn(USER_ROLES)];

export const targetUserValidation = [
  param('userId')
    .trim()
    .matches(/^(?:[a-f\d]{24}|u-[a-z\d-]+)$/i)
    .withMessage('Invalid user identifier'),
];

export const publicUserValidation = [userId];

export const listValidation = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('search').optional().trim().isLength({ max: 100 }),
  query('role').optional().isIn(USER_ROLES),
  query('status').optional().isIn(ACCOUNT_STATUSES),
];

export const accountStatusValidation = [
  userId,
  body('status').isIn(ACCOUNT_STATUSES),
  body('reason').optional().trim().isLength({ max: 500 }),
];
