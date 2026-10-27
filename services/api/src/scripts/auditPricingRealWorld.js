// Native bounded reads only. No model initialization, indexes, jobs or provider requests.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readFile, access } from 'node:fs/promises';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { PRICE_SOURCES } from '../modules/listing/priceSources.registry.js';
import { buildPriceCoverage } from '../modules/listing/priceCoverage.js';
import { eligibleTrainingReference } from '../modules/listing/pricingTrainingExport.js';
import { referenceOfferKey } from '../modules/listing/priceProductDomains.js';
import { readPricingTrainingExport } from './exportPricingData.js';
import { writeNewExport } from './writeNewExport.js';

const validReview = (r, now) => r.status === 'approved' && r.sourceId &&
    r.reviewedBy && r.checkedAt && Number.isFinite(+new Date(r.checkedAt)) && new Date(r.checkedAt) <= now &&
    typeof r.evidenceReference === 'string' && r.evidenceReference.trim();
export function reviewPreview(references, enabledIds, reuseReviews = [], now = new Date()) {
  const approved = new Set(reuseReviews.filter((r) => validReview(r, now)).map((r) => r.sourceId));
  const valid = references.filter((row) => eligibleTrainingReference(row, enabledIds, now));
  const unique = new Map();
  for (const row of valid) {
    if (!approved.has(row.sourceId || new URL(row.sourceUrl).hostname)) continue;
    const key = row.originatingOfferKey || referenceOfferKey(row);
    if (unique.has(key)) continue;
    unique.set(key, { category: row.category, subcategory: row.subcategory,
      productName: [row.brand, row.productModel].filter(Boolean).join(' '),
      brand: row.brand || null, model: row.productModel, productType: row.productType || null,
      quotedAmount: row.quotedAmount, rentalDurationDays: row.rentalDurationDays,
      durationMinDays: row.durationMinDays ?? row.rentalDurationDays,
      durationMaxDays: row.durationMaxDays ?? row.rentalDurationDays,
      dailyEquivalent: row.dailyPrice, currency: row.currency, sourceName: row.sourceName,
      sourceUrl: row.sourceUrl, observedAt: row.observedAt, collectionDate: now.toISOString(),
      condition: row.condition || null, itemAgeYears: row.itemAgeYears ?? null,
      packageNotes: row.packageNotes || '', originatingOfferKey: key,
      priceProvenance: 'external_asking_price', demonstrationClassification: 'observation_not_listing_or_transaction' });
  }
  // Prefer sparse domains rather than producing another camera-heavy demo file.
  const counts = valid.reduce((a, r) => { a[r.subcategory] = (a[r.subcategory] || 0) + 1; return a; }, {});
  const rows = [...unique.values()].sort((a, b) => counts[a.subcategory] - counts[b.subcategory] ||
    a.productName.localeCompare(b.productName)).slice(0, 100);
  return { purpose: 'review_only_external_observations_not_live_listings', databaseWrites: 0,
    rows, requestedMaximum: 100, shortfall: 100 - rows.length,
    blockedPendingReuseReview: valid.filter((r) => !approved.has(r.sourceId || new URL(r.sourceUrl).hostname)).length,
    caveat: 'Existing source enablement/CSV review does not independently establish reuse permission. No source was fetched or enabled.' };
}

export async function auditDatabase(db, now = new Date(), reuseReviews = []) {
  const read = async (name, projection) => {
    const rows = await db.collection(name).find({}, { projection }).limit(10001).toArray();
    if (rows.length > 10000) throw new Error('Audit bound exceeded; no partial report');
    return rows;
  };
  const [listings, bookings, references, sources, payments] = await Promise.all([
    read('listings', { listingType: 1, status: 1, sourceType: 1, priceProvenance: 1 }),
    read('bookings', { publicId: 1, status: 1, sourceType: 1, pricingEvidenceSnapshot: 1 }),
    read('pricing_references', { }), read('pricing_sources', { sourceId: 1, enabled: 1, status: 1, accessCheckedAt: 1 }),
    read('payments', { bookingId: 1, simulated: 1 }),
  ]);
  const approved = new Set(PRICE_SOURCES.filter((s) => s.adapter && env.priceSyncApprovedSources.includes(s.id)).map((s) => s.id));
  const enabled = sources.filter((s) => s.enabled && approved.has(s.sourceId)).map((s) => s.sourceId);
  const coverage = buildPriceCoverage(references, enabled, { now });
  const physical = listings.filter((r) => r.listingType === 'physical');
  const completed = bookings.filter((r) => r.status === 'completed');
  const summary = { auditDate: now.toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }), generatedAt: now.toISOString(), databaseWrites: 0,
    listings: { physical: physical.length, activePhysical: physical.filter((r) => r.status === 'active').length,
      unknownPriceOrigin: physical.filter((r) => !r.priceProvenance || r.priceProvenance.origin === 'unknown').length },
    bookings: { total: bookings.length, completed: completed.length,
      completedWithSimulatedPayment: completed.filter((b) => payments.some((p) => p.bookingId === b.publicId && p.simulated === true)).length,
      completedWithoutPaymentEvidence: completed.filter((b) => !payments.some((p) => p.bookingId === b.publicId)).length },
    paymentRecords: payments.length, simulatedPaymentRecords: payments.filter((p) => p.simulated === true).length,
    coverage,
    sourceReviews: PRICE_SOURCES.map((s) => ({ sourceId: s.id, adapterAvailable: Boolean(s.adapter),
      configuredApproval: approved.has(s.id), enabled: enabled.includes(s.id),
      reusePermissionIndependentlyVerified: reuseReviews.some((r) => r.sourceId === s.id && validReview(r, now)),
      limitation: s.limitation })),
  };
  const observations = await readPricingTrainingExport(db, { now });
  observations.reuseClearance = 'stored_data_diagnostic_not_independently_verified_by_this_audit';
  return { summary, observations, preview: reviewPreview(references, enabled, reuseReviews, now) };
}

export async function main(args = process.argv.slice(2)) {
  const output = args[args.indexOf('--output') + 1];
  if (!args.includes('--output') || !output || output.startsWith('-')) throw new Error('--output requires a new private .data directory');
  const root = path.resolve(fileURLToPath(new URL('../../.data', import.meta.url)));
  const destination = path.resolve(output);
  if (!destination.startsWith(root + path.sep)) throw new Error('Output must stay under services/api/.data');
  try { await access(destination); throw new Error('Output already exists'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const index = args.indexOf('--reuse-reviews');
  const reviews = index < 0 ? [] : JSON.parse(await readFile(args[index + 1], 'utf8'));
  if (!Array.isArray(reviews)) throw new Error('Reuse reviews must be an explicit array');
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000, monitorCommands: true });
  const commands = new Set(); client.on('commandStarted', (event) => commands.add(event.commandName));
  try {
    await client.connect();
    const result = await auditDatabase(client.db(), new Date(), reviews);
    result.summary.databaseCommands = [...commands].sort();
    if ([...commands].some((c) => !['find', 'getMore', 'aggregate', 'killCursors', 'ping'].includes(c))) throw new Error('Unexpected database command');
    for (const [name, payload] of Object.entries(result)) await writeNewExport(path.join(destination, name + '.json'), payload);
    console.log(JSON.stringify({ databaseWrites: 0, previewRows: result.preview.rows.length,
      observations: result.observations.rows.length, subcategories: result.summary.coverage.categoriesWithReferences }));
  } finally { await client.close(); }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Read-only pricing audit failed; check bounds, input and private output. No database writes requested.'); process.exitCode = 1; });
}
