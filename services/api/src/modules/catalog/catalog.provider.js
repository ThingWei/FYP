import { env } from '../../config/env.js';
import { catalogCoverageFor } from './catalog.coverage.js';
import { searchCuratedCatalog } from './catalog.curated.js';

let nextRequestAt = 0;
let requestQueue = Promise.resolve();
const vehicleMakesCache = new Map();

const SMARTPHONE_TYPES = ['Q19723451', 'Q71266741', 'Q20488450'];

const categoryTerms = {
  Books: ['book', 'author', 'publisher', 'novel', 'edition', 'literature'],
  Clothing: ['clothing', 'fashion', 'apparel', 'designer', 'garment'],
  Devices: ['device', 'electronic', 'technology', 'camera', 'computer', 'phone'],
  Equipment: ['equipment', 'tool', 'machine', 'sport', 'event'],
  Vehicles: ['vehicle', 'automobile', 'automotive', 'car', 'motorcycle', 'bicycle'],
};

const subcategoryTerms = {
  Audio: ['audio', 'speaker', 'headphone', 'microphone', 'amplifier'],
  Gaming: ['gaming', 'game console', 'console', 'video game'],
  Cars: ['car', 'automobile', 'automotive', 'sedan', 'suv', 'pickup', 'hatchback'],
  Motorcycles: ['motorcycle', 'motorbike', 'scooter'],
  Bicycles: ['bicycle', 'bike', 'cycling'],
  'Other vehicles': ['vehicle', 'mobility', 'scooter'],
  Smartphones: ['smartphone', 'phone', 'mobile'],
  Cameras: ['camera', 'photography', 'imaging'],
  Computers: ['computer', 'laptop', 'desktop'],
  'Other devices': ['device', 'electronic'],
  'Event equipment': ['event', 'audio', 'lighting', 'projector', 'stage'],
  Tools: ['tool', 'drill', 'saw', 'power tool'],
  'Sports equipment': ['sport', 'fitness', 'racket', 'ball', 'kayak'],
  'Other equipment': ['equipment', 'machine'],
  Textbooks: ['textbook', 'educational book'],
  'Reference books': ['reference book', 'encyclopedia', 'dictionary'],
  Fiction: ['novel', 'fiction', 'book'],
  'Other books': ['book', 'guide'],
  'Formal wear': ['formal wear', 'suit', 'tuxedo', 'blazer'],
  Costumes: ['costume', 'cosplay', 'fancy dress'],
  'Traditional wear': ['traditional wear', 'baju', 'kurung', 'kebaya'],
  'Other clothing': ['clothing', 'apparel', 'jacket'],
};

function normalized(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function unique(items) {
  const seen = new Set();
  return items.filter((item) => {
    const key = `${item.source}:${item.id}`;
    if (!item.label || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function canonicalOrganizationName(value) {
  return String(value ?? '')
    .replace(/\s+(incorporated|inc\.?|corporation|corp\.?|company|co\.?|ltd\.?)$/i, '')
    .trim();
}

function titleCase(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/(^|[\s-])([a-z])/g, (_match, prefix, letter) =>
      `${prefix}${letter.toUpperCase()}`);
}

function rawCanonicalId(value, source) {
  const prefix = `${source}:`;
  return String(value ?? '').startsWith(prefix)
    ? String(value).slice(prefix.length)
    : String(value ?? '');
}

function entityId(uri) {
  return String(uri ?? '').split('/').pop();
}

async function waitForProviderSlot() {
  const delay = Math.max(0, nextRequestAt - Date.now());
  if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
  nextRequestAt = Date.now() + env.catalogMinIntervalMs;
}

async function getJson(url, accept = 'application/json') {
  requestQueue = requestQueue.then(waitForProviderSlot, waitForProviderSlot);
  await requestQueue;
  const response = await fetch(url, {
    headers: {
      accept,
      'user-agent': 'RentHub/1.0 product-catalog',
    },
    signal: AbortSignal.timeout(env.catalogTimeoutMs),
  });
  if (!response.ok) {
    throw new Error(`${new URL(url).hostname} returned HTTP ${response.status}`);
  }
  return response.json();
}

export function catalogProviderStrategy(input) {
  return catalogCoverageFor(input.category, input.subcategory).strategies[0];
}

export function catalogProviderStrategies(input) {
  return catalogCoverageFor(input.category, input.subcategory)
    .strategies.filter((strategy) => strategy !== 'manual-entry');
}

export function catalogSourcesFor(input) {
  const byStrategy = {
    'nhtsa-vpic': ['nhtsa-vpic'],
    'wikidata-smartphones': ['wikidata-smartphones'],
    openlibrary: ['openlibrary'],
    'renthub-curated': ['renthub-curated'],
    'wikidata-validated': ['wikidata'],
  };
  return [...new Set(catalogProviderStrategies(input)
    .flatMap((strategy) => byStrategy[strategy] ?? []))];
}

async function vehicleMakes(vehicleType) {
  const cached = vehicleMakesCache.get(vehicleType);
  if (cached?.expiresAt > Date.now()) return cached.items;
  const url = new URL(
    `/api/vehicles/GetMakesForVehicleType/${vehicleType}`,
    env.catalogVehicleProviderUrl,
  );
  url.searchParams.set('format', 'json');
  const payload = await getJson(url);
  const items = unique((payload.Results ?? []).map((item) => ({
    id: String(item.MakeId),
    label: titleCase(item.MakeName),
    aliases: [String(item.MakeName ?? '')],
    description: 'Vehicle make listed in the NHTSA vPIC vehicle catalog',
    source: 'nhtsa-vpic',
  })));
  vehicleMakesCache.set(vehicleType, {
    items,
    expiresAt: Date.now() + 24 * 60 * 60 * 1000,
  });
  return items;
}

async function searchVehicles(input) {
  const vehicleType = input.subcategory === 'Motorcycles' ? 'motorcycle' : 'car';
  if (input.entityType === 'brand') {
    const query = normalized(input.query);
    return (await vehicleMakes(vehicleType))
      .filter((item) => normalized(item.label).includes(query))
      .sort((left, right) => {
        const leftExact = normalized(left.label) === query ? 1 : 0;
        const rightExact = normalized(right.label) === query ? 1 : 0;
        return rightExact - leftExact || left.label.localeCompare(right.label);
      })
      .slice(0, env.catalogMaxResults);
  }
  let makeId = rawCanonicalId(input.catalogBrandId, 'nhtsa-vpic');
  if (!/^\d+$/.test(makeId)) {
    makeId = (await vehicleMakes(vehicleType)).find((item) =>
      [item.label, ...(item.aliases ?? [])].some((name) => normalized(name) === normalized(input.brand)))?.id ?? '';
  }
  if (!/^\d+$/.test(makeId)) return [];
  const url = new URL(
    `/api/vehicles/GetModelsForMakeIdYear/makeId/${encodeURIComponent(makeId)}/vehicletype/${vehicleType}`,
    env.catalogVehicleProviderUrl,
  );
  url.searchParams.set('format', 'json');
  const payload = await getJson(url);
  const query = normalized(input.query);
  return unique((payload.Results ?? []).map((item) => ({
    id: `${item.Make_ID}:${item.Model_ID}`,
    label: String(item.Model_Name ?? '').trim(),
    aliases: [],
    description: `${item.Make_Name} vehicle model from the NHTSA vPIC catalog`,
    source: 'nhtsa-vpic',
  })))
    .filter((item) => !query || normalized(item.label).includes(query))
    .sort((left, right) => left.label.localeCompare(right.label))
    .slice(0, env.catalogMaxResults);
}

function sparqlUrl(query) {
  const url = new URL(env.catalogWikidataSparqlUrl);
  url.searchParams.set('format', 'json');
  url.searchParams.set('query', query);
  return url;
}

function sparqlString(value) {
  return JSON.stringify(normalized(value));
}

async function searchSmartphones(input) {
  const typeValues = SMARTPHONE_TYPES.map((id) => `wd:${id}`).join(' ');
  if (input.entityType === 'brand') {
    const query = `
SELECT DISTINCT ?manufacturer ?manufacturerLabel WHERE {
  VALUES ?phoneType { ${typeValues} }
  ?phone wdt:P31 ?phoneType; wdt:P176 ?manufacturer.
  ?manufacturer rdfs:label ?manufacturerLabel.
  FILTER(LANG(?manufacturerLabel) = "en")
  FILTER(CONTAINS(LCASE(?manufacturerLabel), ${sparqlString(input.query)}))
} LIMIT ${env.catalogMaxResults}`;
    const payload = await getJson(
      sparqlUrl(query),
      'application/sparql-results+json',
    );
    return unique((payload.results?.bindings ?? []).map((binding) => ({
      id: entityId(binding.manufacturer?.value),
      label: canonicalOrganizationName(binding.manufacturerLabel?.value),
      aliases: [binding.manufacturerLabel?.value].filter(Boolean),
      description: 'Manufacturer with smartphone models in Wikidata',
      source: 'wikidata-smartphones',
    })));
  }
  let brandId = rawCanonicalId(input.catalogBrandId, 'wikidata-smartphones');
  if (!/^Q\d+$/.test(brandId)) {
    const brands = await searchSmartphones({ ...input, entityType: 'brand', query: input.brand });
    brandId = brands.find((item) => [item.label, ...(item.aliases ?? [])]
      .some((name) => normalized(name) === normalized(input.brand)))?.id ?? '';
  }
  if (!/^Q\d+$/.test(brandId)) return [];
  const queryFilter = normalized(input.query)
    ? `FILTER(CONTAINS(LCASE(?modelLabel), ${sparqlString(input.query)}))`
    : '';
  const query = `
SELECT DISTINCT ?model ?modelLabel WHERE {
  VALUES ?phoneType { ${typeValues} }
  ?model wdt:P31 ?phoneType; wdt:P176 wd:${brandId}; rdfs:label ?modelLabel.
  FILTER(LANG(?modelLabel) = "en")
  ${queryFilter}
} ORDER BY ?modelLabel LIMIT ${env.catalogMaxResults}`;
  const payload = await getJson(
    sparqlUrl(query),
    'application/sparql-results+json',
  );
  return unique((payload.results?.bindings ?? []).map((binding) => ({
    id: entityId(binding.model?.value),
    label: String(binding.modelLabel?.value ?? '').trim(),
    aliases: [],
    description: `Smartphone model manufactured by ${input.brand}`,
    source: 'wikidata-smartphones',
  })));
}

async function searchBooks(input) {
  if (input.entityType === 'brand') {
    if (!normalized(input.query)) return [];
    const url = new URL('/search/authors.json', env.catalogBookProviderUrl);
    url.searchParams.set('q', input.query);
    url.searchParams.set('limit', String(env.catalogMaxResults));
    const payload = await getJson(url);
    const authors = unique((payload.docs ?? []).map((author) => ({
      id: String(author.key ?? '').replace('/authors/', ''),
      label: String(author.name ?? '').trim(),
      aliases: author.alternate_names ?? [],
      description: author.top_work
        ? `Author · known for ${author.top_work}`
        : 'Author in the Open Library catalog',
      source: 'openlibrary',
    })));
    const valid = [];
    for (const author of authors.slice(0, 5)) {
      if (searchCuratedCatalog({ ...input, query: author.label }).some((item) => normalized(item.label) === normalized(author.label))) {
        valid.push(author);
      } else if (/^OL\d+A$/i.test(author.id)) {
        const worksUrl = new URL(`/authors/${author.id}/works.json`, env.catalogBookProviderUrl);
        worksUrl.searchParams.set('limit', '20');
        const works = await getJson(worksUrl);
        if ((works.entries ?? []).some((work) => bookMatchesDomain(work, input))) valid.push(author);
      }
    }
    return valid;
  }
  let authorId = rawCanonicalId(input.catalogBrandId, 'openlibrary')
    .replace('/authors/', '');
  if (!/^OL\d+A$/i.test(authorId)) {
    const authors = await searchBooks({ ...input, entityType: 'brand', query: input.brand });
    authorId = authors.find((author) => [author.label, ...(author.aliases ?? [])]
      .some((name) => normalized(name) === normalized(input.brand)))?.id ?? '';
  }
  if (!/^OL\d+A$/i.test(authorId)) return [];
  const url = new URL(
    `/authors/${encodeURIComponent(authorId)}/works.json`,
    env.catalogBookProviderUrl,
  );
  url.searchParams.set('limit', String(Math.max(env.catalogMaxResults * 4, 40)));
  const payload = await getJson(url);
  const query = normalized(input.query);
  return unique((payload.entries ?? []).filter((work) => bookMatchesDomain(work, input)).map((work) => ({
    id: String(work.key ?? '').replace('/works/', ''),
    label: String(work.title ?? '').trim(),
    aliases: [],
    description: `Book work by ${input.brand} in Open Library`,
    source: 'openlibrary',
  })))
    .filter((item) => !query || normalized(item.label).includes(query))
    .slice(0, env.catalogMaxResults);
}

export function bookMatchesDomain(work, input) {
  const known = searchCuratedCatalog({ ...input, entityType: 'product', query: '' });
  if (known.some((item) => normalized(item.label) === normalized(work.title))) return true;
  const subjects = normalized((work.subjects ?? []).join(' '));
  const terms = {
    Textbooks: ['textbook', 'study and teaching', 'problems exercises', 'college textbook'],
    'Reference books': ['encyclopedia', 'encyclopedias', 'dictionary', 'dictionaries', 'reference'],
    Fiction: ['fiction', 'novel', 'fantasy', 'mystery'],
    'Other books': ['guidebook', 'travel', 'nonfiction', 'non fiction', 'cookbook', 'biography'],
  };
  return (terms[input.subcategory] ?? []).some((term) => subjects.includes(term));
}

export function isValidWikidataFallback(item, input) {
  const text = normalized(`${item.label} ${item.description} ${(item.aliases ?? []).join(' ')}`);
  const domainTerms = subcategoryTerms[input.subcategory] ?? categoryTerms[input.category] ?? [];
  const hasDomain = domainTerms.some((term) => text.includes(term));
  if (!hasDomain) return false;
  if (input.entityType === 'brand') {
    return /(manufacturer|brand|company|author|publisher|designer)/.test(text);
  }
  const brand = normalized(input.brand);
  return /(model|series|vehicle|book|device|equipment|product)/.test(text) &&
    (!brand || text.includes(brand));
}

export function rankCatalogProviderItems(items, input) {
  const query = normalized(input.query);
  const terms = [
    ...(categoryTerms[input.category] ?? []),
    ...(subcategoryTerms[input.subcategory] ?? []),
  ];
  return items.map((item, index) => {
    const label = normalized(item.label);
    const aliases = (item.aliases ?? []).map(normalized);
    const description = normalized(item.description);
    let score = 0;
    if (label === query || aliases.includes(query)) score += 30;
    else if (!query || label.startsWith(query) || label.includes(query)) score += 15;
    score += terms.filter((term) =>
      description.includes(term) || label.includes(term)).length * 4;
    return { item, index, score };
  })
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ item }) => item);
}

async function searchValidatedWikidata(input) {
  // Browsing must never become an unrestricted general entity search.
  if (!normalized(input.query)) return [];
  const url = new URL(env.catalogProviderUrl);
  url.search = new URLSearchParams({
    action: 'wbsearchentities',
    search: input.entityType === 'brand'
      ? input.query
      : [input.brand, input.query].filter(Boolean).join(' '),
    language: 'en',
    uselang: 'en',
    format: 'json',
    origin: '*',
    limit: String(Math.max(env.catalogMaxResults * 3, 20)),
  }).toString();
  const payload = await getJson(url);
  const items = (payload.search ?? []).map((item) => ({
    id: String(item.id),
    label: String(item.label ?? item.match?.text ?? '').trim(),
    description: String(item.description ?? '').trim(),
    aliases: [item.match?.text].filter(Boolean),
    source: 'wikidata',
  })).filter((item) => item.label && isValidWikidataFallback(item, input));
  return rankCatalogProviderItems(items, input).slice(0, env.catalogMaxResults);
}

async function search(input) {
  if (env.catalogMode === 'disabled') throw new Error('Catalog provider is disabled');
  const providers = {
    'nhtsa-vpic': searchVehicles,
    'wikidata-smartphones': searchSmartphones,
    openlibrary: searchBooks,
    'renthub-curated': searchCuratedCatalog,
    'wikidata-validated': searchValidatedWikidata,
  };
  const attempted = [];
  const errors = [];
  let successfulProvider = null;
  const collected = [];
  for (const strategy of catalogProviderStrategies(input)) {
    if (strategy === 'wikidata-validated' && collected.length) continue;
    attempted.push(strategy);
    try {
      const items = await providers[strategy](input);
      successfulProvider = strategy;
      collected.push(...items);
    } catch (error) {
      errors.push(`${strategy}: ${error.message}`);
    }
  }
  if (collected.length) {
    const seen = new Set();
    const brand = normalized(input.brand);
    const items = collected.filter((item) => {
      let key = normalized(item.label);
      if (input.entityType !== 'brand' && key.startsWith(`${brand} `)) key = key.slice(brand.length + 1);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    return { provider: collected[0].source, attempted, items,
      providerAvailable: errors.length === 0 };
  }
  if (successfulProvider && errors.length === 0) {
    return { provider: successfulProvider, attempted, items: [] };
  }
  throw new Error(
    `Catalog lookup could not determine a reliable no-match: ${errors.join('; ')}`,
  );
}

export const catalogProvider = {
  search,
  strategy: catalogProviderStrategy,
  strategies: catalogProviderStrategies,
  sourcesFor: catalogSourcesFor,
};
