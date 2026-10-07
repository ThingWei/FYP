import { AppError } from '../../core/errors.js';
import { drivingEligibilityCheck, hasApprovedMykad } from './drivingEligibility.js';

export const DEFAULT_KYC_REQUIREMENTS = Object.freeze([
  { category: 'Devices', documentTypes: ['mykad'], highValueOnly: false },
  {
    category: 'Vehicles',
    documentTypes: ['mykad', 'driving_licence'],
    highValueOnly: false,
  },
  { category: 'Equipment', documentTypes: ['mykad'], highValueOnly: false },
  { category: 'Services', documentTypes: ['mykad'], highValueOnly: false },
  { category: 'Clothing', documentTypes: ['mykad'], highValueOnly: false },
  { category: 'Books', documentTypes: ['mykad'], highValueOnly: false },
]);

export function resolveKycRequirement(settings, listing) {
  // Vehicle credentials cannot be disabled by old or editable category settings.
  if (listing.category === 'Vehicles') return {
    category: 'Vehicles', requiredDocumentTypes: ['mykad', 'driving_licence'],
    required: true, highValueOnly: false,
  };
  const configured = settings?.kycRequirements?.length
    ? settings.kycRequirements
    : DEFAULT_KYC_REQUIREMENTS;
  const rule = configured.find((item) => item.category === listing.category);
  const applies = rule?.highValueOnly
    ? Boolean(settings?.highValueKycEnabled) &&
      Number(listing.dailyPrice ?? 0) >= Number(settings?.highValueThreshold ?? 1000)
    : true;
  return {
    category: listing.category,
    // Mandatory identity cannot be disabled by legacy/category/high-value settings.
    // Preserve any applicable additional document requirements.
    requiredDocumentTypes: [...new Set(['mykad', ...(applies ? rule?.documentTypes ?? [] : [])])]
      .filter((type) => type !== 'driving_licence'),
    required: true,
    highValueOnly: false,
    threshold: Number(settings?.highValueThreshold ?? 1000),
  };
}

export function assertMarketplaceIdentity(user, action, category) {
  if (hasApprovedMykad(user)) return;
  const status = user.verification?.documents?.find((document) => document.documentType === 'mykad')?.status
    ?? (user.verification?.documentType === 'mykad' ? user.verification.status : 'unverified');
  throw new AppError(
    'Administrator-approved MyKad identity verification is required before booking or submitting a listing.',
    403, 'KYC_REQUIRED', {
      action, category, verificationStatus: status,
      requiredDocumentTypes: ['mykad'], missingDocumentTypes: ['mykad'],
      nextAction: 'mykad_identity',
    },
  );
}

export function approvedDocumentTypes(user) {
  const approved = new Set(
    (user.verification?.documents ?? [])
      .filter((document) => document.status === 'approved' && document.documentType !== 'driving_licence')
      .map((document) => document.documentType),
  );
  if (
    user.verification?.status === 'approved' &&
    user.verification?.documentType && user.verification.documentType !== 'driving_licence' &&
    !(user.verification.documents ?? []).some((document) => document.documentType === user.verification.documentType)
  ) {
    approved.add(user.verification.documentType);
  }
  if (drivingEligibilityCheck(user).valid) approved.add('driving_licence');
  return approved;
}
