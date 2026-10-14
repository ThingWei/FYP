import { validCoordinates } from '../../core/location.js';
import { textInput } from '../../core/inputValidation.js';
import { malaysianMobile } from '../../core/inputValidation.js';
import { numericInput, wholeInput, moneyInput } from '../../core/inputValidation.js';
import { body, param, query } from 'express-validator';
import { LICENCE_CLASSES } from './drivingEligibility.js';
import {
  ACCOUNT_STATUSES,
  USER_ROLES,
  VERIFICATION_STATUSES,
} from './user.model.js';
import { isUploadReference } from '../../core/uploadReference.js';

const userId = param('id').custom(textInput).bail().trim()
  .matches(/^(?:[a-f\d]{24}|u-[a-z\d-]+)$/i)
  .withMessage('Invalid user identifier');

const email = () => body('email').custom(textInput).bail().trim().isEmail().normalizeEmail();
const password = () =>
  body('password')
    .isString()
    .isLength({ min: 8, max: 128 })
    .withMessage('Password must contain between 8 and 128 characters');

export const localLoginValidation = [
  email(),
  password(),
  body('role').isIn(USER_ROLES),
];

export const localRegistrationValidation = [
  body('displayName').custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
  email(),
  password(),
  body('role').isIn(['renter', 'owner']),
];

export const localRefreshValidation = [
  body('refreshToken').isString().isLength({ min: 40, max: 500 }),
];

export const localSessionIdValidation = [
  param('sessionId').isUUID().withMessage('Invalid login session identifier'),
];

export const passwordResetRequestValidation = [email()];

export const passwordResetConfirmationValidation = [
  email(),
  body('code')
    .isString().bail()
    .trim()
    .matches(/^\d{6}$/)
    .withMessage('Reset code must contain 6 digits'),
  password(),
];

export const profileValidation = [
  body().custom((value) => {
    const fields = ['displayName', 'phone', 'avatarUrl', 'addresses', 'settings'];
    if (!fields.some((field) => value[field] !== undefined)) {
      throw new Error('At least one profile field is required');
    }
    return true;
  }),
  body('displayName').optional().custom(textInput).bail().trim().isLength({ min: 2, max: 80 }),
  body('phone').optional().isString().bail().trim().isLength({ max: 24 }).custom(malaysianMobile),
  body('avatarUrl')
    .optional().custom(textInput).bail().trim()
    .custom(
      (value) =>
        value === '' ||
        URL.canParse(value) ||
        isUploadReference(value, { publicOnly: true }),
    )
    .withMessage('avatarUrl must be empty, a valid URL, or a public upload'),
  body('addresses').optional().isArray({ max: 10 }),
  body('addresses.*._id').optional().isMongoId(),
  body('addresses.*.coordinates').optional().custom((v) => { if (!validCoordinates(v)) throw new Error('Confirm a valid address pin'); return true; }),
  body('addresses.*.label').optional().custom(textInput).bail().trim().notEmpty().isLength({ max: 40 }),
  body('addresses.*.line1').optional().custom(textInput).bail().trim().notEmpty().isLength({ max: 120 }),
  body('addresses.*.line2').optional().custom(textInput).bail().trim().isLength({ max: 120 }),
  body('addresses.*.city').optional().custom(textInput).bail().trim().notEmpty().isLength({ max: 80 }),
  body('addresses.*.state').optional().custom(textInput).bail().trim().notEmpty().isLength({ max: 80 }),
  body('addresses.*.postcode')
    .optional()
    .isString().bail()
    .trim()
    .matches(/^\d{5}$/),
  body('addresses.*.isDefault').optional().isBoolean(),
  body('settings').optional().isObject(),
  body('settings.language').optional().isIn(['en', 'ms']),
  body('settings.pushNotifications').optional().isBoolean(),
  body('settings.emailNotifications').optional().isBoolean(),
];

export const roleValidation = [body('role').isIn(USER_ROLES)];

export const verificationSubmissionValidation = [
  body().custom((value) => {
    const allowed = new Set(['documentType', 'documentRefs', 'licenceSource']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    if (value.licenceSource && value.documentType !== 'driving_licence') throw new Error('Licence source is only used for driving evidence');
    return true;
  }),
  body('documentType').isIn(['mykad', 'passport', 'driving_licence']),
  body('licenceSource').optional().isIn(['physical', 'myjpj']),
  body('documentRefs').isArray({ min: 1, max: 2 }),
  body('documentRefs.*').custom(textInput).bail().trim()
    .custom((value) => isUploadReference(value))
    .withMessage('Each document must reference an uploaded image'),
];

export const verificationPairValidation = [
  body().custom(value => {
    if (Object.keys(value).some(key => !['frontDocumentRef', 'backDocumentRef'].includes(key))) {
      throw new Error('Only front and back upload references are accepted');
    }
    if (value.frontDocumentRef === value.backDocumentRef) throw new Error('Use distinct front and back images');
    return true;
  }),
  ...['frontDocumentRef', 'backDocumentRef'].map(field => body(field).custom(textInput).bail().isLength({ max: 100 })
    .matches(/^upload:\/\/UPL-[A-Z0-9]+$/)),
];

export const drivingEvidenceValidation = [
  body().custom(value => {
    if (Object.keys(value).some(key => !['documentRef', 'licenceSource'].includes(key))) throw new Error('Only licence upload reference and source are accepted');
    return true;
  }),
  body('documentRef').isString().isLength({ max: 100 }).matches(/^upload:\/\/UPL-[A-Z0-9]+$/),
  body('licenceSource').optional().isIn(['physical', 'myjpj']),
];

export const targetUserValidation = [
  param('userId').custom(textInput).bail().trim()
    .matches(/^(?:[a-f\d]{24}|u-[a-z\d-]+)$/i)
    .withMessage('Invalid user identifier'),
];

export const savedListingValidation = [
  param('listingId').custom(textInput).bail().trim()
    .matches(/^l-[a-z\d-]+$/i)
    .withMessage('Invalid listing identifier'),
];

export const comparisonValidation = [
  body().custom((value) => {
    const unknown = Object.keys(value).filter((field) => field !== 'listingIds');
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('listingIds').isArray({ max: 4 }),
  body('listingIds.*').matches(/^l-[a-z\d-]+$/i),
  body('listingIds').custom((ids) => {
    if (new Set(ids).size !== ids.length) {
      throw new Error('Comparison listing identifiers must be unique');
    }
    return true;
  }),
];

export const publicUserValidation = [userId];

export const listValidation = [
  query('page').optional().custom(wholeInput).bail().isInt({ min: 1 }),
  query('limit').optional().custom(wholeInput).bail().isInt({ min: 1, max: 100 }),
  query('search').optional().custom(textInput).bail().trim().isLength({ max: 100 }),
  query('role').optional().isIn(USER_ROLES),
  query('status').optional().isIn(ACCOUNT_STATUSES),
];

export const accountStatusValidation = [
  userId,
  body('status').isIn(ACCOUNT_STATUSES),
  body('reason').optional().custom(textInput).bail().trim().isLength({ max: 500 }),
];

export const accountDeactivationValidation = [
  body('confirmation')
    .equals('true')
    .withMessage('Account deactivation must be confirmed')
    .toBoolean(),
  body('reason').custom(textInput).bail().trim().isLength({ min: 5, max: 500 }),
  body().custom((value) => {
    const allowed = new Set(['confirmation', 'reason']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
];

export const verificationDecisionValidation = [
  ...targetUserValidation,
  body('status').isIn(
    VERIFICATION_STATUSES.filter((status) =>
      ['approved', 'rejected', 'resubmission_required'].includes(status),
    ),
  ),
  body('licenceClasses').optional().isArray({ min: 1, max: 15 }).custom((classes) => new Set(classes).size === classes.length),
  body('licenceClasses.*').optional().isIn(LICENCE_CLASSES),
  body('expiresAt').optional().matches(/^\d{4}-\d{2}-\d{2}$/).isISO8601({ strict: true }),
  body('identityMatchConfirmed').optional().isBoolean().toBoolean(),
  body('classReviewConfirmed').optional().isBoolean().toBoolean(),
  body('reason').optional().custom(textInput).bail().trim().isLength({ max: 500 }),
  body('attemptId')
    .optional().custom(textInput).bail().trim()
    .matches(/^KYC-[A-F\d]{24}$/i),
];

export const verificationFrameValidation = [
  body().custom((value) => {
    const allowed = new Set(['contentBase64', 'contentType', 'documentType', 'expectedSide', 'validateCapture', 'frontDocumentRef', 'backDocumentRef', 'licenceSource']);
    const unknown = Object.keys(value).filter((field) => !allowed.has(field));
    if (unknown.length) throw new Error(`Unknown fields: ${unknown.join(', ')}`);
    return true;
  }),
  body('contentBase64').isString().isLength({ min: 100, max: 1_900_000 }),
  body('contentType').optional().isIn(['image/jpeg', 'image/png']),
  body('documentType').isIn(['mykad', 'passport', 'driving_licence']),
  body('licenceSource').optional().isIn(['physical', 'myjpj']),
  body('expectedSide').optional().isIn(['front', 'back']),
  body('validateCapture').optional().custom((value) => typeof value === 'boolean'),
  body('frontDocumentRef').optional().isString().matches(/^upload:\/\/UPL-[A-Z0-9]+$/),
  body('backDocumentRef').optional().isString().isLength({ max: 100 }).matches(/^upload:\/\/UPL-[A-Z0-9]+$/),
  body().custom((value) => {
    if (value.licenceSource && value.documentType !== 'driving_licence') throw new Error('Licence source is only used for driving evidence');
    if (value.documentType === 'mykad' && value.validateCapture && !value.expectedSide) {
      throw new Error('MyKad capture validation requires the expected front/back side');
    }
    if (value.frontDocumentRef && (value.documentType !== 'mykad' || value.expectedSide !== 'back' || value.validateCapture !== true)) {
      throw new Error('Front image reference is only used for the final MyKad back check');
    }
    if (value.backDocumentRef && (value.documentType !== 'mykad' || value.expectedSide !== 'front' || value.validateCapture !== true)) {
      throw new Error('Back image reference is only used for the final MyKad front replacement check');
    }
    return true;
  }),
];

export const verificationRequirementsValidation = [
  query('category').isIn([
    'Clothing',
    'Vehicles',
    'Services',
    'Devices',
    'Books',
    'Equipment',
  ]),
  query('dailyPrice').optional().custom(moneyInput).bail().isFloat({ min: 0, max: 1_000_000 }).toFloat(),
  query('requiredLicenceClass').optional().isIn(LICENCE_CLASSES),
];
