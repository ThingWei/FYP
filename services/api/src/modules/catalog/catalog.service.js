import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { catalogProvider, isValidWikidataFallback } from './catalog.provider.js';
import { searchCuratedCatalog } from './catalog.curated.js';
import { ProductCatalogModel, PRODUCT_MATCH_TYPES } from './productCatalog.model.js';

export function normalizeCatalogText(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
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
    .sort({ lastSyncedAt: -1 })
    .limit(env.catalogMaxResults)
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
  }).slice(0, env.catalogMaxResults);
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
  // Only a fresh primary-provider record may short-circuit the provider chain.
  // A prior general fallback must not prevent a domain provider from running.
  const fresh = await cached(input, true, true);
  const curated = await storeProviderItems(input, searchCuratedCatalog(input));
  if (fresh.length) {
    return {
      items: mergeCatalogRecords([...fresh, ...curated, ...await cached(input, true)], input)
        .map((item) => publicItem(item, input.query)),
      provider: 'mongodb-cache',
      providerAvailable: true,
      stale: false,
    };
  }
  try {
    const providerResult = await catalogProvider.search(input);
    const providerItems = Array.isArray(providerResult)
      ? providerResult
      : providerResult.items;
    const providerName = Array.isArray(providerResult)
      ? catalogProvider.strategy(input)
      : providerResult.provider;
    const stored = await storeProviderItems(input, providerItems);
    return {
      items: mergeCatalogRecords([...stored, ...curated, ...await cached(input, true)], input)
        .map((item) => publicItem(item, input.query)),
      provider: providerName,
      providerAvailable: providerResult.providerAvailable !== false,
      stale: false,
    };
  } catch {
    const stale = mergeCatalogRecords([...await cached(input, false), ...curated], input);
    if (!stale.length) {
      throw new AppError(
        'The product catalog is temporarily unavailable. Manual entry remains available.',
        503,
        'CATALOG_UNAVAILABLE',
        { provider: catalogProvider.strategy(input), cacheHit: false },
      );
    }
    return {
      items: stale.map((item) => publicItem(item, input.query)),
      provider: 'mongodb-cache',
      providerAvailable: false,
      stale: true,
      warning: 'The product catalog is temporarily unavailable. Manual entry remains available.',
    };
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
