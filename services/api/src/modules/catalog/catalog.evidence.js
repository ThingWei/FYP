import { createHash } from 'node:crypto';
import { env } from '../../config/env.js';
import { ListingModel } from '../listing/listing.model.js';
import { PricingReferenceModel } from '../listing/pricingReference.model.js';
import { PriceSourceModel } from '../listing/priceSource.model.js';
import { UserModel } from '../user/user.model.js';
import { listingEvidenceReason } from '../listing/priceProvenance.js';
import { validRentalPrice, validPricePrecision } from '../listing/priceLimits.js';
import { eligibleTrainingReference } from '../listing/pricingTrainingExport.js';
import { productTypeFor, normalizeIsbn } from '../listing/priceProductDomains.js';
import { priceSource } from '../listing/priceSources.registry.js';
import { PRICING_EVIDENCE_WINDOW_DAYS } from '../listing/pricingEvidence.js';
import { searchCuratedCatalog } from './catalog.curated.js';
import { ProductCatalogModel } from './productCatalog.model.js';
import { catalogProvider, isValidWikidataFallback } from './catalog.provider.js';
import { catalogResultLimit, MAX_CATALOG_RESULTS } from './catalog.limits.js';

const SCAN_LIMIT = 1000;
const text = value => typeof value === 'string' ? value.trim() : '';
// Unicode-safe identity normalization; never strip model numbers or variant words.
export const evidenceIdentityText = value => text(value).normalize('NFKC').toLocaleLowerCase('en')
  .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().replace(/\s+/g, ' ');
const same = (a, b) => Boolean(evidenceIdentityText(a)) && evidenceIdentityText(a) === evidenceIdentityText(b);
const details = row => ({ variant: text(row.variant), edition: text(row.edition), isbn: text(row.isbn),
  packageType: text(row.packageType), includedLens: text(row.includedLens) });
const identity = (row, entityType) => JSON.stringify([evidenceIdentityText(row.brand),
  ...(entityType === 'brand' ? [] : [evidenceIdentityText(row.model),
    ...Object.values(details(row)).map(evidenceIdentityText)])]);
const inContext = (row, input) => row.category === input.category && row.subcategory === input.subcategory;
function namedProduct(row, input) {
  if (!inContext(row, input) || row.identityLevel === 'specification_only' || !text(row.brand) ||
      text(row.brand).length > 100 || /^(?:unknown|unbranded|n\/a|not specified|generic)$/i.test(text(row.brand)) ||
      !text(row.productModel) || text(row.productModel).length > 120) return false;
  if ([row.variant, row.edition, row.includedLens].some(value => text(value).length > 80) ||
      row.packageType && !['body_only', 'with_lens', 'item_only', 'equipment_set'].includes(row.packageType) ||
      row.isbn && (input.category !== 'Books' || !normalizeIsbn(row.isbn))) return false;
  const type = productTypeFor(row.category, row.subcategory, `${row.brand} ${row.productModel}`, row.productType);
  return Boolean(type && (!row.productType || row.productType === type));
}
function curatedRecord(item, input) {
  return { category: input.category, subcategory: input.subcategory, entityType: input.entityType,
    brand: input.entityType === 'brand' ? item.label : input.brand, model: input.entityType === 'brand' ? '' : item.label,
    aliases: item.aliases ?? [], source: item.source, specifications: item.specifications ?? {},
    canonicalProductId: null, canonicalBrandId: null, catalogEntityId: null };
}
function validCatalog(row, input, allowedSources) {
  if (!inContext(row, input) || row.entityType !== input.entityType || !allowedSources.includes(row.source)) return false;
  if (!text(row.brand) || text(row.brand).length > 100 ||
      (input.entityType === 'product' && (!text(row.model) || text(row.model).length > 120))) return false;
  return row.source !== 'wikidata' || isValidWikidataFallback({ label: input.entityType === 'brand' ? row.brand : row.model,
    description: row.description, aliases: row.aliases }, input);
}

// Pure, reusable merge. Eligibility is checked again on EVERY request, not cached
// as an identity record or inferred from client selection/source declarations.
export function buildEvidenceSuggestions({ input, references = [], listings = [], catalog = [],
  enabledSourceIds = [], now = new Date(), allowedSources = catalogProvider.sourcesFor(input) }) {
  const kind = input.entityType;
  const validCache = catalog.filter(row => validCatalog(row, input, allowedSources));
  const actualProduct = row => validCache.find(c => c.entityType === 'product' && c.canonicalProductId &&
    same(c.brand, row.brand) && [c.model, ...(c.aliases ?? [])].some(name => same(name, row.model)));
  const candidates = [];
  const addProduct = (row, selectionSource) => {
    if (!namedProduct(row, input)) return;
    candidates.push({ brand: text(row.brand), model: kind === 'brand' ? '' : text(row.productModel),
      ...details(row), selectionSource, specifications: { productType: productTypeFor(row.category, row.subcategory,
        `${row.brand} ${row.productModel}`, row.productType) }, canonicalProductId: null, canonicalBrandId: null });
  };
  for (const row of references) if (eligibleTrainingReference(row, enabledSourceIds, now)) addProduct(row, 'rental_reference');
  const since = +now - PRICING_EVIDENCE_WINDOW_DAYS * 86_400_000;
  for (const row of listings) if (row.status === 'active' && row.listingType === 'physical' &&
    validRentalPrice(row.dailyPrice, row.category) && validPricePrecision(row.dailyPrice) &&
    +new Date(row.updatedAt) >= since && +new Date(row.updatedAt) <= +now && !listingEvidenceReason(row)) addProduct(row, 'marketplace_evidence');
  for (const row of validCache) candidates.push({ ...row, selectionSource: 'catalogue' });
  for (const row of searchCuratedCatalog(input)) candidates.push({ ...curatedRecord(row, input), selectionSource: 'catalogue' });

  const query = evidenceIdentityText(input.query), kept = new Map();
  for (const row of candidates) {
    if (kind === 'product' && !same(row.brand, input.brand)) continue;
    const label = kind === 'brand' ? row.brand : row.model;
    if (!label || query && ![label, ...(row.aliases ?? []), ...(kind === 'brand' ? [] : Object.values(details(row)))].some(v => evidenceIdentityText(v).includes(query))) continue;
    const real = kind === 'product' ? actualProduct(row) : validCache.find(c => c.canonicalBrandId && same(c.brand, row.brand));
    const key = real?.canonicalProductId && kind === 'product'
      ? JSON.stringify([real.canonicalProductId, ...Object.values(details(row)).map(evidenceIdentityText)]) : identity(row, kind);
    if (kept.has(key)) continue; // Source order is intentional, not price/popularity ranking.
    const canonicalProductId = real?.canonicalProductId ?? null;
    const catalogBrandId = real?.canonicalBrandId ?? null;
    kept.set(key, { entityType: kind, brand: row.brand, model: kind === 'brand' ? '' : row.model,
      ...details(kind === 'brand' ? {} : row), selectionSource: row.selectionSource,
      displayKey: `suggestion-${createHash('sha256').update(JSON.stringify([input.category, input.subcategory, key])).digest('hex').slice(0, 24)}`,
      canonicalProductId, catalogBrandId, catalogEntityId: real?.catalogEntityId ?? null,
      catalogSource: real?.source ?? null, specifications: real?.specifications ?? row.specifications ?? {},
      queryMatch: same(label, input.query) ? 'exact' : 'fuzzy',
      description: row.selectionSource === 'rental_reference' ? 'Found in rental references'
        : row.selectionSource === 'marketplace_evidence' ? 'Found in reviewed marketplace evidence' : 'Catalogue suggestion' });
  }
  const limit = catalogResultLimit(input), rows = [...kept.values()];
  return { provider: 'renthub-evidence', providerAvailable: true, stale: false, refreshNeeded: false,
    mode: 'evidence', evidenceSuggestions: rows.filter(r => r.selectionSource !== 'catalogue').length,
    items: rows.slice(0, limit), limit, hasMore: rows.length > limit && limit < MAX_CATALOG_RESULTS,
    nextLimit: rows.length > limit && limit < MAX_CATALOG_RESULTS ? Math.min(limit + env.catalogMaxResults, MAX_CATALOG_RESULTS) : null,
    reachedLimit: limit === MAX_CATALOG_RESULTS && rows.length > limit };
}

export async function evidenceSuggestions(input) {
  const context = { category: input.category, subcategory: input.subcategory };
  const pattern = value => text(value).split(/[\s-]+/).map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('[\\s-]*');
  const scoped = modelField => ({
    ...(input.entityType === 'product' && { brand: new RegExp(`^\\s*${pattern(input.brand)}\\s*$`, 'i') }),
    ...(text(input.query) && { $or: (input.entityType === 'brand' ? ['brand', 'aliases'] : [modelField, 'aliases', 'variant', 'edition', 'isbn', 'includedLens'])
      .map(field => ({ [field]: new RegExp(pattern(input.query), 'i') })) }),
  });
  const since = new Date(Date.now() - PRICING_EVIDENCE_WINDOW_DAYS * 86_400_000);
  // Bounded read-only queries. No provider request, materialized identity cache,
  // catalogue upsert, pricing write, index creation or background refresh.
  const [references, listings, catalog, sources] = await Promise.all([
    PricingReferenceModel.find({ ...context, ...scoped('productModel'), active: true, observedAt: { $gte: since, $lte: new Date() } })
      .sort({ observedAt: -1, publicId: 1 }).limit(SCAN_LIMIT + 1).lean(),
    ListingModel.find({ ...context, ...scoped('productModel'), listingType: 'physical', status: 'active', sourceType: 'marketplace', updatedAt: { $gte: since } })
      .select('category subcategory brand productModel variant edition isbn packageType canonicalProductId dailyPrice priceProvenance condition itemAgeYears ownerId listingType status sourceType updatedAt publicId')
      .sort({ updatedAt: -1, publicId: 1 }).limit(SCAN_LIMIT + 1).lean(),
    ProductCatalogModel.find({ ...context, ...scoped('model'), entityType: input.entityType })
      .sort({ lastSyncedAt: -1, catalogEntityId: 1 }).limit(SCAN_LIMIT + 1).lean(),
    PriceSourceModel.find({ enabled: true }).select('sourceId').limit(100).lean(),
  ]);
  const owners = await UserModel.find({ authId: { $in: [...new Set(listings.map(r => r.ownerId))] }, accountStatus: 'active' }).select('authId').lean();
  const activeOwners = new Set(owners.map(row => row.authId));
  const result = buildEvidenceSuggestions({ input, references: references.slice(0, SCAN_LIMIT),
    listings: listings.slice(0, SCAN_LIMIT).filter(row => activeOwners.has(row.ownerId)), catalog: catalog.slice(0, SCAN_LIMIT),
    enabledSourceIds: sources.filter(row => priceSource(row.sourceId)?.adapter && env.priceSyncApprovedSources.includes(row.sourceId)).map(row => row.sourceId) });
  return { ...result, scanLimited: [references, listings, catalog].some(rows => rows.length > SCAN_LIMIT) };
}
