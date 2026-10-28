import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { buildMarketDemoDrafts, seedMarketDemoListings, parseDemoOptions } from '../src/scripts/seedMarketDemoListings.js';
import { listingEvidenceReason } from '../src/modules/listing/priceProvenance.js';

const manifest = JSON.parse(await readFile(new URL('../src/scripts/data/marketDemoListings.json', import.meta.url), 'utf8'));
const now = new Date('2026-10-27T12:00:00Z');
const owner = { authId: 'fixture-owner', displayName: 'Fixture Owner', email: 'fixture@example.test', roles: ['renter', 'owner'],
  accountStatus: 'active', verification: { documentType: 'mykad', status: 'approved' } };

test('market demo drafts contain sourced asking prices and leave unknown item details unfilled', async () => {
  const documents = await buildMarketDemoDrafts(owner, manifest, now);
  assert.equal(documents.length, 12);
  for (const document of documents) {
    assert.equal(document.status, 'draft');
    assert.equal(document.sourceType, 'demo_seed');
    assert.equal(document.verified, false);
    assert.equal(document.condition, undefined);
    assert.equal(document.itemAgeYears, undefined);
    assert.equal(document.coordinates, undefined);
    assert.equal(document.location, '');
    assert.deepEqual(document.images, []);
    assert.ok(document.description.includes('https://'));
    assert.equal(document.priceProvenance.origin, 'external_reference');
    assert.equal(document.priceProvenance.independence, 'unverified');
    assert.equal(listingEvidenceReason(document), 'demonstration');
  }
});

test('invalid account, invented metadata and ambiguous seed arguments are rejected', async () => {
  for (const change of [{ roles: ['renter'] }, { accountStatus: 'banned' }, { verification: {} }]) {
    await assert.rejects(buildMarketDemoDrafts({ ...owner, ...change }, manifest, now));
  }
  const invalid = structuredClone(manifest);
  invalid.records[0].condition = 'Excellent';
  await assert.rejects(buildMarketDemoDrafts(owner, invalid, now));
  for (const args of [[], ['--owner-email'], ['--owner-email', owner.email, '--output', '../outside.json'],
    ['--owner-email', owner.email, '--apply', '--apply']]) assert.throws(() => parseDemoOptions(args));
  assert.equal(parseDemoOptions(['--owner-email', owner.email]).apply, false);
});

test('native seed is draft-only, idempotent, preserves edits and never creates transaction history', async () => {
  const server = await MongoMemoryServer.create();
  const client = new mongoose.mongo.MongoClient(server.getUri());
  try {
    await client.connect();
    const db = client.db('demo-fixture');
    await db.collection('users').insertOne(owner);
    await db.collection('listings').createIndex({ publicId: 1 }, { unique: true });
    await db.collection('bookings').insertOne({ publicId: 'existing-test-booking' });
    const before = await db.collection('users').findOne({ authId: owner.authId });
    const preview = await seedMarketDemoListings(db, { ownerEmail: owner.email, manifest, now });
    assert.equal(preview.created, 0);
    assert.equal(await db.collection('listings').countDocuments(), 0);
    const applied = await seedMarketDemoListings(db, { ownerEmail: owner.email, manifest, now, apply: true });
    assert.equal(applied.created, 12);
    const id = applied.drafts[0].publicId;
    await db.collection('listings').updateOne({ publicId: id }, { $set: { description: 'Owner edited this draft' } });
    const repeated = await seedMarketDemoListings(db, { ownerEmail: owner.email, manifest, now, apply: true });
    assert.equal(repeated.created, 0);
    assert.equal(repeated.alreadyPresent, 12);
    assert.equal(await db.collection('listings').countDocuments({ status: 'draft', sourceType: 'demo_seed' }), 12);
    assert.equal((await db.collection('listings').findOne({ publicId: id })).description, 'Owner edited this draft');
    assert.equal(await db.collection('bookings').countDocuments(), 1);
    assert.equal(await db.collection('payments').countDocuments(), 0);
    assert.deepEqual(await db.collection('users').findOne({ authId: owner.authId }), before);
    assert.equal(JSON.stringify(applied).includes(owner.email), false);
    assert.equal(JSON.stringify(applied).includes(owner.authId), false);
  } finally { await client.close(); await server.stop(); }
});
