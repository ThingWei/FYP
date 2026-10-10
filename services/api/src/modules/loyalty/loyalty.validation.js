import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, query } from 'express-validator';
import { LOYALTY_ENTRY_TYPES } from './loyalty.model.js';

const pagination = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
];

export const redeemValidation = [
  body().custom((value) => {
    const unknown = Object.keys(value).filter((field) => field !== 'points');
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('points').custom(wholeInput).bail().isInt({ min: 1 }).toInt(),
];

export const referralValidation = [
  body().custom((value) => {
    const unknown = Object.keys(value).filter(
      (field) => field !== 'referralCode',
    );
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('referralCode').custom(textInput).bail().trim()
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
  body('physicalCompletionPoints').custom(wholeInput).bail().isInt({ min: 0, max: 10000 }).toInt(),
  body('serviceCompletionPoints').custom(wholeInput).bail().isInt({ min: 0, max: 10000 }).toInt(),
  body('referralRewardPoints').custom(wholeInput).bail().isInt({ min: 0, max: 10000 }).toInt(),
  body('refereeDiscountAmount').custom(moneyInput).bail().isFloat({ min: 0, max: 1000 }).toFloat(),
  body('redemptionOptions').isArray({ min: 1, max: 10 }),
  body('redemptionOptions.*.points').custom(wholeInput).bail().isInt({ min: 1, max: 100000 }).toInt(),
  body('redemptionOptions.*.discountAmount')
    .custom(moneyInput).bail().isFloat({ min: 0.01, max: 10000 })
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
