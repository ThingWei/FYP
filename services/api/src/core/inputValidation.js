// Validate before sanitizing: never reinterpret malformed human input as a number.
export function textInput(value) {
  if (typeof value !== 'string' || /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/.test(value)) {
    throw new Error('Enter text without unsupported control characters');
  }
  return true;
}

export function numericInput(value) {
  const valid = typeof value === 'number' ? Number.isFinite(value) && value >= 0
    : typeof value === 'string' && /^\d+(?:\.\d+)?$/.test(value.trim());
  if (!valid || !Number.isFinite(Number(value))) throw new Error('Enter a finite non-negative number without letters or exponent notation');
  return true;
}

export function wholeInput(value) {
  numericInput(value);
  if (typeof value === 'string' && !/^\d+$/.test(value.trim()) || !Number.isSafeInteger(Number(value))) {
    throw new Error('Enter a whole number');
  }
  return true;
}

export function moneyInput(value) {
  numericInput(value);
  if (Number(value) * 100 > Number.MAX_SAFE_INTEGER ||
      typeof value === 'string' && !/^\d+(?:\.\d{1,2})?$/.test(value.trim()) ||
      Math.abs(Number(value) * 100 - Math.round(Number(value) * 100)) > 0.000001) {
    throw new Error('Money amounts must have at most two decimal places');
  }
  return true;
}

export function malaysianMobile(value) {
  if (typeof value !== 'string' || value.trim() !== '' &&
      !/^(\+?60|0)1(([0145]\d{7,8})|([236-9]\d{7}))$/.test(value.trim().replace(/[ -]/g, ''))) {
    throw new Error('Enter a valid Malaysian mobile number (01… or +601…)');
  }
  return true;
}
