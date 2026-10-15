import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';
export function comparisonGroup(listing) {
  if (listing.listingType !== 'physical') return null;
  return CATALOG_COVERAGE.find(row => row.category === listing.category && row.subcategory === listing.subcategory)
    ? `${listing.category}\0${listing.subcategory}` : null;
}
export function validComparison(listings) {
  return listings.length <= 3 && (!listings.length || comparisonGroup(listings[0]) !== null &&
    listings.every(item => comparisonGroup(item) === comparisonGroup(listings[0])));
}
