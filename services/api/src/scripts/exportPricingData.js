import { fileURLToPath } from 'node:url';
import path from 'node:path';
import mongoose from 'mongoose';
import { readFile } from 'node:fs/promises';
import { env } from '../config/env.js';
import { PRICE_SOURCES } from '../modules/listing/priceSources.registry.js';
import { buildPricingTrainingExport } from '../modules/listing/pricingTrainingExport.js';
import { writeNewExport } from './writeNewExport.js';

export async function readPricingTrainingExport(db, { limit = 10000, now = new Date(), stagedUserIds = [], allStaged = false } = {}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100000) throw new Error('Limit must be 1–100000');
  if (!Array.isArray(stagedUserIds) || stagedUserIds.some((id) => typeof id !== 'string' || !id.trim())) throw new Error('Invalid staged users');
  if (typeof allStaged !== 'boolean' || allStaged && stagedUserIds.length) throw new Error('Choose all-staged or individual staged users, not both');
  const read = async (collection, query, projection) => {
    const rows = await db.collection(collection).find(query, { projection }).sort({ _id: 1 }).limit(limit + 1).toArray();
    if (rows.length > limit) throw new Error('Export limit exceeded; no partial export written. Increase --limit deliberately.');
    return rows;
  };
  const [listings, bookings, reviews, references, sources] = await Promise.all([
    read('listings', { listingType: 'physical' }, { publicId: 1, ownerId: 1, title: 1, listingType: 1,
      category: 1, subcategory: 1, brand: 1, productModel: 1, canonicalProductId: 1, condition: 1,
      isbn: 1, edition: 1, variant: 1, packageType: 1,
      itemAgeYears: 1, 'locationDetails.city': 1, state: 1, dailyPrice: 1, status: 1, sourceType: 1, createdAt: 1, updatedAt: 1 }),
    read('bookings', { listingType: 'physical', status: { $in: ['completed', 'active', 'approved'] } },
      { listingId: 1, renterId: 1, status: 1, startDate: 1, endDate: 1, 'pricing.baseAmount': 1, paymentStatus: 1,
        completedAt: 1, decidedAt: 1, sourceType: 1, createdAt: 1 }),
    read('reviews', { subjectRole: 'owner', status: 'published' }, { subjectId: 1, overallRating: 1, createdAt: 1 }),
    read('pricing_references', { active: true }, { publicId: 1, observationKey: 1, sourceType: 1,
      category: 1, subcategory: 1, brand: 1, productModel: 1, canonicalProductId: 1, condition: 1, itemAgeYears: 1,
      isbn: 1, edition: 1, variant: 1, packageType: 1,
      state: 1, quotedAmount: 1, rentalDurationDays: 1, dailyPrice: 1, currency: 1, country: 1, sourceName: 1,
      sourceUrl: 1, observedAt: 1, createdAt: 1, packageNotes: 1, active: 1, collectionMethod: 1, sourceId: 1,
      sourceProductKey: 1, productType: 1, identityLevel: 1, validationStatus: 1, validatedAt: 1,
      durationMinDays: 1, durationMaxDays: 1, reviewedAt: 1, reviewedBy: 1 }),
    read('pricing_sources', { enabled: true }, { sourceId: 1 }),
  ]);
  const approved = new Set(PRICE_SOURCES.filter((s) => s.adapter && env.priceSyncApprovedSources.includes(s.id)).map((s) => s.id));
  const staged = new Set(stagedUserIds);
  const payload = buildPricingTrainingExport({
    listings: listings.map((row) => allStaged || staged.has(row.ownerId) ? { ...row, sourceType: 'demo_seed' } : row),
    bookings: bookings.map((row) => allStaged || staged.has(row.renterId) ? { ...row, sourceType: 'demo_seed' } : row),
    reviews, references, now,
    enabledSourceIds: sources.filter((s) => approved.has(s.sourceId)).map((s) => s.sourceId) });
  payload.activityClassification = allStaged ? 'all_platform_activity_staged_by_caller' : 'existing_markers_and_selected_staged_users';
  payload.summary.activityClassification = payload.activityClassification;
  return payload;
}

export async function main(args = process.argv.slice(2)) {
  let output = '.data/pricing_observations.json', summaryOnly = false, limit = 10000, stagedFile, allStaged = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--summary-only') summaryOnly = true;
    else if (arg === '--all-staged') allStaged = true;
    else if (arg === '--limit' || arg.startsWith('--limit=')) limit = Number(arg.includes('=') ? arg.split('=')[1] : args[++i]);
    else if (arg === '--output') {
      output = args[++i];
      if (!output || output.startsWith('-')) throw new Error('--output requires a path');
    } else if (arg === '--staged-users') {
      stagedFile = args[++i];
      if (!stagedFile || stagedFile.startsWith('-')) throw new Error('--staged-users requires a JSON path');
    }
    else if (!arg.startsWith('-') && i === 0) output = arg; // Existing positional path remains supported.
    else throw new Error('Use [output-path] [--summary-only] [--limit N] [--all-staged | --staged-users JSON] or --output PATH');
  }
  if (!output) throw new Error('An output path is required');
  if (allStaged && stagedFile) throw new Error('Choose --all-staged or --staged-users, not both');
  const stagedUserIds = stagedFile ? JSON.parse(await readFile(stagedFile, 'utf8')) : [];
  // Native read-only queries: importing this script never initializes Mongoose
  // schemas/indexes or collections, unlike connecting exported model classes.
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    const payload = await readPricingTrainingExport(client.db(), { limit, stagedUserIds, allStaged });
    if (!summaryOnly) {
      await writeNewExport(output, payload);
    }
    console.log(JSON.stringify({ ...payload.summary, databaseWrites: 0, fileWritten: !summaryOnly }));
    return payload.summary;
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Pricing export failed; check configuration, limits and source validity. No database writes were requested.'); process.exitCode = 1; });
}
