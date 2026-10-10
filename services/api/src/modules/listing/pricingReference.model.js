import mongoose from 'mongoose';

const schema = new mongoose.Schema({
  publicId: { type: String, required: true, unique: true },
  observationKey: { type: String, required: true, unique: true },
  sourceType: { type: String, enum: ['external_asking_price'], default: 'external_asking_price' },
  category: { type: String, required: true, index: true },
  subcategory: { type: String, required: true },
  brand: { type: String, required: true },
  productModel: { type: String, required: true },
  canonicalProductId: { type: String, default: null },
  quotedAmount: { type: Number, required: true },
  rentalDurationDays: { type: Number, required: true },
  dailyPrice: { type: Number, required: true },
  currency: { type: String, enum: ['MYR'], default: 'MYR' },
  country: { type: String, enum: ['MY'], default: 'MY' },
  sourceName: { type: String, required: true },
  sourceUrl: { type: String, required: true },
  observedAt: { type: Date, required: true },
  location: { type: String, default: '' },
  state: { type: String, default: '' },
  condition: { type: String, default: '' },
  itemAgeYears: { type: Number, default: null },
  packageNotes: { type: String, default: '' },
  active: { type: Boolean, default: true, index: true },
  reviewedBy: { type: String, required: true },
  reviewedAt: { type: Date, required: true },
  deactivatedBy: { type: String },
  deactivatedAt: { type: Date },
}, { timestamps: true, strict: 'throw', collection: 'pricing_references' });
schema.index({ category: 1, subcategory: 1, active: 1, observedAt: -1 });
export const PricingReferenceModel = mongoose.models.PricingReference ??
  mongoose.model('PricingReference', schema);
