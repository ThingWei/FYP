import { ProductCatalogModel } from './productCatalog.model.js';
import { catalogTypesFor } from './catalog.typeMetadata.js';
export { catalogTypesFor } from './catalog.typeMetadata.js';

// Server-owned catalogue metadata narrows recognition. Never trust a submitted
// productType, model-name guess or price inference as image evidence.
export async function catalogItemType(listing) {
  if (!listing.canonicalProductId || listing.listingType !== 'physical') return null;
  const entry = await ProductCatalogModel.findOne({
    entityType: 'product', canonicalProductId: listing.canonicalProductId,
    category: listing.category, subcategory: listing.subcategory,
    brand: listing.brand, model: listing.productModel,
  }).select('specifications.productType').lean();
  const type = entry?.specifications?.productType;
  return typeof type === 'string' && /^[a-z][a-z0-9_]{0,63}$/.test(type) ? type : null;
}

export async function withCatalogTypes(items) {
  const ids = [...new Set(items.map((r) => r.canonicalProductId).filter(Boolean))];
  if (!ids.length) return items;
  const entries = await ProductCatalogModel.find({ entityType: 'product', canonicalProductId: { $in: ids } })
    .select('canonicalProductId category subcategory brand model specifications.productType').limit(2000).lean();
  return catalogTypesFor(items, entries);
}
