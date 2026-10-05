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
    requiredDocumentTypes: applies ? [...rule.documentTypes] : [],
    required: applies && rule.documentTypes.length > 0,
    highValueOnly: Boolean(rule.highValueOnly),
    threshold: Number(settings.highValueThreshold ?? 1000),
  };
}

export function approvedDocumentTypes(user) {
  const approved = new Set(
    (user.verification?.documents ?? [])
      .filter((document) => document.status === 'approved')
      .map((document) => document.documentType),
  );
  if (
    user.verification?.status === 'approved' &&
    user.verification?.documentType
  ) {
    approved.add(user.verification.documentType);
  }
  return approved;
}
