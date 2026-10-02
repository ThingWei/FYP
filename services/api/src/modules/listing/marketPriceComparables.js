const conditionWeight = {
  Fair: 0.72,
  Good: 0.84,
  'Very good': 0.93,
  Excellent: 1,
  'Like New': 1.08,
};

const resaleToDailyRentalFactor = {
  Books: 0.08,
  Clothing: 0.08,
  Devices: 0.035,
  Equipment: 0.04,
  Vehicles: 0.025,
};

// Manually reviewed, short-term Malaysian rental asking prices. Keep the
// observation date and source so stale evidence is visible and replaceable.
// Financing, subscriptions and rent-to-own offers must not be added here.
const references = [
  {
    category: 'Devices',
    subcategory: 'Smartphones',
    brand: 'Apple',
    productModel: 'iPhone 13 Pro 256GB',
    condition: 'Used',
    dailyPrice: 100,
    evidenceType: 'short_term_rental',
    state: 'Kuala Lumpur',
    observedAt: '2026-10-02',
    sourceUrl: 'https://www.carousell.com.my/phone-rental/q/',
  },
  {
    category: 'Devices',
    subcategory: 'Smartphones',
    brand: 'Apple',
    productModel: 'iPhone 15 Pro Max 256GB',
    condition: 'Brand new',
    dailyPrice: 100,
    evidenceType: 'short_term_rental',
    state: 'Kuala Lumpur',
    observedAt: '2026-10-02',
    sourceUrl: 'https://www.carousell.com.my/phone-rental/q/',
  },
  {
    category: 'Devices',
    subcategory: 'Smartphones',
    brand: 'Apple',
    productModel: 'iPhone 15 Pro Max 256GB',
    condition: 'Like new',
    dailyPrice: 80,
    evidenceType: 'short_term_rental',
    state: 'Kuala Lumpur',
    observedAt: '2026-10-02',
    sourceUrl: 'https://www.carousell.com.my/phone-rental-service/q/',
  },
  {
    category: 'Devices',
    subcategory: 'Smartphones',
    brand: 'Apple',
    productModel: 'iPhone 16 Pro Max 256GB',
    condition: 'Brand new',
    dailyPrice: 120,
    evidenceType: 'short_term_rental',
    state: 'Kuala Lumpur',
    observedAt: '2026-10-02',
    sourceUrl:
      'https://www.carousell.com.my/p/for-rent-sewa-iphone-16-pro-max-256-gb-phone-rental-service-1335538719/',
  },
  {
    category: 'Devices',
    subcategory: 'Smartphones',
    brand: 'Apple',
    productModel: 'iPhone 17 Pro Max 256GB',
    condition: 'Like new',
    dailyPrice: 180,
    evidenceType: 'short_term_rental',
    state: 'Kuala Lumpur',
    observedAt: '2026-10-02',
    sourceUrl: 'https://www.carousell.com.my/phone-rental-service/q/',
  },
  {
    category: 'Books',
    subcategory: 'Fiction',
    brand: 'J.R.R. Tolkien',
    productModel: 'The Lord of the Rings Trilogy',
    aliases: ['Lord of the Rings', 'Lord of the Ring', 'LOTR Trilogy'],
    condition: 'Heavily used',
    marketPrice: 50,
    evidenceType: 'resale_asking',
    state: 'Malaysia',
    observedAt: '2026-10-02',
    sourceUrl:
      'https://www.carousell.com.my/hobbies-toys/books-magazines/lord-of-the-rings/q-5/',
  },
  {
    category: 'Books',
    subcategory: 'Fiction',
    brand: 'J.R.R. Tolkien',
    productModel: 'The Lord of the Rings Trilogy',
    aliases: ['Lord of the Rings', 'Lord of the Ring', 'LOTR Trilogy'],
    condition: 'Lightly used',
    marketPrice: 50,
    evidenceType: 'resale_asking',
    state: 'Malaysia',
    observedAt: '2026-10-02',
    sourceUrl:
      'https://www.carousell.com.my/hobbies-toys/books-magazines/lord-of-the-rings/q-5/',
  },
  {
    category: 'Books',
    subcategory: 'Fiction',
    brand: 'J.R.R. Tolkien',
    productModel: 'The Fellowship of the Ring',
    aliases: ['Fellowship of the Ring'],
    condition: 'Well used',
    marketPrice: 15,
    evidenceType: 'resale_asking',
    state: 'Malaysia',
    observedAt: '2026-10-02',
    sourceUrl:
      'https://www.carousell.com.my/hobbies-toys/books-magazines/lord-of-the-rings/q-5/',
  },
  {
    category: 'Books',
    subcategory: 'Fiction',
    brand: 'J.R.R. Tolkien',
    productModel: 'The Fellowship of the Ring',
    aliases: ['Fellowship of the Ring'],
    condition: 'Lightly used',
    marketPrice: 20,
    evidenceType: 'resale_asking',
    state: 'Malaysia',
    observedAt: '2026-10-02',
    sourceUrl:
      'https://www.carousell.com.my/hobbies-toys/books-magazines/lord-of-the-rings/q-5/',
  },
];

function normalized(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function capacity(value) {
  return normalized(value).match(/\b(?:64|128|256|512) gb\b|\b1 tb\b/)?.[0] ?? '';
}

function baseModel(value) {
  return normalized(value)
    .replace(/\b(?:64|128|256|512) gb\b|\b1 tb\b/g, '')
    .replace(/\b(?:book|books|rental|rent)\b/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function compatibleModel(requested, candidate) {
  const left = baseModel(requested);
  const right = baseModel(candidate);
  const requestedCapacity = capacity(requested);
  const candidateCapacity = capacity(candidate);
  return (
    left.length >= 4 &&
    left === right &&
    (!requestedCapacity || !candidateCapacity || requestedCapacity === candidateCapacity)
  );
}

function compatibleBrand(requested, candidate) {
  const left = normalized(requested);
  const right = normalized(candidate);
  return (
    left === right ||
    (left.length >= 4 && right.split(' ').includes(left)) ||
    (right.length >= 4 && left.split(' ').includes(right))
  );
}

function requestedConditionWeight(condition) {
  return conditionWeight[condition] ?? 0.9;
}

function referenceConditionWeight(condition) {
  if (condition === 'Brand new') return 1.12;
  if (condition === 'Used') return 0.84;
  if (condition === 'Lightly used') return 0.93;
  if (condition === 'Well used') return 0.8;
  if (condition === 'Heavily used') return 0.68;
  const canonical = Object.keys(conditionWeight).find(
    (key) => key.toLowerCase() === String(condition).toLowerCase(),
  );
  return conditionWeight[canonical] ?? 0.9;
}

export function externalMarketComparables(profile, rentalDurationDays = 1) {
  const empty = {
    adjustedAverage: null,
    count: 0,
    evidenceTypes: [],
    directRentalCount: 0,
    resaleDerivedCount: 0,
    sources: [],
  };
  if (!profile.product_model || !profile.brand || !profile.subcategory) {
    return empty;
  }
  const matches = references.filter(
    (item) =>
      item.category === profile.category &&
      normalized(item.subcategory) === normalized(profile.subcategory) &&
      compatibleBrand(profile.brand, item.brand) &&
      [item.productModel, ...(item.aliases ?? [])].some((candidate) =>
        compatibleModel(profile.product_model, candidate),
      ),
  );
  if (!matches.length) return empty;

  const condition = requestedConditionWeight(profile.condition);
  const ageMultiplier = Math.max(0.75, 1 - Number(profile.item_age_years ?? 0) * 0.025);
  // Marketplace examples commonly discount subsequent days. This treats each
  // extra day as 10% cheaper, then converts the total back to a daily average.
  const days = Math.max(1, Number(rentalDurationDays) || 1);
  const durationMultiplier = (1 + (days - 1) * 0.9) / days;
  const adjusted = matches.map((item) => {
    const dailyBase =
      item.evidenceType === 'short_term_rental'
        ? item.dailyPrice
        : item.marketPrice * (resaleToDailyRentalFactor[item.category] ?? 0.05);
    return (
      dailyBase *
      (condition / referenceConditionWeight(item.condition)) *
      ageMultiplier *
      durationMultiplier
    );
  });
  const evidenceTypes = [...new Set(matches.map((item) => item.evidenceType))];
  return {
    adjustedAverage:
      Math.round((adjusted.reduce((sum, value) => sum + value, 0) / adjusted.length) * 100) /
      100,
    count: matches.length,
    evidenceTypes,
    directRentalCount: matches.filter(
      (item) => item.evidenceType === 'short_term_rental',
    ).length,
    resaleDerivedCount: matches.filter(
      (item) => item.evidenceType === 'resale_asking',
    ).length,
    sources: matches.map(
      ({ productModel, dailyPrice, marketPrice, evidenceType, observedAt, sourceUrl }) => ({
        productModel,
        evidenceType,
        ...(dailyPrice !== undefined && { dailyPrice }),
        ...(marketPrice !== undefined && { marketPrice }),
        observedAt,
        sourceUrl,
      }),
    ),
  };
}
