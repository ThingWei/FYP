import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';

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

// Product types are semantic guards, never price rules. Unknown types fail closed.
export function productTypeFor(category, subcategory, text) {
  const value = String(text ?? '').toLowerCase();
  if (category === 'Vehicles') return ({ Cars: 'car', Motorcycles: 'motorcycle', Bicycles: 'bicycle', 'Other vehicles': /scooter/.test(value) ? 'electric_scooter' : null })[subcategory] ?? null;
  if (subcategory === 'Smartphones') return 'smartphone';
  if (subcategory === 'Cameras') return /\blens\b|\b(?:ef|rf|fe|af-s|af-p)\b.*\d.*mm/.test(value) ? 'camera_lens' : 'camera';
  if (subcategory === 'Computers') return /desktop|\bpc\b/.test(value) ? 'desktop' : /laptop|notebook|macbook|latitude|thinkpad|\bxps\b|ideapad/.test(value) ? 'laptop' : null;
  if (subcategory === 'Gaming') return /playstation|ps[345]|xbox|switch/.test(value) ? 'console' : null;
  if (subcategory === 'Audio') {
    if (/microphone|microfone|\bmic\b|by-m|by-wm|ecm-|wm820/.test(value)) return 'microphone';
    if (/headphone|earphone|earbud|wh-|wf-|tune |quietcomfort/.test(value)) return 'headphones';
    if (/speaker|partybox|srs-|charge \d|flip \d|soundlink|xtreme/.test(value)) return 'speaker';
    return null;
  }
  if (subcategory === 'Other devices') {
    if (/walkie|motorola t[68]/.test(value)) return 'walkie_talkie';
    if (/video capture|atem|mars 400|transmitter/.test(value)) return 'video_capture';
    return null;
  }
  if (subcategory === 'Event equipment') {
    if (/projector|\beb-[a-z0-9]|\bth575\b|\btk700\b/.test(value)) return 'projector';
    if (/\btv\b|television/.test(value)) return 'television';
    if (/speaker.*mic|pa system|stagepas/.test(value)) return 'pa_set';
    if (/light|godox|sk[34]00/.test(value)) return 'lighting';
    return null;
  }
  if (subcategory === 'Tools') return /drill|\bgsb\b|\bgsr\b/.test(value) ? 'drill' : /hammer|\bgbh\b/.test(value) ? 'hammer' : /saw|\bgks\b/.test(value) ? 'saw' : /ladder/.test(value) ? 'ladder' : null;
  if (subcategory === 'Sports equipment') return /racket|racquet|blade 98|pro staff|astrox|nanoflare|speed mp|radical mp/.test(value) ? 'racket' : null;
  if (subcategory === 'Other equipment') {
    if (/puzzi|fabric cleaner|carpet extractor/.test(value)) return 'fabric_cleaner';
    if (/pressure washer|\bk[2-7]\b|c 110|c 120/.test(value)) return 'pressure_washer';
    if (/vacuum|wet.*dry|\bwd \d|\bv(?:8|15)\b|nt30/.test(value)) return 'vacuum';
    return null;
  }
  if (subcategory === 'Formal wear') return /suit|tuxedo|huge.*genius/.test(value) ? 'suit' : /blazer|jacket/.test(value) ? 'formal_jacket' : /gown|dress/.test(value) ? 'formal_dress' : null;
  if (subcategory === 'Traditional wear') return /hanfu/.test(value) ? 'hanfu' : /baju|kurung|melayu|nikah/.test(value) ? 'malay_traditional' : /kurta|sherwani/.test(value) ? 'kurta' : /traditional/.test(value) ? 'traditional_costume' : null;
  if (subcategory === 'Costumes') return /costume|jedi|joker|egyptian/.test(value) ? 'costume' : null;
  if (subcategory === 'Other clothing') return /winter|coat|jacket|nuptse|powder lite/.test(value) ? 'winter_garment' : null;
  return null;
}
