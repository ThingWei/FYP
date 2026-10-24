// Money entered by Owners is in cents; equivalent daily observations may retain
// additional precision when an explicitly quoted multi-day amount is divided.
export const MAX_RENTAL_PRICE = 1_000_000;

export function minimumRentalPrice(category, listingType = 'physical') {
  return category === 'Books' && listingType === 'physical' ? 0.01 : 1;
}

export function validRentalPrice(value, category, listingType = 'physical') {
  return Number.isFinite(value) && value >= minimumRentalPrice(category, listingType) &&
    value <= MAX_RENTAL_PRICE;
}

export function validPricePrecision(value) {
  return Number.isFinite(value) && Math.abs(value * 100 - Math.round(value * 100)) < 1e-6;
}
