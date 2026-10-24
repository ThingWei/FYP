import { fileURLToPath } from 'node:url';
import path from 'node:path';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { buildPriceCoverage, PRICE_COVERAGE_SCAN_LIMIT } from '../modules/listing/priceCoverage.js';
import { PRICE_SOURCES } from '../modules/listing/priceSources.registry.js';
import { writeNewExport } from './writeNewExport.js';

// Native MongoDB only: no Mongoose connection, schema initialization, index
// creation, provider requests, scheduler startup or changes to source approval.
const referenceProjection = Object.fromEntries([
  'category', 'subcategory', 'brand', 'productModel', 'canonicalProductId',
  'isbn', 'edition', 'variant', 'packageType', 'quotedAmount', 'rentalDurationDays',
  'dailyPrice', 'currency', 'country', 'sourceName', 'sourceUrl', 'observedAt',
  'active', 'sourceType', 'collectionMethod', 'sourceId', 'sourceProductKey',
  'productType', 'identityLevel', 'validationStatus', 'validatedAt',
  'durationMinDays', 'durationMaxDays', 'reviewedBy', 'reviewedAt', 'packageNotes',
  'condition', 'itemAgeYears', 'state',
].map((key) => [key, 1]));
const timestamp = (value) => value && Number.isFinite(+new Date(value)) ? new Date(value).toISOString() : null;

export async function readPriceCoverageAudit(db, {
  limit = PRICE_COVERAGE_SCAN_LIMIT, now = new Date(), approvedSourceIds = env.priceSyncApprovedSources,
} = {}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > PRICE_COVERAGE_SCAN_LIMIT) throw new Error('Limit must be 1–10000');
  if (!(now instanceof Date) || !Number.isFinite(+now)) throw new Error('Invalid audit time');
  if (!Array.isArray(approvedSourceIds) || approvedSourceIds.some((id) => typeof id !== 'string')) throw new Error('Invalid configured approvals');
  const [references, storedSources] = await Promise.all([
    db.collection('pricing_references').find({}, { projection: { _id: 0, ...referenceProjection } })
      .sort({ observedAt: -1 }).limit(limit + 1).maxTimeMS(10000).toArray(),
    db.collection('pricing_sources').find({ sourceId: { $in: PRICE_SOURCES.map((s) => s.id) } },
      { projection: { _id: 0, sourceId: 1, enabled: 1, lastSuccessAt: 1 } })
      .limit(PRICE_SOURCES.length + 1).maxTimeMS(10000).toArray(),
  ]);
  if (references.length > limit) throw new Error('Coverage limit exceeded; no partial audit written');
  if (new Set(storedSources.map((s) => s.sourceId)).size !== storedSources.length) throw new Error('Duplicate source configuration; audit unavailable');
  const sources = PRICE_SOURCES.map((source) => {
    const stored = storedSources.find((s) => s.sourceId === source.id);
    const configuredApproved = approvedSourceIds.includes(source.id);
    return { sourceId: source.id, name: source.name, adapterAvailable: Boolean(source.adapter), configuredApproved,
      enabled: Boolean(source.adapter && configuredApproved && stored?.enabled === true),
      collectionGate: !source.adapter ? 'adapter_unavailable' : !configuredApproved ? 'access_review_required'
        : stored?.enabled !== true ? 'disabled' : 'enabled',
      lastSuccessfulSyncAt: timestamp(stored?.lastSuccessAt) };
  });
  const coverage = buildPriceCoverage(references, sources.filter((s) => s.enabled).map((s) => s.sourceId), { now });
  const actions = coverage.rows.map((row) => {
    const candidates = sources.filter((source) => row.sourceIds.includes(source.sourceId));
    const missingProductTypes = Object.entries(row.productTypeCounts).filter(([, count]) => !count).map(([type]) => type);
    const nextAction = !row.eligibleObservations
      ? !candidates.length ? 'seek_permissioned_product_quotes'
        : candidates.some((s) => s.enabled) ? 'inspect_enabled_collection'
          : candidates.some((s) => s.adapterAvailable && s.configuredApproved) ? 'review_disabled_source'
            : candidates.some((s) => s.adapterAvailable) ? 'review_source_access' : 'find_usable_source'
      : missingProductTypes.length ? 'expand_product_type_evidence'
        : row.sourceWebsiteCount < 2 ? 'diversify_reference_sources' : 'evaluate_real_price_performance';
    return { category: row.category, subcategory: row.subcategory,
      priority: row.eligibleObservations ? 'existing_but_limited_evidence' : 'missing_evidence', nextAction,
      missingProductTypes, observationsWithoutCondition: row.eligibleObservations - row.withCondition,
      observationsWithoutItemAge: row.eligibleObservations - row.withItemAge,
      sourceGates: candidates.map(({ sourceId, collectionGate }) => ({ sourceId, collectionGate })) };
  });
  return { ...coverage, scanLimit: limit, databaseWrites: 0, sources, actions,
    totals: { eligibleObservations: coverage.rows.reduce((n, row) => n + row.eligibleObservations, 0),
      namedProductObservations: coverage.rows.reduce((n, row) => n + row.namedProductObservations, 0),
      specificationOnlyObservations: coverage.rows.reduce((n, row) => n + row.specificationOnlyObservations, 0),
      withCondition: coverage.rows.reduce((n, row) => n + row.withCondition, 0),
      withItemAge: coverage.rows.reduce((n, row) => n + row.withItemAge, 0) },
    limitations: [...coverage.limitations,
      'Configured approvals are not independently verified reuse rights. This audit does not fetch any source.',
      'Actions are collection/review tasks, not numerical accuracy or deployment thresholds.',
      'Platform asking prices, accepted bookings and completed rentals are not relabelled or counted here.'] };
}

export function parseAuditOptions(args) {
  let limit = PRICE_COVERAGE_SCAN_LIMIT, output;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--limit') {
      const value = args[++i];
      if (!/^\d+$/.test(value ?? '')) throw new Error('--limit requires a whole number');
      limit = Number(value);
    } else if (arg === '--output') {
      output = args[++i];
      if (!output || output.startsWith('-')) throw new Error('--output requires a new JSON path');
    } else throw new Error('Use [--limit 1–10000] [--output NEW_JSON_PATH]');
  }
  if (limit < 1 || limit > PRICE_COVERAGE_SCAN_LIMIT) throw new Error('Limit must be 1–10000');
  return { limit, output };
}

export async function main(args = process.argv.slice(2)) {
  const { limit, output } = parseAuditOptions(args);
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    const report = await readPriceCoverageAudit(client.db(), { limit });
    if (output) await writeNewExport(output, report);
    console.log(JSON.stringify(report, null, 2));
    return report;
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    console.error('Read-only price-coverage audit failed. Check configuration, bounds and any output path. No database writes were requested.');
    process.exitCode = 1;
  });
}
