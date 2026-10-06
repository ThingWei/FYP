import { AppError } from '../../core/errors.js';

export const LICENCE_CLASSES = ['A', 'A1', 'B', 'B1', 'B2', 'C', 'D', 'DA', 'E', 'E1', 'E2', 'F', 'G', 'H', 'I'];

export function hasApprovedMykad(user) {
  const documents = user.verification?.documents ?? [];
  return documents.some((document) => document.documentType === 'mykad' && document.status === 'approved') ||
    (!documents.some((document) => document.documentType === 'mykad') &&
      user.verification?.documentType === 'mykad' && user.verification?.status === 'approved');
}

export function drivingEligibilityCheck(user, listing = {}, throughDate, now = new Date()) {
  if (!hasApprovedMykad(user)) return { valid: false, code: 'MYKAD_REQUIRED', reason: 'Complete administrator-approved MyKad identity verification first.' };
  const driving = user.drivingEligibility;
  if (!driving || driving.status !== 'approved') {
    const legacy = (user.verification?.documents ?? []).some((document) => document.documentType === 'driving_licence' && document.status === 'approved');
    return { valid: false, code: 'DRIVING_ELIGIBILITY_REQUIRED', reason: legacy
      ? 'Your historical licence approval needs a new driving-eligibility review.'
      : 'Submit driving licence / MyJPJ evidence for administrator review.' };
  }
  const expiry = driving.expiresAt && new Date(driving.expiresAt);
  if (!expiry || !Number.isFinite(expiry.getTime()) || expiry < now || (throughDate && expiry < new Date(throughDate))) {
    return { valid: false, code: 'DRIVING_ELIGIBILITY_EXPIRED', reason: 'Driving eligibility is expired or does not cover the requested rental dates.' };
  }
  if (!driving.identityMatchConfirmed || !driving.classReviewConfirmed || !driving.licenceClasses?.length) {
    return { valid: false, code: 'DRIVING_ELIGIBILITY_REVIEW_REQUIRED', reason: 'Licence identity, class and validity need administrator re-review.' };
  }
  if (listing.requiredLicenceClass && !driving.licenceClasses.includes(listing.requiredLicenceClass)) {
    return { valid: false, code: 'DRIVING_LICENCE_CLASS_REQUIRED', reason: `This vehicle requires licence class ${listing.requiredLicenceClass}.` };
  }
  return { valid: true, code: null, reason: '' };
}

export function assertDrivingEligibility(user, listing, throughDate) {
  if (listing.category !== 'Vehicles') return;
  const check = drivingEligibilityCheck(user, listing, throughDate);
  if (!check.valid) throw new AppError(check.reason, 403, check.code, {
    category: 'Vehicles', requiredLicenceClass: listing.requiredLicenceClass || null,
    missingDocumentTypes: check.code === 'MYKAD_REQUIRED' ? ['mykad'] : ['driving_licence'],
    nextAction: check.code === 'MYKAD_REQUIRED' ? 'mykad_identity' : 'driving_eligibility',
  });
}

export function reviewedLicenceExpiry(value) {
  // Date-only admin input is valid through the end of that Malaysian calendar day.
  const expiry = /^\d{4}-\d{2}-\d{2}$/.test(value ?? '')
    ? new Date(`${value}T23:59:59.999+08:00`) : new Date(NaN);
  if (!Number.isFinite(expiry.getTime()) || expiry < new Date() ||
      new Date(expiry.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10) !== value) {
    throw new AppError('Enter an unexpired licence valid-until date (YYYY-MM-DD)', 400, 'INVALID_LICENCE_EXPIRY');
  }
  return expiry;
}
