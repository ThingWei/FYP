import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { buildRecommendationInteractions, modelInteraction } from '../modules/listing/recommendationInteractions.js';
import { writeNewExport } from './writeNewExport.js';

const countsBy = (rows, field) => rows.reduce((counts, row) => {
  const value = row[field] ?? 'unknown';
  counts[value] = (counts[value] ?? 0) + 1;
  return counts;
}, {});

export async function readRecommendationTrainingExport(db, { limit = 10000, now = new Date(), stagedUserIds = [], allStaged = false } = {}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100000) throw new Error('Limit must be 1-100000');
  if (!Array.isArray(stagedUserIds) || stagedUserIds.some((id) => typeof id !== 'string' || !id.trim())) {
    throw new Error('Staged users must be a private array of dedicated tester account IDs');
  }
  if (typeof allStaged !== 'boolean' || allStaged && stagedUserIds.length) throw new Error('Choose all-staged or individual staged users, not both');
  const read = async (name, query, projection) => {
    const rows = await db.collection(name).find(query, { projection }).sort({ _id: 1 }).limit(limit + 1).toArray();
    if (rows.length > limit) throw new Error('Export limit exceeded; no partial export written');
    return rows;
  };
  const [users, bookings, reviews, views, listings] = await Promise.all([
    read('users', { 'savedListingIds.0': { $exists: true } }, { authId: 1, savedListingIds: 1, createdAt: 1, updatedAt: 1 }),
    read('bookings', {}, { publicId: 1, renterId: 1, listingId: 1, status: 1, sourceType: 1,
      createdAt: 1, decidedAt: 1, completedAt: 1 }),
    read('reviews', { authorRole: 'renter', status: 'published' }, { bookingId: 1, authorId: 1,
      authorRole: 1, listingId: 1, overallRating: 1, status: 1, createdAt: 1, updatedAt: 1 }),
    read('listingviews', { expiresAt: { $gt: now } }, { userId: 1, listingId: 1, lastViewedAt: 1 }),
    read('listings', { sourceType: 'demo_seed' }, { publicId: 1, sourceType: 1 }),
  ]);
  const interactions = buildRecommendationInteractions({ users, bookings, reviews, views, listings,
    includeDemoSeed: true, stagedUserIds, allStaged });
  const eligible = interactions.filter((row) => row.observedAt > new Date(0) && row.observedAt <= now);
  const rows = eligible.map((row) => {
    const model = modelInteraction(row);
    if (!['marketplace', 'demo_seed', 'synthetic'].includes(model.source_type)) throw new Error('Unknown provenance');
    return { userId: model.user_id, listingId: model.item_id, interactionType: model.interaction_type,
      rating: model.rating, observedAt: model.observed_at, sourceType: model.source_type };
  });
  const activityClassification = allStaged ? 'all_platform_activity_staged_by_caller' : 'existing_markers_and_selected_staged_users';
  return { generatedAt: now.toISOString(), schemaVersion: 'renthub-recommendation-interactions-v1', rows, activityClassification,
    summary: { users: new Set(rows.map((r) => r.userId)).size, listings: new Set(rows.map((r) => r.listingId)).size,
      interactions: rows.length, sourceTypes: countsBy(rows, 'sourceType'), interactionTypes: countsBy(rows, 'interactionType'),
      excludedInvalidOrFutureTimes: interactions.length - eligible.length,
      stagedInteractions: rows.filter((r) => r.sourceType === 'demo_seed').length,
      activityClassification,
      limitations: ['Marketplace provenance is not independently verified commercial activity',
        'Dedicated staged accounts are labelled demo_seed in this export only; database history is unchanged',
        'Legacy staged activity cannot be identified automatically'] } };
}

export async function main(args = process.argv.slice(2)) {
  let output = '.data/recommendation_interactions.json', summaryOnly = false, limit = 10000, stagedFile, allStaged = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--summary-only') summaryOnly = true;
    else if (arg === '--all-staged') allStaged = true;
    else if (arg === '--limit') limit = Number(args[++i]);
    else if (arg === '--output') {
      output = args[++i];
      if (!output || output.startsWith('-')) throw new Error('--output requires a path');
    } else if (arg === '--staged-users') {
      stagedFile = args[++i];
      if (!stagedFile || stagedFile.startsWith('-')) throw new Error('--staged-users requires a JSON path');
    }
    else if (i === 0 && !arg.startsWith('-')) output = arg;
    else throw new Error('Use [output] [--summary-only] [--limit N] [--output PATH] [--all-staged | --staged-users JSON]');
  }
  if (!output) throw new Error('Output path required');
  if (allStaged && stagedFile) throw new Error('Choose --all-staged or --staged-users, not both');
  const stagedUserIds = stagedFile ? JSON.parse(await readFile(stagedFile, 'utf8')) : [];
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    const payload = await readRecommendationTrainingExport(client.db(), { limit, stagedUserIds, allStaged });
    if (!summaryOnly) await writeNewExport(output, payload);
    console.log(JSON.stringify({ ...payload.summary, databaseWrites: 0, fileWritten: !summaryOnly }));
    return payload.summary;
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Recommendation export failed; check input, limits and configuration. Existing files are not overwritten.'); process.exitCode = 1; });
}
