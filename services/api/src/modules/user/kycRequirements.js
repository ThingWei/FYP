import { drivingEligibilityCheck } from './drivingEligibility.js';

export const DEFAULT_KYC_REQUIREMENTS = Object.freeze([
  { category: 'Devices', documentTypes: ['mykad'], highValueOnly: true },
  {
    category: 'Vehicles',
    documentTypes: ['mykad', 'driving_licence'],
    highValueOnly: false,
  },
  { category: 'Equipment', documentTypes: ['mykad'], highValueOnly: true },
  { category: 'Services', documentTypes: ['mykad'], highValueOnly: false },
  { category: 'Clothing', documentTypes: [], highValueOnly: false },
  { category: 'Books', documentTypes: [], highValueOnly: false },
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
  if (!rule) {
    return { category: listing.category, requiredDocumentTypes: [], required: false };
  }
  const applies = rule.highValueOnly
    ? Boolean(settings?.highValueKycEnabled) &&
      Number(listing.dailyPrice ?? 0) >= Number(settings?.highValueThreshold ?? 1000)
    : true;
  return {
    category: listing.category,
    requiredDocumentTypes: applies ? rule.documentTypes.filter((type) => type !== 'driving_licence') : [],
    required: applies && rule.documentTypes.some((type) => type !== 'driving_licence'),
    highValueOnly: Boolean(rule.highValueOnly),
    threshold: Number(settings.highValueThreshold ?? 1000),
  };
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
