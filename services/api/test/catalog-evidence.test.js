import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { buildEvidenceSuggestions } from '../src/modules/catalog/catalog.evidence.js';
import { catalogProvider } from '../src/modules/catalog/catalog.provider.js';
import { catalogService, resolveProductIdentity } from '../src/modules/catalog/catalog.service.js';
import { CATALOG_COVERAGE } from '../src/modules/catalog/catalog.coverage.js';
import { CURATED_CATALOG } from '../src/modules/catalog/catalog.curated.js';
import { ProductCatalogModel } from '../src/modules/catalog/productCatalog.model.js';
import { PricingReferenceModel } from '../src/modules/listing/pricingReference.model.js';
import { PriceSourceModel } from '../src/modules/listing/priceSource.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { nextPriceProvenance, listingEvidenceReason } from '../src/modules/listing/priceProvenance.js';
import { reviewedPrice } from './helpers/pricingEvidence.js';

const now = new Date('2026-10-28T04:00:00Z');
const input = { category: 'Devices', subcategory: 'Computers', entityType: 'product', brand: 'Evidence Maker', query: '', limit: 12 };
const quote = (extra = {}) => ({ category: input.category, subcategory: input.subcategory, productModel: 'Notebook laptop', brand: 'Evidence Maker',
  sourceType: 'external_asking_price', identityLevel: 'named_product', productType: 'laptop',
  active: true, currency: 'MYR', country: 'MY', quotedAmount: 100, rentalDurationDays: 1, dailyPrice: 100,
  sourceName: 'Reviewed fixture', sourceUrl: 'https://example.test/rental', observedAt: new Date('2026-10-27'),
  collectionMethod: 'manual_csv', reviewedBy: 'fixture-reviewer', reviewedAt: new Date('2026-10-27'),
  rateBasis: 'daily_rate', ...extra });
const build = (extra = {}) => buildEvidenceSuggestions({ input, now, ...extra });

test('evidence order, case normalization, IDs and package variants remain distinct without exposing prices', () => {
  const reference = quote({ productModel: 'Notebook laptop' });
  const cache = { ...input, brand: 'Evidence Maker', model: 'Notebook laptop', source: 'renthub-curated',
    canonicalProductId: 'fixture:real-product', canonicalBrandId: 'fixture:real-brand', specifications: { productType: 'laptop' } };
  const listing = reviewedPrice({ ...quote({ productModel: 'Second laptop' }), listingType: 'physical', status: 'active',
    sourceType: 'marketplace', updatedAt: new Date('2026-10-27') });
  const result = build({ references: [reference, quote({ productModel: 'NOTEBOOK laptop' }),
    quote({ variant: '512GB' }), quote({ variant: '256GB' }), quote({ packageType: 'equipment_set' })],
    listings: [listing], catalog: [cache] });
  assert.equal(result.items.length, 5);
  assert.equal(result.items[0].selectionSource, 'rental_reference');
  assert.equal(result.items.at(-1).selectionSource, 'marketplace_evidence');
  assert.equal(result.items[0].canonicalProductId, 'fixture:real-product');
  assert.equal(result.items.at(-1).canonicalProductId, null);
  assert.equal(new Set(result.items.map(r => r.displayKey)).size, 5);
  for (const row of result.items) for (const privateKey of ['dailyPrice', 'quotedAmount', 'reviewedBy', 'ownerId', 'priceProvenance']) assert.equal(row[privateKey], undefined);
  const aliasPage = build({ references: [reference, quote({ productModel: 'Notebook compact laptop' })],
    catalog: [{ ...cache, aliases: ['Notebook compact laptop'] }] });
  assert.equal(aliasPage.items.length, 1); // Recorded exact alias, not fuzzy text similarity.
  assert.equal(aliasPage.items[0].canonicalProductId, 'fixture:real-product');
});

test('unknown, demo, AI-derived and unreviewed listings and invalid references never provide suggestions', () => {
  const listing = reviewedPrice({ ...quote(), status: 'active', listingType: 'physical', sourceType: 'marketplace', updatedAt: now });
  const badListings = [{ ...listing, sourceType: 'demo_seed' }, { ...listing, priceProvenance: undefined },
    { ...listing, priceProvenance: { ...listing.priceProvenance, origin: 'ai_suggested' } },
    { ...listing, priceProvenance: { origin: 'owner_entered' } }, { ...listing, status: 'draft' }];
  const badRefs = [quote({ active: false }), quote({ observedAt: new Date('2024-01-01') }),
    quote({ reviewedBy: undefined }), quote({ identityLevel: 'specification_only' }), quote({ brand: 'Unknown' }),
    quote({ subcategory: 'Smartphones' }), quote({ productType: 'smartphone' }),
    quote({ quotedAmount: 1.001, dailyPrice: 1.001 }), quote({ packageNotes: 'Starting from RM1' })];
  assert.equal(build({ listings: badListings, references: badRefs }).items.length, 0);
  const selected = build({ references: [quote()] }).items[0];
  const futureListing = { ...listing, priceProvenance: nextPriceProvenance({ priceProvenance: { origin: 'owner_entered', independence: 'reviewed' },
    brand: selected.brand, productModel: selected.model }, { ...listing, priceProvenance: undefined }) };
  assert.equal(listingEvidenceReason(futureListing), 'unverified_owner_price');
});

test('Unicode identity, partial searches, brand isolation and pagination preserve meaningful model tokens', () => {
  const context = { ...input, brand: '製造社', query: 'モデル' };
  const refs = ['モデル 1', 'モデル 1 Pro', 'モデル 2'].map(productModel => quote({ brand: '製造社', productModel }));
  const result = build({ input: { ...context, limit: 2 }, references: [...refs, quote({ brand: '別会社', productModel: 'モデル 3' })] });
  assert.equal(result.items.length, 2); assert.equal(result.hasMore, true); assert.equal(result.nextLimit > 2, true);
  assert.equal(result.items.every(row => row.brand === '製造社'), true);
  assert.equal(new Set(result.items.map(row => row.model)).size, 2);
});

test('peripheral suggestions keep keyboards, mice, monitors and controllers in their product domains', () => {
  for (const [subcategory, model, type] of [['Computers', 'Office mouse', 'mouse'], ['Computers', 'Office keyboard', 'keyboard'],
    ['Computers', 'Office monitor', 'monitor'], ['Gaming', 'Game controller', 'controller']]) {
    const result = build({ input: { ...input, subcategory }, references: [quote({ subcategory, productModel: model, productType: type })] });
    assert.equal(result.items[0].specifications.productType, type);
  }
  const journal = { ...input, subcategory: 'Smartphones', entityType: 'brand', source: 'wikidata', brand: 'Applied Physics Letters', description: 'Physics journal' };
  assert.equal(build({ input: { ...input, subcategory: 'Smartphones', entityType: 'brand', query: 'appl' }, catalog: [journal] })
    .items.some(row => row.brand === journal.brand), false);
});

let mongo, originalSearch, originalApproved, providerCalls;
const owner = { 'x-user-id': 'evidence-owner', 'x-user-name': 'Evidence Owner', 'x-user-roles': 'owner' };
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  await Promise.all([ProductCatalogModel, PricingReferenceModel, PriceSourceModel, ListingModel, UserModel].map(m => m.init()));
  originalSearch = catalogProvider.search; originalApproved = env.priceSyncApprovedSources;
});
beforeEach(async () => {
  await Promise.all([ProductCatalogModel, PricingReferenceModel, PriceSourceModel, ListingModel, UserModel].map(m => m.deleteMany({})));
  providerCalls = 0; catalogProvider.search = async () => { providerCalls++; throw Error('Provider must not be used by evidence lookup'); };
  env.priceSyncApprovedSources = ['rentism'];
});
after(async () => { catalogProvider.search = originalSearch; env.priceSyncApprovedSources = originalApproved; await disconnectDatabase(); await mongo.stop(); });

test('evidence endpoints are owner-only, validate mode/query/context and make no catalogue writes or provider calls', async () => {
  const previousMode = env.authMode;
  try {
    env.authMode = 'local';
    await request(app).get('/api/v1/catalog/brands').query({ ...input, mode: 'evidence' }).expect(401);
  } finally { env.authMode = previousMode; }
  await request(app).get('/api/v1/catalog/brands').set({ ...owner, 'x-user-roles': 'admin' }).query({ ...input, mode: 'evidence' }).expect(403);
  for (const patch of [{ mode: 'bad' }, { query: 'x' }, { subcategory: 'Cars' }]) {
    await request(app).get('/api/v1/catalog/brands').set(owner).query({ ...input, mode: 'evidence', ...patch }).expect(422);
  }
  await request(app).get('/api/v1/catalog/brands?category=Devices&subcategory=Computers&mode=evidence&mode=evidence').set(owner).expect(422);
  for (const refresh of ['true', 'false']) {
    const response = await request(app).get('/api/v1/catalog/brands').set(owner)
      .query({ category: 'Devices', subcategory: 'Computers', mode: 'evidence', refresh, query: '' }).expect(200);
    assert.ok(response.body.data.length > 0); assert.equal(response.body.meta.refreshNeeded, false);
  }
  assert.equal(providerCalls, 0); assert.equal(await ProductCatalogModel.countDocuments(), 0);
  assert.equal(await ListingModel.countDocuments(), 0); assert.equal(await PricingReferenceModel.countDocuments(), 0);
});

test('source eligibility and deactivation are rechecked without stale cached evidence suggestions', async () => {
  await PriceSourceModel.create({ sourceId: 'rentism', enabled: true, status: 'ready' });
  await PricingReferenceModel.create(quote({ publicId: 'pr-evidence', observationKey: 'evidence', collectionMethod: 'automatic',
    sourceId: 'rentism', validationStatus: 'accepted', validatedAt: new Date('2026-10-27'), durationMinDays: 1, durationMaxDays: 1 }));
  const lookup = () => catalogService.models({ ...input, mode: 'evidence' });
  assert.equal((await lookup()).items[0].selectionSource, 'rental_reference');
  assert.equal((await lookup()).items[0].canonicalProductId, null);
  await PriceSourceModel.updateOne({ sourceId: 'rentism' }, { enabled: false });
  assert.equal((await lookup()).items.length, 0);
  await PriceSourceModel.updateOne({ sourceId: 'rentism' }, { enabled: true });
  await PricingReferenceModel.updateOne({}, { active: false });
  assert.equal((await lookup()).items.length, 0);
  assert.equal(providerCalls, 0); assert.equal(await ProductCatalogModel.countDocuments(), 0);
});

test('reviewed marketplace identities require an active Owner and remain separate from their private listing data', async () => {
  await UserModel.create({ authId: 'reviewed-owner', displayName: 'Fixture Owner', email: 'owner@example.test', roles: ['renter', 'owner'], activeRole: 'owner' });
  await ListingModel.create(reviewedPrice({ publicId: 'l-reviewed-evidence', ownerId: 'reviewed-owner', ownerName: 'Fixture Owner',
    title: 'Reviewed laptop', category: 'Devices', subcategory: 'Computers', brand: 'Evidence Maker', productModel: 'Notebook laptop',
    status: 'active', listingType: 'physical', dailyPrice: 100, condition: 'Good', fulfilmentMethods: ['pickup'], location: 'PRIVATE UNIT' }));
  const lookup = () => catalogService.models({ ...input, mode: 'evidence' });
  const first = await lookup();
  assert.equal(first.items[0].selectionSource, 'marketplace_evidence');
  assert.equal(first.items[0].ownerId, undefined); assert.equal(first.items[0].location, undefined);
  await UserModel.updateOne({ authId: 'reviewed-owner' }, { accountStatus: 'suspended' });
  assert.equal((await lookup()).items.length, 0);
});

for (const domain of CATALOG_COVERAGE) test(`local fallback provides a brand/model for ${domain.category} / ${domain.subcategory}`, async () => {
  const brandPage = await catalogService.brands({ ...domain, mode: 'evidence', query: '' });
  assert.ok(brandPage.items.length > 0);
  const example = CURATED_CATALOG.find(row => row.category === domain.category && row.subcategory === domain.subcategory && row.models.length);
  assert.ok(example);
  const modelPage = await catalogService.models({ ...domain, brand: example.brand, mode: 'evidence', query: '' });
  assert.ok(modelPage.items.some(row => row.model === example.models[0]));
  assert.equal(providerCalls, 0); assert.equal(await ProductCatalogModel.countDocuments(), 0);
});

test('Unicode canonical validation does not confuse unrelated non-Latin product identities', async () => {
  await ProductCatalogModel.create({ category: input.category, subcategory: input.subcategory, brand: '製造社', model: 'モデル一', entityType: 'product', source: 'renthub-curated',
    normalizedBrand: '製造社', normalizedModel: 'モデル一', catalogEntityId: 'fixture-unicode', canonicalProductId: 'fixture-unicode', lastSyncedAt: now });
  const valid = await resolveProductIdentity({ ...input, brand: '製造社', productModel: 'モデル一', canonicalProductId: 'fixture-unicode' });
  assert.equal(valid.canonicalProductId, 'fixture-unicode');
  const bad = await resolveProductIdentity({ ...input, brand: '別会社', productModel: '別製品', canonicalProductId: 'fixture-unicode' });
  assert.equal(bad.canonicalProductId, null);
});
