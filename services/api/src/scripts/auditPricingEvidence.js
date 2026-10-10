// Read-only aggregate inspection. No provider calls, seeds or database writes.
import mongoose from 'mongoose';
import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { env } from '../config/env.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { ListingModel } from '../modules/listing/listing.model.js';
import { ProductCatalogModel } from '../modules/catalog/productCatalog.model.js';
import { normalizeCatalogText } from '../modules/catalog/catalog.service.js';
import { PRICING_COMPLETED_PAYMENT_STATUSES, PRICING_EVIDENCE_WINDOW_DAYS,
  PRICING_EVIDENCE_QUERY_LIMIT, selectComparableTier, evidenceCounts,
  robustPriceStats } from '../modules/listing/pricingEvidence.js';

mongoose.set('autoIndex', false);
mongoose.set('autoCreate', false);
const [category, subcategory, brand, product_model] = process.argv.slice(2);
if (![category, subcategory, brand, product_model].every(Boolean)) {
  console.error('Usage: node src/scripts/auditPricingEvidence.js category subcategory brand model');
  process.exitCode = 1;
} else {
  try {
    await connectDatabase();
    const catalog = await ProductCatalogModel.findOne({ category, subcategory,
      normalizedBrand: normalizeCatalogText(brand), normalizedModel: normalizeCatalogText(product_model) })
      .sort({ lastSyncedAt: -1 }).select('canonicalProductId').lean();
    const profile = { category, subcategory, brand, product_model,
      canonicalProductId: catalog?.canonicalProductId,
      condition: 'Excellent', location: 'Kuala Lumpur', state: 'Kuala Lumpur',
      item_age_years: 1, rental_duration_days: 1 };
    const listings = await ListingModel.find({ category, listingType: 'physical' })
      .select('publicId status subcategory brand productModel canonicalProductId condition itemAgeYears location state dailyPrice updatedAt sourceType')
      .sort({ updatedAt: -1 }).lean();
    const byId = new Map(listings.map(item => [item.publicId, item]));
    const since = new Date(Date.now() - PRICING_EVIDENCE_WINDOW_DAYS * 86400000);
    const bookings = await BookingModel.find({ listingType: 'physical', status: 'completed',
      paymentStatus: { $in: PRICING_COMPLETED_PAYMENT_STATUSES }, 'pricing.baseAmount': { $gt: 0 },
      $or: [{ completedAt: { $gte: since } }, { completedAt: { $exists: false }, createdAt: { $gte: since } }] })
      .select('listingId startDate endDate pricing.baseAmount completedAt sourceType')
      .sort({ completedAt: -1 }).limit(PRICING_EVIDENCE_QUERY_LIMIT).lean();
    const eligible = bookings.flatMap(booking => {
      const listing = byId.get(booking.listingId);
      if (!listing) return [];
      const days = Math.max(1, Math.floor((new Date(booking.endDate) - new Date(booking.startDate)) / 86400000) + 1);
      return [{ ...listing, dailyPrice: booking.pricing.baseAmount / days,
        observedAt: booking.completedAt, sourceType: booking.sourceType ?? 'marketplace' }];
    });
    const active = listings.filter(item => item.status === 'active').slice(0, PRICING_EVIDENCE_QUERY_LIMIT);
    const historical = eligible.filter(item => env.pricingIncludeDemoSeed || item.sourceType !== 'demo_seed');
    function summary(items) {
      const tier = selectComparableTier(items, profile);
      return { selectedTier: tier.name, candidateCounts: evidenceCounts(items, profile),
        selectedCounts: evidenceCounts(tier.items, profile), selectedCount: tier.items.length,
        selectedMedian: robustPriceStats(tier.items.map(item => item.dailyPrice)).median,
        selectedMarketplaceCount: tier.items.filter(item => item.sourceType !== 'demo_seed').length,
        selectedDemoSeedCount: tier.items.filter(item => item.sourceType === 'demo_seed').length };
    }
    console.log(JSON.stringify({ category, subcategory, brand, model: product_model,
      canonicalIdentityCached: Boolean(catalog?.canonicalProductId),
      evidenceWindowDays: PRICING_EVIDENCE_WINDOW_DAYS,
      demoSeedIncludedByConfiguration: env.pricingIncludeDemoSeed,
      eligibleCompletedMarketplace: eligible.filter(item => item.sourceType !== 'demo_seed').length,
      eligibleCompletedDemoSeed: eligible.filter(item => item.sourceType === 'demo_seed').length,
      active: summary(active), historical: summary(historical),
      caveat: 'Marketplace is a provenance label, not independent proof of a genuine transaction. Active prices are asking prices.' }, null, 2));
  } catch (error) {
    console.error(JSON.stringify({ available: false, errorType: error.name,
      reason: 'Read-only database audit could not complete; no database contents changed.' }));
    process.exitCode = 1;
  } finally { await disconnectDatabase(); }
}
