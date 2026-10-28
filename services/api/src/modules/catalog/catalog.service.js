import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { catalogProvider, isValidWikidataFallback } from './catalog.provider.js';
import { searchCuratedCatalog } from './catalog.curated.js';
import { ProductCatalogModel, PRODUCT_MATCH_TYPES } from './productCatalog.model.js';
import { catalogResultLimit, MAX_CATALOG_RESULTS, CATALOG_LOOKAHEAD_LIMIT } from './catalog.limits.js';
import { evidenceSuggestions } from './catalog.evidence.js';

const refreshes = new Map();
const updateIntervalMs = Math.min(env.catalogCacheTtlHours, 24) * 3_600_000;
const retryDelayMs = 60_000;

function queryKey(input) {
  return JSON.stringify([input.entityType, input.category, input.subcategory,
    normalizeCatalogText(input.brand), input.catalogBrandId ?? '', normalizeCatalogText(input.query),
    catalogResultLimit(input)]);
}

async function refreshProvider(input, key) {
  const prior = refreshes.get(key);
  if (prior?.pending) return prior.pending;
  const state = { ...prior };
  const pending = Promise.resolve().then(async () => {
    try {
      const result = await catalogProvider.search(input);
      const items = Array.isArray(result) ? result : result.items;
      if (!Array.isArray(items)) throw new Error('Invalid catalogue response');
      const stored = await storeProviderItems(input, items.slice(0, CATALOG_LOOKAHEAD_LIMIT));
      const available = result.providerAvailable !== false;
      if (available) state.successAt = Date.now();
      else state.failedAt = Date.now();
      return { stored, available, provider: Array.isArray(result) ? catalogProvider.strategy(input) : result.provider };
    } catch (error) {
      state.failedAt = Date.now();
      throw error;
    } finally { state.pending = null; }
  });
  state.pending = pending;
  refreshes.delete(key);
  refreshes.set(key, state);
  if (refreshes.size > 256) refreshes.delete(refreshes.keys().next().value);
  return pending;
}

export function normalizeCatalogText(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function compactCatalogText(value) {
  return normalizeCatalogText(value).replaceAll(' ', '');
}

function matchesCatalogText(value, candidates) {
  const normalized = normalizeCatalogText(value);
  const compact = compactCatalogText(value);
  return candidates.filter(Boolean).some((candidate) =>
    normalizeCatalogText(candidate) === normalized ||
    compactCatalogText(candidate) === compact);
}

function escapedPattern(value) {
  return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

function publicItem(record, query) {
  const label = record.entityType === 'brand' ? record.brand : record.model;
  return {
    entityType: record.entityType,
    brand: record.brand,
    model: record.model,
    canonicalProductId: record.canonicalProductId,
    catalogBrandId: record.canonicalBrandId,
    catalogEntityId: record.catalogEntityId,
    catalogSource: record.source,
    description: record.description,
    specifications: record.specifications ?? {},
    queryMatch: matchesCatalogText(query, [label, ...(record.aliases ?? [])])
      ? 'exact'
      : 'fuzzy',
  };
}

function cacheFilter({
  entityType,
  category,
  subcategory,
  brand,
  query,
  freshOnly,
  primaryOnly,
}) {
  const sources = catalogProvider.sourcesFor({ category, subcategory });
  const normalizedQuery = normalizeCatalogText(query);
  const filter = {
    entityType,
    category,
    subcategory,
    source: { $in: primaryOnly ? sources.slice(0, 1) : sources },
    ...(freshOnly && {
      lastSyncedAt: {
        $gte: new Date(Date.now() - env.catalogCacheTtlHours * 3_600_000),
      },
    }),
  };
  if (brand) filter.normalizedBrand = normalizeCatalogText(brand);
  if (normalizedQuery) {
    filter[entityType === 'brand' ? 'normalizedBrand' : 'normalizedModel'] =
      escapedPattern(normalizedQuery);
  }
  return filter;
}

async function cached(input, freshOnly, primaryOnly = false) {
  return ProductCatalogModel.find(cacheFilter({
    ...input,
    freshOnly,
    primaryOnly,
  }))
    .sort({ lastSyncedAt: -1, catalogEntityId: 1 })
    .limit(CATALOG_LOOKAHEAD_LIMIT)
    .lean();
}

export function mergeCatalogRecords(records, input) {
  const kept = [];
  const browseLabels = new Set(searchCuratedCatalog(input).map((item) => compactCatalogText(item.label)));
  for (const record of records) {
    const label = input.entityType === 'brand' ? record.brand : record.model;
    if (record.source === 'wikidata' && !isValidWikidataFallback({
      label, description: record.description, aliases: record.aliases,
    }, input)) continue;
    const identityText = (value) => {
      const normalized = normalizeCatalogText(value), brand = normalizeCatalogText(input.brand);
      return compactCatalogText(input.entityType !== 'brand' && normalized.startsWith(`${brand} `)
        ? normalized.slice(brand.length + 1) : normalized);
    };
    const names = [label, ...(record.aliases ?? [])].map(identityText).filter(Boolean);
    if (!kept.some((item) => [input.entityType === 'brand' ? item.brand : item.model,
      ...(item.aliases ?? [])].map(identityText).some((name) => names.includes(name)))) {
      kept.push(record);
    }
  }
  return kept.sort((a, b) => {
    const left = input.entityType === 'brand' ? a.brand : a.model;
    const right = input.entityType === 'brand' ? b.brand : b.model;
    return (!normalizeCatalogText(input.query) ? Number(browseLabels.has(compactCatalogText(right))) -
      Number(browseLabels.has(compactCatalogText(left))) : 0) ||
      Number(matchesCatalogText(input.query, [right])) -
      Number(matchesCatalogText(input.query, [left])) || left.localeCompare(right);
  }).slice(0, catalogResultLimit(input));
}

async function storeProviderItems(input, items) {
  const stored = [];
  for (const item of items) {
    const entityId = `${item.source}:${item.id}`;
    const isBrand = input.entityType === 'brand';
    const brand = isBrand ? item.label : input.brand;
    const model = isBrand ? '' : item.label;
    const canonicalBrandId = isBrand
      ? entityId
      : item.brandId
        ? `${item.source}:${item.brandId}`
        : input.catalogBrandId ?? null;
    const canonicalProductId = isBrand ? null : entityId;
    const record = await ProductCatalogModel.findOneAndUpdate(
      {
        source: item.source,
        catalogEntityId: entityId,
        entityType: input.entityType,
        category: input.category,
        subcategory: input.subcategory,
      },
      {
        $set: {
          canonicalProductId,
          canonicalBrandId,
          brand,
          model,
          normalizedBrand: normalizeCatalogText(brand),
          normalizedModel: normalizeCatalogText(model),
          aliases: [...new Set([item.label, ...(item.aliases ?? [])])],
          description: item.description,
          specifications: item.specifications ?? {},
          lastSyncedAt: new Date(),
        },
        $setOnInsert: {
          source: item.source,
          catalogEntityId: entityId,
          entityType: input.entityType,
          category: input.category,
          subcategory: input.subcategory,
        },
      },
      { upsert: true, new: true, lean: true },
    );
    stored.push(record);
  }
  return stored;
}

async function search(input) {
  if (input.mode === 'evidence') return evidenceSuggestions(input);
  const limit = Math.min(catalogResultLimit(input), MAX_CATALOG_RESULTS);
  const lookup = { ...input, limit: limit + 1 };
  const key = queryKey(lookup);
  const state = refreshes.get(key);
  const force = input.refresh === true || input.refresh === 'true';
  const preferCache = input.preferCache === true || input.preferCache === 'true';
  const fresh = await cached(input, true, true);
  const saved = await cached(input, false);
  const curated = await storeProviderItems(input, searchCuratedCatalog(input));
  const knownFresh = fresh.length > 0 && state?.successAt > Date.now() - updateIntervalMs &&
    !(state.failedAt >= state.successAt);
  const recentFailure = saved.length > 0 && state?.failedAt > Date.now() - retryDelayMs &&
    !(state.successAt > state.failedAt);
  const response = (records, meta) => {
    const merged = mergeCatalogRecords(records, lookup);
    const hasMore = merged.length > limit && limit < MAX_CATALOG_RESULTS;
    const visible = merged.slice(0, limit);
    const older = visible.some((record) => record.source !== 'renthub-curated' &&
      new Date(record.lastSyncedAt).getTime() < Date.now() - updateIntervalMs);
    return { ...meta, stale: meta.stale || older,
      items: visible.map((item) => publicItem(item, input.query)),
      limit, hasMore, nextLimit: hasMore ? Math.min(limit + env.catalogMaxResults, MAX_CATALOG_RESULTS) : null,
      reachedLimit: limit === MAX_CATALOG_RESULTS && merged.length > limit };
  };
  if (preferCache && !force && (saved.length || curated.length)) {
    const stale = saved.some((record) => record.source !== 'renthub-curated' &&
      new Date(record.lastSyncedAt).getTime() < Date.now() - updateIntervalMs);
    return response([...saved, ...curated], { provider: 'mongodb-cache',
      providerAvailable: !recentFailure, stale: stale || recentFailure,
      refreshNeeded: !knownFresh && !recentFailure });
  }
  if (!force && (knownFresh || input.limit === undefined && fresh.length)) {
    return response([...fresh, ...curated, ...await cached(input, true)], {
      provider: 'mongodb-cache', providerAvailable: true, stale: false, refreshNeeded: false });
  }
  if (recentFailure) {
    return response([...saved, ...curated], { provider: 'mongodb-cache',
      providerAvailable: false, stale: true, refreshNeeded: false,
      warning: 'Updates are temporarily unavailable. Saved suggestions and manual entry remain available.' });
  }
  try {
    const result = await refreshProvider(lookup, key);
    return response([...result.stored, ...curated, ...saved], {
      provider: result.provider, providerAvailable: result.available,
      stale: !result.available, refreshNeeded: false });
  } catch {
    const stale = mergeCatalogRecords([...saved, ...curated], lookup);
    if (!stale.length) {
      throw new AppError(
        'The product catalog is temporarily unavailable. Manual entry remains available.',
        503,
        'CATALOG_UNAVAILABLE',
        { provider: catalogProvider.strategy(input), cacheHit: false },
      );
    }
    return response(stale, { provider: 'mongodb-cache', providerAvailable: false,
      stale: true, refreshNeeded: false,
      warning: 'The product catalog is temporarily unavailable. Manual entry remains available.' });
  }
}

export async function resolveProductIdentity(input) {
  const brand = String(input.brand ?? '').trim();
  const model = String(input.product_model ?? input.productModel ?? '').trim();
  const manual = {
    brand,
    model,
    canonicalProductId: null,
    catalogBrandId: null,
    productMatchType: 'manual_entry',
    catalogSource: null,
  };
  if (input.canonicalProductId) {
    const product = await ProductCatalogModel.findOne({
      canonicalProductId: input.canonicalProductId,
      entityType: 'product',
      category: input.category,
      subcategory: input.subcategory,
    }).lean();
    if (
      product &&
      matchesCatalogText(brand, [product.brand]) &&
      matchesCatalogText(model, [product.model, ...(product.aliases ?? [])])
    ) {
      const requestedType = PRODUCT_MATCH_TYPES.includes(input.productMatchType)
        ? input.productMatchType
        : 'exact_catalog_match';
      return {
        brand: product.brand,
        model: product.model,
        canonicalProductId: product.canonicalProductId,
        catalogBrandId: product.canonicalBrandId,
        productMatchType: requestedType === 'fuzzy_catalog_match'
          ? requestedType
          : 'exact_catalog_match',
        catalogSource: product.source,
      };
    }
  }
  if (input.catalogBrandId) {
    const catalogBrand = await ProductCatalogModel.findOne({
      canonicalBrandId: input.catalogBrandId,
      entityType: 'brand',
      category: input.category,
      subcategory: input.subcategory,
    }).lean();
    if (
      catalogBrand &&
      matchesCatalogText(brand, [
        catalogBrand.brand,
        ...(catalogBrand.aliases ?? []),
      ])
    ) {
      return {
        ...manual,
        brand: catalogBrand.brand,
        catalogBrandId: catalogBrand.canonicalBrandId,
        productMatchType: 'catalog_brand_match_model_manual',
        catalogSource: catalogBrand.source,
      };
    }
  }
  return manual;
}

export const catalogService = {
  brands: (query) => search({ ...query, entityType: 'brand' }),
  models: (query) => search({ ...query, entityType: 'product' }),
  search: async (query) => {
    const entityType = query.brand ? 'product' : 'brand';
    return search({ ...query, entityType });
  },
  resolveProductIdentity,
};
