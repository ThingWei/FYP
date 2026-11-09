import { fileURLToPath } from 'node:url';
import path from 'node:path';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { readPriceCoverageAudit } from './auditPriceCoverage.js';
import { writeNewExport } from './writeNewExport.js';
import { PRICE_PRODUCT_DOMAINS } from '../modules/listing/priceProductDomains.js';
import { listingEvidenceReason, bookingEvidenceReason } from '../modules/listing/priceProvenance.js';
import { demonstrationBookingReason } from '../modules/listing/pricingRecovery.js';

// Aggregate-only, read-only. This is coverage, not independently measured accuracy.
export function pricingReadinessSummary(coverage, listings, bookings, payments, now = new Date()) {
  const exclusions = {};
  const completed = bookings.filter((b) => b.listingType === 'physical' && b.status === 'completed');
  for (const b of completed) {
    const reason = demonstrationBookingReason(b, payments, now);
    if (reason) exclusions[reason] = (exclusions[reason] ?? 0) + 1;
  }
  const rows = PRICE_PRODUCT_DOMAINS.map((domain) => {
    const same = (r) => r?.category === domain.category && r.subcategory === domain.subcategory;
    const references = coverage.rows.find(same);
    const active = listings.filter((r) => r.status === 'active' && r.listingType === 'physical' && same(r));
    return { category: domain.category, subcategory: domain.subcategory,
      eligibleExternalObservations: references?.eligibleObservations ?? 0,
      productTypeCounts: references?.productTypeCounts ?? {},
      missingReferenceTypes: Object.entries(references?.productTypeCounts ?? {}).filter(([, n]) => n === 0).map(([key]) => key),
      activeListings: active.length,
      cleanActiveListings: active.filter((r) => !listingEvidenceReason(r)).length,
      cleanCompletedRentals: completed.filter((b) => same(b.pricingEvidenceSnapshot) && !bookingEvidenceReason(b, payments)).length,
      eligibleSimulatedCompletedRentals: completed.filter((b) => same(b.pricingEvidenceSnapshot) && !demonstrationBookingReason(b, payments, now)).length,
      limitation: 'Category counts do not guarantee a compatible model, package or rental period.' };
  });
  return { schemaVersion: 'renthub-pricing-readiness-v1', generatedAt: now.toISOString(), databaseWrites: 0,
    rows, completedPhysicalRecords: completed.length,
    completedWithoutSnapshots: completed.filter((b) => !b.pricingEvidenceSnapshot).length,
    demonstrationExclusions: exclusions,
    limitations: ['Simulated completed rentals remain separate from independently verified payments and clean training exports.',
      'No records, source settings or deployed models were changed. No historical snapshot was reconstructed.'] };
}

export async function readPricingReadiness(db, now = new Date()) {
  const read = async (name, query, fields) => {
    const rows = await db.collection(name).find(query, { projection: { _id: 0,
      ...Object.fromEntries(fields.map((k) => [k, 1])) } }).limit(10001).maxTimeMS(10000).toArray();
    if (rows.length > 10000) throw new Error('Audit bound exceeded');
    return rows;
  };
  const [coverage, listings, bookings, payments] = await Promise.all([
    readPriceCoverageAudit(db, { now }),
    read('listings', { listingType: 'physical' }, ['listingType', 'status', 'sourceType', 'category', 'subcategory',
      'brand', 'productModel', 'canonicalProductId', 'condition', 'itemAgeYears', 'isbn', 'edition', 'variant', 'packageType', 'dailyPrice', 'state', 'priceProvenance']),
    read('bookings', { listingType: 'physical', status: 'completed', completedAt: { $gte: new Date(+now - 365 * 86400000), $lte: now } },
      ['publicId', 'listingType', 'status', 'sourceType', 'pricingEvidenceSnapshot', 'pricing.baseAmount', 'completedAt', 'paymentStatus']),
    read('payments', { type: { $in: ['authorization', 'capture'] } },
      ['bookingId', 'type', 'status', 'amount', 'currency', 'createdAt', 'simulated', 'gatewayReference']),
  ]);
  return pricingReadinessSummary(coverage, listings, bookings, payments, now);
}

export async function main(args = process.argv.slice(2)) {
  if (args.length && (args.length !== 2 || args[0] !== '--output' || !args[1] || args[1].startsWith('-'))) throw new Error('Use [--output NEW_JSON_PATH]');
  const c = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await c.connect();
    const summary = await readPricingReadiness(c.db());
    if (args[1]) await writeNewExport(args[1], summary);
    console.log(JSON.stringify(summary, null, 2));
    return summary;
  } finally { await c.close(); }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Pricing readiness audit could not complete. No database writes were requested.'); process.exitCode = 1; });
}
