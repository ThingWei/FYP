import { body, query } from 'express-validator';
import { LOYALTY_ENTRY_TYPES } from './loyalty.model.js';

const pagination = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
];

export const redeemValidation = [
  body().custom((value) => {
    const unknown = Object.keys(value).filter((field) => field !== 'points');
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('points').isInt({ min: 1 }).toInt(),
];

export const referralValidation = [
  body().custom((value) => {
    const unknown = Object.keys(value).filter(
      (field) => field !== 'referralCode',
    );
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('referralCode')
    .trim()
    .toUpperCase()
    .matches(/^RH-[A-Z0-9]{5,20}$/),
];

export const configValidation = [
  body().custom((value) => {
    const allowed = new Set([
      'enabled',
      'physicalCompletionPoints',
      'serviceCompletionPoints',
      'referralRewardPoints',
      'refereeDiscountAmount',
      'redemptionOptions',
    ]);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('enabled').isBoolean(),
  body('physicalCompletionPoints').isInt({ min: 0, max: 10000 }).toInt(),
  body('serviceCompletionPoints').isInt({ min: 0, max: 10000 }).toInt(),
  body('referralRewardPoints').isInt({ min: 0, max: 10000 }).toInt(),
  body('refereeDiscountAmount').isFloat({ min: 0, max: 1000 }).toFloat(),
  body('redemptionOptions').isArray({ min: 1, max: 10 }),
  body('redemptionOptions.*.points').isInt({ min: 1, max: 100000 }).toInt(),
  body('redemptionOptions.*.discountAmount')
    .isFloat({ min: 0.01, max: 10000 })
    .toFloat(),
  body('redemptionOptions').custom((options) => {
    const costs = options.map((option) => option.points);
    if (new Set(costs).size !== costs.length) {
      throw new Error('Redemption point costs must be unique');
    }
    return true;
  }),
];

export const adminLedgerValidation = [
  ...pagination,
  query('type').optional().isIn(LOYALTY_ENTRY_TYPES),
];

export const adminReferralValidation = [
  ...pagination,
  query('status').optional().isIn(['pending', 'rewarded']),
];
