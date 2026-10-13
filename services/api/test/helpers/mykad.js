export function validMykadFields(overrides = {}) {
  return {
    documentType: 'mykad', identityNumber: '900101-07-1234', identityNumberFormatValid: true,
    mykadSidesConsistent: true,
    mandatoryMykadValidation: {
      method: 'mykad-required-fields-v2', status: 'matched', accepted: true, authenticityVerified: false,
      sides: ['front', 'back'].map(side => ({
        method: 'mykad-required-fields-v2', status: 'validated', accepted: true,
        expectedSide: side, detectedSide: side, authenticityVerified: false,
        screenCopy: { status: 'not_detected', cues: [], phoneScreen: { status: 'not_detected', method: 'enclosing-phone-v1' } },
        requiredFields: Object.fromEntries((side === 'front'
          ? ['front_identity_number', 'front_name', 'front_address'] : ['back_identity_number'])
          .map(field => [field, { detected: true, readable: true }]))
      }))
    },
    ...overrides
  };
}

