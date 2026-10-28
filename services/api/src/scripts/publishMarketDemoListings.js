// Explicit local demo publication only. Never approves/changes genuine listings.
import { createHash } from 'node:crypto';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { storageAdapter } from '../integrations/storageAdapter.js';
import { ListingModel } from '../modules/listing/listing.model.js';
import { UploadAssetModel } from '../modules/upload/upload.model.js';
import { approximatePoint } from '../core/location.js';
import { nextPriceProvenance } from '../modules/listing/priceProvenance.js';
import { buildMarketDemoDrafts, parseDemoOptions } from './seedMarketDemoListings.js';
import { writeNewExport } from './writeNewExport.js';

const apiRoot = fileURLToPath(new URL('../..', import.meta.url));
const digest = (value) => createHash('sha256').update(value).digest('hex');

export async function planDemoPublication(db, { ownerEmail, manifest, presentation, imageDirectory, now = new Date() }) {
  const owner = await db.collection('users').findOne({ email: ownerEmail }, { projection: {
    authId: 1, displayName: 1, roles: 1, accountStatus: 1, 'verification.documentType': 1,
    'verification.status': 1, 'verification.documents.documentType': 1, 'verification.documents.status': 1,
  } });
  const expected = await buildMarketDemoDrafts(owner, manifest, now);
  if (presentation.purpose !== 'fictional_demo_presentation_not_observed_item_facts') throw new Error('Explicit demo presentation required');
  const existing = await db.collection('listings').find({ publicId: { $in: expected.map((d) => d.publicId) } }).limit(31).toArray();
  if (existing.length !== expected.length) throw new Error('All selected demo drafts must already exist');
  const point = presentation.meetingPoint;
  const coordinates = { latitude: point.latitude, longitude: point.longitude };
  const plans = [];
  for (const [index, row] of manifest.records.entries()) {
    const current = existing.find((d) => d.publicId === expected[index].publicId);
    const example = presentation.items?.[row.slug];
    if (!example || current.ownerId !== owner.authId || current.sourceType !== 'demo_seed' || !current.title.startsWith('[Demo]') ||
        current.category !== row.category || current.subcategory !== row.subcategory || current.brand !== row.brand || current.productModel !== row.model) {
      throw new Error('Only the selected unchanged-identity demo records can be completed');
    }
    const buffer = await readFile(path.join(imageDirectory, row.slug + '.png'));
    if (!buffer.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || buffer.length > 10_485_760) throw new Error('Valid bounded PNG illustration required');
    const sha256 = digest(buffer), publicId = 'UPL-' + digest(owner.authId + ':' + row.slug + ':' + sha256).slice(0, 32).toUpperCase();
    const reference = 'upload://' + publicId;
    if (current.status === 'active' && current.images?.[0] === reference && current.description.includes('DEMO LISTING')) {
      plans.push({ current, alreadyPublished: true }); continue;
    }
    if (current.status !== 'draft' || current.images?.length) throw new Error('Draft was changed/submitted or already has images; no automatic overwrite');
    const source = manifest.sources[row.sourceId];
    const fields = { status: 'active', title: '[Demo] ' + row.brand + ' ' + row.model,
      description: 'DEMO LISTING — illustrative image and example details; no physical item is offered.\n\n' + example.summary +
        `\nExample condition: ${example.condition}. Example item age: ${example.age} year(s). Deposit and delivery charges are example amounts for testing.\n` +
        `Demo pickup: ${point.label}, ${point.city}. This is a public demonstration meeting point, not the Owner's address.\n\n` +
        `Daily asking-price reference: ${source.name}, RM ${row.amount.toFixed(2)} for one day, checked ${manifest.observedDate}. ${row.notes}\n${source.url}`,
      condition: example.condition, itemAgeYears: example.age, dailyPrice: row.amount,
      securityDeposit: example.deposit, deliveryFee: example.delivery, priceUnit: 'day',
      fulfilmentMethods: ['pickup', 'owner_delivery'], damageWaiverAvailable: false, damageWaiverFee: 0,
      location: point.label + ', ' + point.city, state: point.state, coordinates,
      locationDetails: { coordinates, displayAddress: point.label + ', ' + point.city,
        addressLine1: point.label, city: point.city, state: point.state, postcode: '', source: 'map' },
      publicGeoPoint: approximatePoint(coordinates), images: [reference], verified: false, rating: 0, reviewCount: 0,
      requiredLicenceClass: row.category === 'Vehicles' ? 'D' : '',
      moderationReason: 'Published as labelled demonstration data at the account holder’s request; no item verification performed.',
      updatedAt: now,
    };
    fields.priceProvenance = nextPriceProvenance(fields, current, now);
    const validated = new ListingModel({ ...current, ...fields });
    await validated.validate();
    const storagePath = `public/demo-market/${digest(owner.authId).slice(0, 16)}/${publicId}.png`;
    const asset = { publicId, uploadedBy: owner.authId, purpose: 'listing_image', visibility: 'public',
      originalName: 'demo-' + row.slug + '.png', contentType: 'image/png', size: buffer.length,
      storagePath, sha256, storageProvider: env.storageMode === 'supabase' ? 'supabase' : env.storageMode === 'firebase' ? 'firebase' : 'local',
      createdAt: now, updatedAt: now };
    await new UploadAssetModel(asset).validate();
    const previousAsset = await db.collection(UploadAssetModel.collection.name).findOne({ publicId });
    if (previousAsset && (previousAsset.uploadedBy !== owner.authId || previousAsset.sha256 !== sha256 ||
        previousAsset.purpose !== 'listing_image' || previousAsset.visibility !== 'public' || previousAsset.storagePath !== storagePath)) throw new Error('Upload identity conflict');
    plans.push({ current, fields, asset, buffer, existingAsset: Boolean(previousAsset), alreadyPublished: false });
  }
  return plans;
}

export async function applyDemoPublication(db, plans, { storage = storageAdapter } = {}) {
  let published = 0, imagesCreated = 0;
  // Every listing/image is prevalidated before any publication. Failed runs can be retried.
  for (const plan of plans) {
    if (plan.alreadyPublished) continue;
    if (!plan.existingAsset) {
      try {
        const uploaded = await storage.upload({ storagePath: plan.asset.storagePath, buffer: plan.buffer, contentType: 'image/png', isPublic: true });
        if (uploaded.provider !== plan.asset.storageProvider) throw new Error('Storage provider mismatch');
      } catch (error) {
        // Recover only a byte-identical upload left by a prior interrupted run.
        const old = await storage.download(plan.asset.storagePath).catch(() => null);
        if (!old || digest(old) !== plan.asset.sha256) throw error;
      }
      await db.collection(UploadAssetModel.collection.name).updateOne({ publicId: plan.asset.publicId }, { $setOnInsert: plan.asset }, { upsert: true });
      imagesCreated++;
    }
    const loaded = await storage.download(plan.asset.storagePath);
    if (digest(loaded) !== plan.asset.sha256) throw new Error('Stored image did not verify');
    const saved = await db.collection('listings').updateOne({ _id: plan.current._id, ownerId: plan.current.ownerId,
      sourceType: 'demo_seed', status: 'draft', updatedAt: plan.current.updatedAt },
    { $set: plan.fields, $unset: { itemVerification: '', priceRecommendation: '' } });
    if (saved.modifiedCount !== 1) throw new Error('Draft changed during publication; inspect before retrying');
    published++;
  }
  return { published, alreadyPublished: plans.filter((p) => p.alreadyPublished).length, imagesCreated,
    sourceType: 'demo_seed', cleanPricingEvidence: false, itemVerificationGranted: false, bookingsCreated: 0, paymentsCreated: 0 };
}

export async function main(args = process.argv.slice(2)) {
  const options = parseDemoOptions(args);
  if (env.nodeEnv === 'production') throw new Error('Demo publication is disabled in production');
  if (options.apply && !options.output) throw new Error('A new private receipt path is required');
  if (options.output) {
    for (const file of [options.output, options.output + '.result.json']) {
      try { await access(file); throw new Error('Output exists'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
  }
  const manifest = JSON.parse(await readFile(new URL('data/marketDemoListings.json', import.meta.url), 'utf8'));
  const presentation = JSON.parse(await readFile(new URL('data/marketDemoPresentation.json', import.meta.url), 'utf8'));
  const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    const plans = await planDemoPublication(client.db(), { ownerEmail: options.ownerEmail, manifest, presentation,
      imageDirectory: path.join(apiRoot, '.data/demo-market-images-v1') });
    const backup = plans.map((p) => ({ publicId: p.current.publicId, status: p.current.status, alreadyPublished: p.alreadyPublished,
      proposed: p.fields }));
    if (options.output) await writeNewExport(options.output, { mode: 'preview', listings: backup });
    const summary = options.apply ? await applyDemoPublication(client.db(), plans) : { planned: plans.length, published: 0, mode: 'preview_only' };
    if (options.output && options.apply) await writeNewExport(options.output + '.result.json', summary);
    console.log(JSON.stringify(summary));
    return summary;
  } finally { await client.close(); }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Labelled demo publication did not complete. Inspect the private receipt and storage before retrying. No genuine listing approvals, account changes or transactions requested.'); process.exitCode = 1; });
}
