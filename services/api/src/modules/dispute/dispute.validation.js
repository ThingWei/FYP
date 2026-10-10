import { textInput } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { CLAIM_STATUSES } from './claim.model.js';
import {
  DISPUTE_STATUSES,
  GENERAL_DISPUTE_CATEGORIES,
  PHYSICAL_DISPUTE_CATEGORIES,
  SERVICE_DISPUTE_CATEGORIES,
} from './dispute.model.js';
import { isUploadReference } from '../../core/uploadReference.js';

const disputeId = param('id').custom(textInput).bail().trim().matches(/^RH-DSP-[A-Z0-9]+$/);
const claimId = param('claimId').custom(textInput).bail().trim().matches(/^RH-CLM-[A-Z0-9]+$/);
const evidence = body('evidence')
  .optional()
  .isArray({ max: 10 })
  .custom((items) => items.every((item) => isUploadReference(item)));
const pagination = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
];

export const createDisputeValidation = [
  body('rentalId').custom(textInput).bail().trim().matches(/^RH-RNT-\d{4}-[A-Z0-9]+$/),
  body('category').isIn([
    ...PHYSICAL_DISPUTE_CATEGORIES,
    ...SERVICE_DISPUTE_CATEGORIES,
    ...GENERAL_DISPUTE_CATEGORIES,
  ]),
  body('summary').custom(textInput).bail().trim().isLength({ min: 5, max: 160 }),
  body('description').custom(textInput).bail().trim().isLength({ min: 20, max: 3000 }),
  evidence,
];

export const disputeListValidation = [
  ...pagination,
  query('status').optional().isIn(DISPUTE_STATUSES),
];

export const disputeDetailValidation = [disputeId];

export const responseValidation = [
  disputeId,
  body('text').custom(textInput).bail().trim().isLength({ min: 5, max: 2000 }),
  evidence,
];

export const claimCreateValidation = [
  disputeId,
  body('description').custom(textInput).bail().trim().isLength({ min: 20, max: 3000 }),
  body('amountRequested').custom(moneyInput).bail().isFloat({ min: 0.01 }).toFloat(),
  body('evidence')
    .isArray({ min: 1, max: 10 })
    .custom((items) => items.every((item) => isUploadReference(item))),
];

export const claimListValidation = [
  ...pagination,
  query('status').optional().isIn(CLAIM_STATUSES),
];

export const reviewStatusValidation = [
  disputeId,
  body('status').isIn(['under_review', 'more_evidence_required', 'escalated']),
  body('note').custom(textInput).bail().trim().isLength({ min: 5, max: 2000 }),
];

export const resolveValidation = [
  disputeId,
  body('outcome').isIn([
    'release_to_renter',
    'split',
    'release_to_owner',
    'dismissed',
  ]),
  body('renterAmount').optional().custom(moneyInput).bail().isFloat({ min: 0 }).toFloat(),
  body('ownerAmount').optional().custom(moneyInput).bail().isFloat({ min: 0 }).toFloat(),
  body('notes').custom(textInput).bail().trim().isLength({ min: 10, max: 2000 }),
];

export const claimDecisionValidation = [
  claimId,
  body('status').isIn(['approved', 'rejected']),
  body('reason').custom(textInput).bail().trim().isLength({ min: 5, max: 1000 }),
  body('approvedAmount').optional().custom(moneyInput).bail().isFloat({ min: 0 }).toFloat(),
];
