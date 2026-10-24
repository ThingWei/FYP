import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';
export { productTypeFor } from './priceProductDomains.js';

const source = (id, name, urls, domains, options = {}) => Object.freeze({
  id, name, urls, domains, parserVersion: '1', adapter: id,
  accessStatus: 'review_required',
  limitation: 'One-time source access/reuse review required before enabling collection.',
  ...options,
});

// URLs are code-owned. Administrators cannot submit a URL or crawl arbitrary sites.
export const PRICE_SOURCES = Object.freeze([
  source('rentism', 'RENTISM', ['https://www.rentism.com.my/price-list/'],
    ['Smartphones', 'Cameras', 'Audio', 'Other devices', 'Event equipment']),
  source('irent', 'iRent', ['https://irent.my/product-category/smartphone-rental/'],
    ['Smartphones'], { parserVersion: '2', discovery: /^\/product\/[a-z0-9-]+\/$/, discoveryFrom: /^\/product-category\//,
      limitation: 'Product-page duration tiers only; headline minimum and ambiguous yearly tiers excluded. Stock substitution and collection terms apply.' }),
  source('itpa', 'ITPA', ['https://itpa.my/pc-rental.php'], ['Computers']),
  source('rentsmart', 'RentSmart Asia', [
    'https://rentsmartasia.com/product-category/rent-equipment/electronics/',
    'https://rentsmartasia.com/product-category/rent-vehicles-vessels/scooters/',
    'https://rentsmartasia.com/product-category/rentals/sports/',
  ], ['Computers', 'Audio', 'Gaming', 'Other vehicles', 'Sports equipment'],
  { adapter: null, limitation: 'Direct public category pages currently return an empty catalogue, including the current electronics route. No verifiable page quotes are available; search-engine snippets are not ingested.' }),
  source('cilt', 'Cilt Tech', ['https://cilttech.com/ms/sewaan'], ['Gaming']),
  source('drivor', 'DRIVOR', ['https://drivor.my/vehicle/toyota-camry/'], ['Cars'],
    { discovery: /^\/vehicle\/[a-z0-9-]+\/$/, limitation: 'Only explicit daily duration bands; mileage and charges retained.' }),
  source('alquiler', 'Alquiler Motorbike', ['https://alquilermotorbike.com/llms.txt'], ['Motorcycles'],
    { limitation: 'Uses the publicly published AI-readable catalogue; never calls disallowed booking/private APIs.' }),
  source('ecocana', 'Ecocana Sports', ['https://ecocanasports.com/rent'], ['Bicycles'],
    { limitation: 'Only catalogue products explicitly labelled daily rental; retail entries excluded.' }),
  source('goritta', 'Goritta', ['https://goritta.com/pages/camp-like-a-pro-goritta-camping-equipment-rental'], ['Sports equipment'],
    { requiresWrittenPermission: true,
      limitation: 'Written reuse permission required before collection. Named tents only; fixed four-day packages, not advertised one-day rates. Maintenance items and unsupported camping gear excluded.' }),
  source('rental-guy', 'The Rental Guy', ['https://therentalguy.com.my/av-solution/'], ['Event equipment'],
    { limitation: 'Specification-only one-day reference prices; before tax; delivery/setup quoted separately.' }),
  source('pc-rent', 'PC Rent', ['https://www.pcrent.com.my/home/rental_rates'], ['Event equipment'],
    { limitation: 'Brightness-specification projector rates, not exact manufacturer/model prices.' }),
  source('12rent', '12RENT', ['https://toolrent.instantestore.com/cat-power-tools.cfm'], ['Tools'],
    { parserVersion: '2', discovery: /^\/pd-rental-[a-z0-9-]+\.cfm$/, discoveryFrom: /^\/cat-[a-z0-9-]+\.cfm$/,
      limitation: 'Explicit daily lease fields and minimum rental period only; checkout/deposit values excluded. Current robots response is unrendered markup, so collection remains blocked pending a valid policy.' }),
  source('jomrent', 'JomRentPro', ['https://jomrentpro.com/'], ['Tools', 'Other equipment'],
    { limitation: 'Contradictory quotes and alternative-model offers excluded; retail consumables and multi-machine bundles excluded.' }),
  source('partymix', 'Partymix', ['https://partymix.com.my/product-tag/men/',
    'https://partymix.com.my/product-tag/men/page/2/'], ['Formal wear', 'Costumes', 'Traditional wear'],
    { limitation: 'Unbranded garments use type comparisons only; rental fee excludes refundable deposit.' }),
  source('futago', 'Futago Winter', ['https://futago.twinsjapantrading.com.my/'], ['Other clothing'],
    { limitation: 'Broad winter-garment 10-day package; not a named-brand/model quote; cleaning/delivery excluded.' }),
  source('avm', 'AVMProjector', ['https://www.avmprojector.com/rental'], ['Event equipment'],
    { adapter: null, limitation: 'Optional candidate only; access failure during research. Not a required dependency.' }),
]);

export const PRICE_SOURCE_COVERAGE = Object.freeze(CATALOG_COVERAGE.map(({ category, subcategory }) => ({
  category, subcategory,
  sourceIds: PRICE_SOURCES.filter((entry) => entry.domains.includes(subcategory) && entry.id !== 'avm').map((entry) => entry.id),
  fallback: 'renthub_evidence_then_conservative_estimate_or_manual_price',
  limitation: category === 'Books' ? 'No verified Malaysian per-title rental-price source; retail and subscription prices excluded.' : '',
})));

export const FUTURE_PRICE_DOMAINS = Object.freeze([
  { domain: 'Educational/children’s toys', url: 'https://pleylore.com/plan', limitation: 'Subscription credits are not per-toy daily quotes.' },
  { domain: 'Board games and giant games', url: 'https://www.fndmindspot.com/game-rental', limitation: 'Amount, period and package require validation.' },
  { domain: 'Party games and attractions', url: 'https://www.carnivalgamesrental.my/product/giant-chess', limitation: 'Delivery/setup/crew bundles cannot price equipment-only rentals.' },
]);

export function priceSource(id) { return PRICE_SOURCES.find((entry) => entry.id === id); }

export function isAllowedSourceUrl(entry, value) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.search || url.hash) return false;
    return entry.urls.includes(url.href) || Boolean(entry.discovery &&
      url.origin === new URL(entry.urls[0]).origin && entry.discovery.test(url.pathname));
  } catch { return false; }
}
