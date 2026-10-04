import mongoose from 'mongoose';

export const PRODUCT_MATCH_TYPES = [
  'exact_catalog_match',
  'fuzzy_catalog_match',
  'manual_entry',
  'catalog_brand_match_model_manual',
];

const productCatalogSchema = new mongoose.Schema(
  {
    entityType: { type: String, enum: ['brand', 'product'], required: true },
    catalogEntityId: { type: String, required: true, trim: true },
    canonicalProductId: { type: String, trim: true, default: null },
    canonicalBrandId: { type: String, trim: true, default: null },
    category: { type: String, required: true, trim: true, index: true },
    subcategory: { type: String, required: true, trim: true, index: true },
    brand: { type: String, required: true, trim: true, maxlength: 100 },
    model: { type: String, trim: true, maxlength: 160, default: '' },
    normalizedBrand: { type: String, required: true, trim: true, index: true },
    normalizedModel: { type: String, trim: true, default: '', index: true },
    aliases: { type: [String], default: [] },
    source: { type: String, required: true, trim: true },
    description: { type: String, trim: true, maxlength: 500, default: '' },
    specifications: { type: mongoose.Schema.Types.Mixed, default: {} },
    lastSyncedAt: { type: Date, required: true, index: true },
  },
  { timestamps: true, strict: 'throw' },
);

productCatalogSchema.index(
  { source: 1, catalogEntityId: 1, entityType: 1, category: 1, subcategory: 1 },
  { unique: true, name: 'unique_catalog_entity_context' },
);
productCatalogSchema.index(
  { canonicalProductId: 1 },
  {
    sparse: true,
    name: 'canonical_product_lookup',
  },
);

export const ProductCatalogModel =
  mongoose.models.ProductCatalog ??
  mongoose.model('ProductCatalog', productCatalogSchema);
