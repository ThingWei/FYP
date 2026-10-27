// Native bounded reads only. Shares the clean export policy; never starts jobs.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { normalizeCatalogText } from '../modules/catalog/catalog.service.js';
import { readPricingTrainingExport } from './exportPricingData.js';
import { referencePeriodMatches } from '../modules/listing/priceProductDomains.js';
import { PRICING_EVIDENCE_WINDOW_DAYS, selectComparableTier, evidenceCounts,
  robustPriceStats } from '../modules/listing/pricingEvidence.js';

export function summarizePricingEvidence(payload, profile, now = new Date()) {
  const since = +now - PRICING_EVIDENCE_WINDOW_DAYS * 86400000;
  const eligible = payload.rows.filter((row) => {
    const at = +new Date(row.observed_at);
    const known = +new Date(row.available_at || (row.source_type !== 'external_asking_price' ? row.observed_at : undefined));
    const origin = row.source_type === 'real' && row.price_origin === 'owner_entered' && row.payment_simulated !== true ||
      row.source_type === 'external_asking_price' && row.price_origin === 'external_reference';
    return origin && row.independent_evidence === true && row.category === profile.category &&
      Number.isFinite(at) && Number.isFinite(known) && at >= since && at <= +now && known <= +now &&
      Number.isFinite(row.daily_price) && row.daily_price > 0;
  }).map((row) => ({ ...row, productModel: row.product_model, productType: row.product_type,
    identityLevel: row.identity_level, itemAgeYears: row.item_age_years, dailyPrice: row.daily_price,
    rentalDurationDays: row.rental_duration_days, durationMinDays: row.duration_min_days,
    durationMaxDays: row.duration_max_days }));
  const completed = eligible.filter((row) => row.source_type === 'real' && row.target_source === 'completed_rental');
  const completedCounts = evidenceCounts(completed, profile);
  const summary = (items) => {
    const tier = selectComparableTier(items, profile);
    return { selectedTier: tier.name, candidateCounts: evidenceCounts(items, profile),
      selectedCounts: evidenceCounts(tier.items, profile), selectedCount: tier.items.length,
      selectedMedian: robustPriceStats(tier.items.map((item) => item.dailyPrice)).median,
      selectedMarketplaceCount: tier.items.filter((item) => item.source_type === 'real').length,
      selectedDemoSeedCount: 0 };
  };
  return { category: profile.category, subcategory: profile.subcategory, brand: profile.brand, model: profile.product_model,
    canonicalIdentityCached: Boolean(profile.canonicalProductId), evidenceWindowDays: PRICING_EVIDENCE_WINDOW_DAYS,
    demoSeedIncludedByConfiguration: false, eligibleCompletedMarketplace: completedCounts.exact + completedCounts.similar,
    eligibleCompletedDemoSeed: 0,
    active: summary(eligible.filter((row) => row.source_type === 'real' && row.target_source === 'active_asking')),
    historical: summary(completed),
    externalAsking: summary(eligible.filter((row) => row.target_source === 'external_asking_price' &&
      referencePeriodMatches(row, profile.rental_duration_days ?? 1))),
    excludedPlatform: payload.summary.excludedPlatform ?? {}, databaseWrites: 0,
    caveat: 'Only clean evidence is counted. External asking prices are not achieved rental prices; missing age/condition remain unknown.' };
}

export async function main(args = process.argv.slice(2)) {
  const [category, subcategory, brand, product_model] = args;
  if (args.length !== 4 || !args.every((arg) => typeof arg === 'string' && arg.trim())) {
    throw new Error('Usage: node src/scripts/auditPricingEvidence.js category subcategory brand model');
  }
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000, monitorCommands: true });
  const commands = new Set();
  client.on('commandStarted', (event) => commands.add(event.commandName));
  try {
    await client.connect();
    const db = client.db(), now = new Date();
    const catalog = await db.collection('productcatalogs').find({ category, subcategory,
      normalizedBrand: normalizeCatalogText(brand), normalizedModel: normalizeCatalogText(product_model) },
    { projection: { canonicalProductId: 1 } }).sort({ lastSyncedAt: -1 }).limit(1).toArray();
    const payload = await readPricingTrainingExport(db, { now });
    const result = summarizePricingEvidence(payload, { category, subcategory, brand, product_model,
      canonicalProductId: catalog[0]?.canonicalProductId, rental_duration_days: 1 }, now);
    if ([...commands].some((command) => !['find', 'getMore', 'killCursors', 'ping'].includes(command))) {
      throw new Error('Unexpected database command');
    }
    console.log(JSON.stringify({ ...result, databaseCommands: [...commands].sort() }, null, 2));
    return result;
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Read-only product audit failed; check arguments/configuration. No database writes requested.'); process.exitCode = 1; });
}
