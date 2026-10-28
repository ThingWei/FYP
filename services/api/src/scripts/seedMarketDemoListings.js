// Opt-in local draft seeding. Native writes affect only new demo listing records.
import { createHash } from 'node:crypto';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { ListingModel } from '../modules/listing/listing.model.js';
import { CATALOG_COVERAGE } from '../modules/catalog/catalog.coverage.js';
import { priceSource, isAllowedSourceUrl } from '../modules/listing/priceSources.registry.js';
import { referenceOfferKey } from '../modules/listing/priceProductDomains.js';
import { validRentalPrice, validPricePrecision } from '../modules/listing/priceLimits.js';
import { hasApprovedMykad } from '../modules/user/drivingEligibility.js';
import { writeNewExport } from './writeNewExport.js';

const hash = (value) => createHash('sha256').update(value).digest('hex').slice(0, 16);
const defaultManifest = fileURLToPath(new URL('data/marketDemoListings.json', import.meta.url));
const privateRoot = fileURLToPath(new URL('../../.data', import.meta.url));

export function parseDemoOptions(args) {
  let ownerEmail, output, apply = false;
  for (let i = 0; i < args.length; i++) {
    const option = args[i];
    if (option === '--apply' && !apply) { apply = true; continue; }
    if (!['--owner-email', '--output'].includes(option)) throw new Error('Use --owner-email EMAIL [--output NEW_PRIVATE_JSON] [--apply]');
    const value = args[++i];
    if (!value || value.startsWith('-')) throw new Error('Missing option value');
    if (option === '--owner-email') { if (ownerEmail) throw new Error('Duplicate owner option'); ownerEmail = value.trim().toLowerCase(); }
    else { if (output) throw new Error('Duplicate output option'); output = path.resolve(value); }
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail ?? '')) throw new Error('An explicit Owner email is required');
  if (output && !output.startsWith(path.resolve(privateRoot) + path.sep)) throw new Error('Output must stay under services/api/.data');
  return { ownerEmail, output, apply };
}

export async function buildMarketDemoDrafts(owner, manifest, now = new Date()) {
  if (!owner || !owner.roles?.includes('owner') || owner.accountStatus !== 'active' || !hasApprovedMykad(owner)) {
    throw new Error('The selected account must be an active, MyKad-approved Owner');
  }
  if (manifest.purpose !== 'source_based_demo_drafts_not_marketplace_transactions' ||
      !Array.isArray(manifest.records) || !manifest.records.length || manifest.records.length > 30) throw new Error('Invalid bounded demo manifest');
  const observed = new Date(manifest.observedDate + 'T00:00:00Z');
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }).format(now);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(manifest.observedDate ?? '') || !Number.isFinite(+observed) ||
      observed.toISOString().slice(0, 10) !== manifest.observedDate || manifest.observedDate > today) throw new Error('Invalid observation date');
  const slugs = new Set(), documents = [];
  const allowed = new Set(['slug', 'category', 'subcategory', 'brand', 'model', 'amount', 'sourceId', 'packageType', 'notes']);
  for (const row of manifest.records) {
    if (Object.keys(row).some((key) => !allowed.has(key)) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(row.slug ?? '') || slugs.has(row.slug)) throw new Error('Invalid/duplicate demo record');
    slugs.add(row.slug);
    const source = manifest.sources?.[row.sourceId], entry = priceSource(row.sourceId);
    if (!source || !entry || !isAllowedSourceUrl(entry, source.url) || !entry.domains.includes(row.subcategory) ||
        !CATALOG_COVERAGE.some((domain) => domain.category === row.category && domain.subcategory === row.subcategory) ||
        !validRentalPrice(row.amount, row.category) || !validPricePrecision(row.amount)) throw new Error('Invalid source/domain/rate');
    for (const field of ['brand', 'model', 'notes']) {
      if (typeof row[field] !== 'string' || !row[field].trim() || row[field].length > (field === 'notes' ? 500 : 100)) throw new Error('Missing product/reference details');
    }
    const offerKey = referenceOfferKey({ sourceUrl: source.url, brand: row.brand, productModel: row.model, packageType: row.packageType });
    const document = new ListingModel({
      publicId: `l-demo-market-${hash(owner.authId)}-${hash(row.slug)}`,
      ownerId: owner.authId, ownerName: owner.displayName,
      title: `[Demo] ${row.brand} ${row.model}`, category: row.category, subcategory: row.subcategory,
      brand: row.brand, productModel: row.model, packageType: row.packageType,
      description: `Demonstration draft based on an advertised asking price, not a completed rental.\n` +
        `Reference: ${source.name}; ${source.url}; checked ${manifest.observedDate}. RM ${row.amount.toFixed(2)} for one day.\n` +
        `${row.notes}\n` +
        `Owner has not confirmed this item's possession, condition, age, pickup point, photos or charges. Complete these from your actual item before submitting.`,
      listingType: 'physical', sourceType: 'demo_seed', status: 'draft', dailyPrice: row.amount,
      priceProvenance: { origin: 'external_reference', independence: 'unverified', originatingOfferKey: offerKey, recordedAt: now },
      verified: false, images: [], location: '', state: '', fulfilmentMethods: [],
      createdAt: now, updatedAt: now,
    });
    await document.validate(); // Schema validation without connecting Mongoose or creating indexes.
    documents.push(document.toObject());
  }
  return documents;
}

export async function seedMarketDemoListings(db, { ownerEmail, manifest, apply = false, now = new Date() }) {
  const matches = await db.collection('users').find({ email: ownerEmail }, { projection: {
    authId: 1, displayName: 1, roles: 1, accountStatus: 1, 'verification.documentType': 1,
    'verification.status': 1, 'verification.documents.documentType': 1, 'verification.documents.status': 1,
  } }).limit(2).toArray();
  if (matches.length !== 1) throw new Error('Exactly one existing Owner account must match');
  const documents = await buildMarketDemoDrafts(matches[0], manifest, now);
  const collection = db.collection('listings');
  const previous = await collection.find({ publicId: { $in: documents.map((document) => document.publicId) } },
    { projection: { publicId: 1, ownerId: 1, sourceType: 1 } }).limit(31).toArray();
  if (previous.some((row) => row.ownerId !== matches[0].authId || row.sourceType !== 'demo_seed')) throw new Error('Existing listing identifier conflict; nothing overwritten');
  let created = 0;
  if (apply) {
    const indexes = await collection.listIndexes().toArray();
    if (!indexes.some((index) => index.unique && index.key?.publicId === 1 &&
        Object.keys(index.key).length === 1 && !index.sparse && !index.partialFilterExpression)) {
      throw new Error('Existing unique listing identifier index is required; no indexes will be created by this script');
    }
    const result = await collection.bulkWrite(documents.map((document) => ({ updateOne: {
      filter: { publicId: document.publicId, ownerId: document.ownerId, sourceType: 'demo_seed' },
      update: { $setOnInsert: document }, upsert: true,
    } })), { ordered: true });
    if (result.modifiedCount !== 0) throw new Error('Unexpected modification of existing documents');
    created = result.upsertedCount;
  }
  return { mode: apply ? 'applied' : 'preview_only', plannedDrafts: documents.length, created,
    alreadyPresent: previous.length, sourceType: 'demo_seed', cleanPricingEvidence: false,
    bookingsCreated: 0, paymentsCreated: 0, drafts: documents.map(({ ownerId, ownerName, _id, ...document }) => document) };
}

export async function main(args = process.argv.slice(2)) {
  const options = parseDemoOptions(args);
  if (env.nodeEnv === 'production') throw new Error('Demo draft seeding is disabled in production');
  if (options.output) {
    try { await access(options.output); throw new Error('Output exists'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const manifest = JSON.parse(await readFile(defaultManifest, 'utf8'));
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    const result = await seedMarketDemoListings(client.db(), { ...options, manifest });
    if (options.output) await writeNewExport(options.output, result);
    const { drafts, ...summary } = result;
    console.log(JSON.stringify(summary));
    return result;
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Demo draft preparation failed. Check the selected account, source manifest and new private output path. No account, booking or payment changes requested.'); process.exitCode = 1; });
}
