import { env } from '../../config/env.js';

let nextRequestAt = 0;
let requestQueue = Promise.resolve();

const categoryTerms = {
  Books: ['book', 'author', 'publisher', 'novel', 'edition'],
  Clothing: ['clothing', 'fashion', 'apparel', 'designer', 'garment'],
  Devices: ['device', 'electronic', 'technology', 'camera', 'computer', 'phone'],
  Equipment: ['equipment', 'tool', 'machine', 'sport', 'event'],
  Vehicles: ['vehicle', 'automobile', 'automotive', 'car', 'motorcycle', 'bicycle'],
};

const subcategoryTerms = {
  Cars: ['car', 'automobile', 'automotive', 'sedan', 'suv', 'pickup', 'hatchback'],
  Motorcycles: ['motorcycle', 'motorbike', 'scooter'],
  Bicycles: ['bicycle', 'bike', 'cycling'],
  Smartphones: ['smartphone', 'phone', 'mobile'],
  Cameras: ['camera', 'photography', 'imaging'],
  Computers: ['computer', 'laptop', 'desktop'],
};

function normalized(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function rankCatalogProviderItems(items, input) {
  const query = normalized(input.query);
  const terms = [
    ...(categoryTerms[input.category] ?? []),
    ...(subcategoryTerms[input.subcategory] ?? []),
  ];
  const scored = items.map((item, index) => {
    const label = normalized(item.label);
    const aliases = (item.aliases ?? []).map(normalized);
    const description = normalized(item.description);
    let score = 0;
    if (label === query || aliases.includes(query)) score += 30;
    else if (label.startsWith(query) || label.includes(query)) score += 15;
    score += terms.filter((term) =>
      description.includes(term) || label.includes(term)).length * 4;
    if (input.entityType === 'brand' &&
        /(manufacturer|brand|company|author|publisher|designer)/.test(description)) {
      score += 12;
    }
    if (input.entityType === 'product' &&
        /(model|series|vehicle|book|device|equipment|product)/.test(description)) {
      score += 10;
    }
    return { item, index, score };
  });
  return scored
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ item }) => item);
}

async function waitForProviderSlot() {
  const delay = Math.max(0, nextRequestAt - Date.now());
  if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
  nextRequestAt = Date.now() + env.catalogMinIntervalMs;
}

function providerQuery({ entityType, brand, query }) {
  // Wikidata entity search is keyword-oriented. Adding RentHub taxonomy labels
  // such as "Devices" or "Bicycles" can hide valid entities (for example Sony),
  // so taxonomy is applied to our cache record rather than the provider phrase.
  return entityType === 'brand'
    ? query
    : [brand, query].filter(Boolean).join(' ');
}

async function wikidataSearch(input) {
  if (env.catalogMode === 'disabled') {
    throw new Error('Catalog provider is disabled');
  }
  requestQueue = requestQueue.then(waitForProviderSlot, waitForProviderSlot);
  await requestQueue;
  const url = new URL(env.catalogProviderUrl);
  url.search = new URLSearchParams({
    action: 'wbsearchentities',
    search: providerQuery(input),
    language: 'en',
    uselang: 'en',
    format: 'json',
    origin: '*',
    limit: String(env.catalogMaxResults),
  }).toString();
  const response = await fetch(url, {
    headers: { 'user-agent': 'RentHub/1.0 product-catalog' },
    signal: AbortSignal.timeout(env.catalogTimeoutMs),
  });
  if (!response.ok) throw new Error(`Wikidata returned HTTP ${response.status}`);
  const payload = await response.json();
  const items = (payload.search ?? []).map((item) => ({
    id: String(item.id),
    label: String(item.label ?? item.match?.text ?? '').trim(),
    description: String(item.description ?? '').trim(),
    aliases: [item.match?.text].filter(Boolean),
    source: 'wikidata',
  })).filter((item) => item.label);
  return rankCatalogProviderItems(items, input);
}

export const catalogProvider = {
  search: wikidataSearch,
};
