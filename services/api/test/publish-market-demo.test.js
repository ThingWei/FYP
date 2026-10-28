import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { seedMarketDemoListings } from '../src/scripts/seedMarketDemoListings.js';
import { planDemoPublication, applyDemoPublication } from '../src/scripts/publishMarketDemoListings.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { listingEvidenceReason } from '../src/modules/listing/priceProvenance.js';
import { buildRecommendationInteractions } from '../src/modules/listing/recommendationInteractions.js';
import { readRecommendationTrainingExport } from '../src/scripts/exportRecommendationData.js';

const manifest = JSON.parse(await readFile(new URL('../src/scripts/data/marketDemoListings.json', import.meta.url), 'utf8'));
const presentation = JSON.parse(await readFile(new URL('../src/scripts/data/marketDemoPresentation.json', import.meta.url), 'utf8'));
const now = new Date('2026-10-27T12:00:00Z');
const owner = { authId: 'demo-fixture-owner', email: 'demo-fixture@example.test', displayName: 'Demo Fixture',
  roles: ['renter', 'owner'], accountStatus: 'active', verification: { documentType: 'mykad', status: 'approved' } };
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');

test('labelled demo publication fills presentation, owns its images and preserves evidence/privacy rules', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'demo-publication-'));
  const server = await MongoMemoryServer.create();
  const client = new mongoose.mongo.MongoClient(server.getUri());
  const files = new Map();
  const storage = { upload: async ({ storagePath, buffer }) => { files.set(storagePath, buffer); return { provider: 'local' }; },
    download: async (key) => files.get(key) };
  try {
    await client.connect(); const db = client.db('demo-publication');
    await db.collection('users').insertOne(owner);
    await db.collection('listings').createIndex({ publicId: 1 }, { unique: true });
    await db.collection(UploadAssetModel.collection.name).createIndex({ publicId: 1 }, { unique: true });
    for (const row of manifest.records) await writeFile(path.join(root, row.slug + '.png'), png);
    await seedMarketDemoListings(db, { ownerEmail: owner.email, manifest, now, apply: true });
    const options = { ownerEmail: owner.email, manifest, presentation, imageDirectory: root, now };
    const preview = await planDemoPublication(db, options);
    assert.equal(preview.length, 12);
    assert.equal(await db.collection('listings').countDocuments({ status: 'active' }), 0);
    assert.equal(await db.collection(UploadAssetModel.collection.name).countDocuments(), 0);
    const result = await applyDemoPublication(db, preview, { storage });
    assert.equal(result.published, 12);
    assert.equal(result.imagesCreated, 12);
    assert.equal(result.itemVerificationGranted, false);
    const saved = await db.collection('listings').find({}).toArray();
    for (const item of saved) {
      assert.equal(item.status, 'active');
      assert.equal(item.sourceType, 'demo_seed');
      assert.equal(item.verified, false);
      assert.equal(item.reviewCount, 0);
      assert.ok(item.condition && item.itemAgeYears >= 0);
      assert.ok(item.description.includes('DEMO LISTING'));
      assert.ok(item.description.includes('Example condition'));
      assert.equal(item.images.length, 1);
      assert.equal(listingEvidenceReason(item), 'demonstration');
      const publicItem = new ListingModel(item).toJSON();
      assert.notEqual(publicItem.coordinates.latitude, item.coordinates.latitude);
      assert.equal(publicItem.locationDetails, undefined);
      const asset = await db.collection(UploadAssetModel.collection.name).findOne({ publicId: item.images[0].slice(9) });
      assert.equal(asset.uploadedBy, owner.authId);
      assert.equal(asset.visibility, 'public');
      assert.equal(asset.purpose, 'listing_image');
    }
    const again = await applyDemoPublication(db, await planDemoPublication(db, options), { storage });
    assert.equal(again.published, 0);
    assert.equal(again.alreadyPublished, 12);
    assert.equal(files.size, 12);
    assert.equal(await db.collection('bookings').countDocuments(), 0);
    assert.equal(await db.collection('payments').countDocuments(), 0);
    assert.equal((await db.collection('users').findOne({ email: owner.email })).accountStatus, 'active');
    // Classification uses listing provenance even for a legacy view without a source marker.
    await db.collection('listingviews').insertOne({ userId: 'tester', listingId: saved[0].publicId, lastViewedAt: now, expiresAt: new Date(+now + 86400000) });
    const exported = await readRecommendationTrainingExport(db, { now });
    assert.equal(exported.rows[0].sourceType, 'demo_seed');
  } finally { await client.close(); await server.stop(); await rm(root, { recursive: true, force: true }); }
});

test('all interactions with demo listings stay staged, including saves and published feedback', () => {
  const input = { listings: [{ publicId: 'demo', sourceType: 'demo_seed' }],
    views: [{ userId: 'u', listingId: 'demo', lastViewedAt: now }],
    users: [{ authId: 'u', savedListingIds: ['demo'], updatedAt: now }],
    bookings: [{ publicId: 'b', renterId: 'u', listingId: 'demo', sourceType: 'marketplace', status: 'completed', completedAt: now }],
    reviews: [{ bookingId: 'b', authorId: 'u', authorRole: 'renter', listingId: 'demo', status: 'published', overallRating: 5, createdAt: now }] };
  assert.deepEqual(buildRecommendationInteractions(input), []);
  const staged = buildRecommendationInteractions({ ...input, includeDemoSeed: true });
  assert.equal(staged.length, 1);
  assert.equal(staged[0].sourceType, 'demo_seed');
  assert.equal(staged[0].interactionType, 'published_review');
});
