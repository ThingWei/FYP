// Synthetic OCR contract fixture, never a genuine licence or accuracy benchmark.
export const validDrivingFields = (overrides = {}) => ({
  documentType: 'driving_licence', identityNumber: '900101-07-1234',
  identityNumberFormatValid: true, licenceClass: 'D', licenceClasses: ['D'],
  validUntil: '2035-12-31', licenceValidation: {
    method: 'malaysian-driving-ocr-v1', status: 'ready_for_review',
    acceptedForReview: true, requiresAdminReview: true,
    authenticityVerified: false, officialVerification: false,
    fieldStates: { name: 'readable', ic_number: 'readable', licence_class: 'readable', valid_until: 'readable' },
  }, ...overrides,
});
