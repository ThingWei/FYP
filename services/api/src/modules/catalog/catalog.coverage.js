export const CATALOG_COVERAGE = Object.freeze([
  { category: 'Devices', subcategory: 'Smartphones', strategies: ['wikidata-smartphones', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Devices', subcategory: 'Cameras', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Devices', subcategory: 'Computers', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Devices', subcategory: 'Audio', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Devices', subcategory: 'Gaming', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Devices', subcategory: 'Other devices', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Vehicles', subcategory: 'Cars', strategies: ['nhtsa-vpic', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Vehicles', subcategory: 'Motorcycles', strategies: ['nhtsa-vpic', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Vehicles', subcategory: 'Bicycles', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Vehicles', subcategory: 'Other vehicles', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Equipment', subcategory: 'Event equipment', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Equipment', subcategory: 'Tools', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Equipment', subcategory: 'Sports equipment', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Equipment', subcategory: 'Other equipment', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Books', subcategory: 'Textbooks', strategies: ['openlibrary', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Books', subcategory: 'Reference books', strategies: ['openlibrary', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Books', subcategory: 'Fiction', strategies: ['openlibrary', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Books', subcategory: 'Other books', strategies: ['openlibrary', 'renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Clothing', subcategory: 'Formal wear', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Clothing', subcategory: 'Costumes', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Clothing', subcategory: 'Traditional wear', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
  { category: 'Clothing', subcategory: 'Other clothing', strategies: ['renthub-curated', 'wikidata-validated', 'manual-entry'] },
]);

export function catalogCoverageFor(category, subcategory) {
  return CATALOG_COVERAGE.find((entry) =>
    entry.category === category && entry.subcategory === subcategory) ?? {
    category,
    subcategory,
    strategies: ['wikidata-validated', 'manual-entry'],
  };
}
