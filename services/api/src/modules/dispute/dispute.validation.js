import { body, param, query } from 'express-validator';
import { CLAIM_STATUSES } from './claim.model.js';
import {
  DISPUTE_STATUSES,
  GENERAL_DISPUTE_CATEGORIES,
  PHYSICAL_DISPUTE_CATEGORIES,
  SERVICE_DISPUTE_CATEGORIES,
} from './dispute.model.js';

const disputeId = param('id').trim().matches(/^RH-DSP-[A-Z0-9]+$/);
const claimId = param('claimId').trim().matches(/^RH-CLM-[A-Z0-9]+$/);
const evidence = body('evidence')
  .optional()
  .isArray({ max: 10 })
  .custom((items) => items.every((item) => typeof item === 'string' && item.length <= 500));
const pagination = [
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
];

export const createDisputeValidation = [
  body('rentalId').trim().matches(/^RH-RNT-\d{4}-[A-Z0-9]+$/),
  body('category').isIn([
    ...PHYSICAL_DISPUTE_CATEGORIES,
    ...SERVICE_DISPUTE_CATEGORIES,
    ...GENERAL_DISPUTE_CATEGORIES,
  ]),
  body('summary').trim().isLength({ min: 5, max: 160 }),
  body('description').trim().isLength({ min: 20, max: 3000 }),
  evidence,
];

export const disputeListValidation = [
  ...pagination,
  query('status').optional().isIn(DISPUTE_STATUSES),
];

export const disputeDetailValidation = [disputeId];

export const responseValidation = [
  disputeId,
  body('text').trim().isLength({ min: 5, max: 2000 }),
  evidence,
];

export const claimCreateValidation = [
  disputeId,
  body('description').trim().isLength({ min: 20, max: 3000 }),
  body('amountRequested').isFloat({ min: 0.01 }).toFloat(),
  body('evidence')
    .isArray({ min: 1, max: 10 })
    .custom((items) => items.every((item) => typeof item === 'string' && item.length <= 500)),
];

export const claimListValidation = [
  ...pagination,
  query('status').optional().isIn(CLAIM_STATUSES),
];

export const reviewStatusValidation = [
  disputeId,
  body('status').isIn(['under_review', 'more_evidence_required', 'escalated']),
  body('note').trim().isLength({ min: 5, max: 2000 }),
];

export const resolveValidation = [
  disputeId,
  body('outcome').isIn([
    'release_to_renter',
    'split',
    'release_to_owner',
    'dismissed',
  ]),
  body('renterAmount').optional().isFloat({ min: 0 }).toFloat(),
  body('ownerAmount').optional().isFloat({ min: 0 }).toFloat(),
  body('notes').trim().isLength({ min: 10, max: 2000 }),
];

export const claimDecisionValidation = [
  claimId,
  body('status').isIn(['approved', 'rejected']),
  body('reason').trim().isLength({ min: 5, max: 1000 }),
  body('approvedAmount').optional().isFloat({ min: 0 }).toFloat(),
];
