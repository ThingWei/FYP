import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';
import { suitableProductComparison } from './productComparisonFacts.js';

// Semantic identities only. No rental amounts, depreciation or manufacturer APIs.
const rules = {
  Smartphones: [['smartphone', /./]],
  Cameras: [['camera_adapter', /\badapter\b|\bmount adapter\b/],
    ['camera_accessory', /\bcage\b|\bgrip\b|\btripod\b|\bgimbal\b|\bflash\b/],
    ['action_camera', /\bgo\s?pro\b|\binsta360\b|\baction camera\b/],
    ['camcorder', /\bcamcorder\b|\bhandycam\b|\bhxr[- ]|\bfdr[- ]|\bpxw[- ]|osmo pocket/],
    ['cinema_camera', /\bcinema\b|\beos c\d/],
    ['camera_lens', /\blens\b|\b(?:ef|rf|fe|af-s|af-p)\b.*\d.*mm|\b\d+(?:\.\d+)?\s*mm\b/], ['camera', /./]],
  Computers: [['mouse', /\bmouse\b|\bmx master\b/], ['keyboard', /\bkeyboard\b|\bmx keys\b/],
    ['monitor', /\bmonitor\b|studio display|thunderbolt display|\bu\d{4}[a-z]+\b/],
    ['desktop', /desktop|\bpc\b|imac|mac mini/], ['laptop', /laptop|notebook|macbook|latitude|thinkpad|\bxps\b|ideapad/]],
  Audio: [['microphone', /microphone|microfone|\bmic\b|by-m|by-wm|ecm-|wm820/],
    ['headphones', /headphone|earphone|earbud|wh-|wf-|tune |quietcomfort/],
    ['speaker', /speaker|partybox|srs-|charge \d|flip \d|soundlink|xtreme/],
    ['audio_mixer', /mixer|\bmg\d{1,2}xu\b/]],
  Gaming: [['controller', /controller|dualshock|dualsense|joy-con/], ['vr_headset', /vr headset|meta quest|oculus/],
    ['console', /playstation|\bps[345]\b|xbox|switch/]],
  'Other devices': [['walkie_talkie', /walkie|motorola t[68]/], ['video_capture', /video capture|atem|mars 400|transmitter/],
    ['tablet', /\btablet\b|ipad|galaxy tab/], ['smartwatch', /smartwatch|watch series|galaxy watch|instinct 2|forerunner/],
    ['printer', /\bprinter\b/]],
  Cars: [['car', /./]], Motorcycles: [['motorcycle', /./]], Bicycles: [['bicycle', /./]],
  'Other vehicles': [['electric_scooter', /electric scooter|ninebot|\bhx x[79]\b|\be(?:100|300)\b|\bscooter\b/],
    ['mobility_scooter', /mobility scooter/], ['electric_unicycle', /electric unicycle/]],
  'Event equipment': [['projector', /projector|\beb-[a-z0-9]|\bth575\b|\btk700\b/], ['television', /\btv\b|television/],
    ['pa_set', /speaker.*mic|pa system|stagepas/], ['lighting', /light|godox|sk[34]00/],
    ['audio_mixer', /mixer|\bmg\d{1,2}xu\b/], ['tripod', /tripod|\bc-stand\b/],
    ['event_tent', /marquee|canopy/], ['event_table', /\btable\b/], ['event_chair', /\bchair\b/]],
  Tools: [['drill', /drill|\bgsb\b|\bgsr\b|\bdhp\d/], ['hammer', /hammer|\bgbh\b/],
    ['saw', /\bsaw\b|\bgks\b/], ['ladder', /ladder/], ['sander', /sander/], ['grinder', /grinder/]],
  'Sports equipment': [['racket', /racket|racquet|blade 98|pro staff|astrox|nanoflare|speed mp|radical mp/],
    ['camping_tent', /\btent\b|arpenaz|\bholiday retreat\b|\btier dome\b/], ['sleeping_bag', /sleeping bag/], ['golf_clubs', /golf (?:club|set)/],
    ['paddleboard', /paddleboard|stand.up paddle|\bsup\b/], ['kayak', /kayak/],
    ['life_jacket', /life jacket|buoyancy aid/], ['snorkel_set', /snorkel|scuba mask/],
    ['fitness_equipment', /treadmill|exercise bike|rowing machine/]],
  'Other equipment': [['fabric_cleaner', /puzzi|fabric cleaner|carpet extractor/],
    ['pressure_washer', /pressure washer|\bk[2-7]\b|c 110|c 120/], ['vacuum', /vacuum|wet.*dry|\bwd \d|\bv(?:8|15)\b|nt30/]],
  Textbooks: [['book', /./]], 'Reference books': [['book', /./]], Fiction: [['book', /./]], 'Other books': [['book', /./]],
  'Formal wear': [['suit', /suit|tuxedo|huge.*genius/], ['formal_jacket', /blazer|jacket/], ['formal_dress', /gown|dress/]],
  Costumes: [['costume', /costume|jedi|joker|egyptian/]],
  'Traditional wear': [['hanfu', /hanfu/], ['malay_traditional', /baju|kurung|melayu|nikah/],
    ['kurta', /kurta|sherwani/], ['traditional_costume', /traditional/]],
  'Other clothing': [['winter_garment', /winter|coat|jacket|nuptse|powder lite/], ['rainwear', /raincoat|poncho|blocktech/]],
};

export const PRICE_PRODUCT_DOMAINS = Object.freeze(CATALOG_COVERAGE.map(({ category, subcategory }) => Object.freeze({
  category, subcategory, productTypes: Object.freeze([...new Set(rules[subcategory].map(([type]) => type))]),
  requiredIdentity: category === 'Books' ? ['author_or_publisher', 'title', 'edition_when_known', 'isbn_when_known']
    : ['brand_or_specifications', 'model_or_item_type', 'variant_and_package_when_known'],
})));

export const priceText = (value) => String(value ?? '').normalize('NFKC').toLowerCase()
  .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().replace(/\s+/g, ' ');

export function productTypeFor(category, subcategory, text, declaredType) {
  if (!PRICE_PRODUCT_DOMAINS.some((row) => row.category === category && row.subcategory === subcategory)) return null;
  const value = String(text ?? '').normalize('NFKC').toLowerCase().trim();
  if (!value) return null;
  if (subcategory === 'Cameras') {
    const specific = rules.Cameras.slice(0, -1).find(([, pattern]) => pattern.test(value));
    if (specific) return specific[0]; // A coarse legacy "camera" tag cannot override an adapter/action/camcorder label.
  }
  if (declaredType && rules[subcategory].some(([type]) => type === declaredType)) return declaredType;
  // A mobility scooter must not inherit the generic electric-scooter type.
  if (subcategory === 'Other vehicles' && /mobility scooter/.test(value)) return 'mobility_scooter';
  return rules[subcategory].find(([, pattern]) => pattern.test(value))?.[0] ?? null;
}

export function normalizeIsbn(value) {
  const isbn = String(value ?? '').replace(/[\s-]/g, '').toUpperCase();
  if (/^\d{9}[\dX]$/.test(isbn)) {
    const sum = [...isbn].reduce((total, digit, index) => total + (digit === 'X' ? 10 : Number(digit)) * (10 - index), 0);
    if (sum % 11 === 0) {
      const prefix = `978${isbn.slice(0, 9)}`;
      const sum13 = [...prefix].reduce((total, digit, index) => total + Number(digit) * (index % 2 ? 3 : 1), 0);
      return `${prefix}${(10 - sum13 % 10) % 10}`;
    }
  }
  if (/^97[89]\d{10}$/.test(isbn) && [...isbn].reduce((sum, digit, index) => sum + Number(digit) * (index % 2 ? 3 : 1), 0) % 10 === 0) return isbn;
  return null;
}

const model = (item) => item.productModel ?? item.product_model ?? '';
const edition = (item) => priceText(item.edition || model(item).match(/\b\d+(?:st|nd|rd|th)?\s+(?:edition|ed)\b/i)?.[0])
  .replace(/\b(\d+)(?:st|nd|rd|th)?(?:\s+(?:edition|ed))?\b/, '$1');
const variant = (item) => item.subcategory === 'Cameras' && item.packageType === 'with_lens' ? ''
  : priceText(item.variant || model(item).match(/\b\d+(?:\.\d+)?\s*(?:gb|tb)\b/i)?.[0]).replace(/\s/g, '');
const packageType = (item) => item.packageType === 'item_only' && item.subcategory === 'Cameras' &&
  productTypeFor(item.category, item.subcategory, `${item.brand ?? ''} ${model(item)}`) === 'camera' ? 'body_only'
  : item.packageType || (/body\s*only/i.test(`${model(item)} ${item.packageNotes ?? ''}`) ? 'body_only'
    : /with (?:a )?lens|\+\s*lens|lens kit|camera kit/i.test(`${model(item)} ${item.packageNotes ?? ''}`) ? 'with_lens' : '');
const bookTitle = (item) => priceText(model(item).replace(/\b\d+(?:st|nd|rd|th)?\s+(?:edition|ed)\b/ig, ''));
const includedLens = (item) => item.subcategory === 'Cameras' && packageType(item) === 'with_lens'
  ? priceText(item.includedLens ?? item.included_lens ?? item.variant ?? '') : '';

// Same-domain constraints apply to both CSV and automatic observations. A valid
// catalogue identity cannot override an explicit edition/variant/package conflict.
export function compatibleProductReference(item, profile) {
  if (item.category !== profile.category || item.subcategory !== profile.subcategory) return false;
  const requestedType = productTypeFor(profile.category, profile.subcategory, `${profile.brand ?? ''} ${model(profile)}`, profile.productType ?? profile.product_type);
  const inferredType = productTypeFor(item.category, item.subcategory, `${item.brand ?? ''} ${model(item)}`, item.productType ?? item.product_type);
  if (!requestedType || !inferredType || requestedType !== inferredType || item.productType && item.productType !== inferredType) return false;
  for (const attribute of [edition, variant]) {
    const offered = attribute(item), requested = attribute(profile);
    if (offered && offered !== requested) return false;
  }
  const offeredPackage = packageType(item), requestedPackage = packageType(profile);
  if (offeredPackage && offeredPackage !== requestedPackage && !(offeredPackage === 'body_only' && !requestedPackage)) return false;
  if (includedLens(item) && includedLens(profile) && includedLens(item) !== includedLens(profile)) return false;
  if (!suitableProductComparison(item, profile)) return false;
  if (item.category === 'Books') {
    if (item.isbn || profile.isbn) {
      const offered = normalizeIsbn(item.isbn), requested = normalizeIsbn(profile.isbn);
      if (!offered || !requested || offered !== requested) return false;
      return true;
    }
    // No author-wide averaging: a publisher's textbook cannot price its fiction.
    return Boolean(priceText(model(profile))) && (Boolean(item.canonicalProductId) && item.canonicalProductId === profile.canonicalProductId ||
      priceText(item.brand) === priceText(profile.brand) && bookTitle(item) === bookTitle(profile));
  }
  return true;
}

export function referencePeriodMatches(item, days) {
  const min = item.durationMinDays ?? item.rentalDurationDays;
  const max = item.durationMaxDays ?? item.rentalDurationDays;
  return Number.isInteger(days) && Number.isInteger(min) && Number.isInteger(max) && min >= 1 && max <= 365 && min <= max && days >= min && days <= max;
}

export function referenceIdentityUncertain(item, profile) {
  return [edition, variant, packageType, includedLens].some((attribute) => Boolean(attribute(item)) !== Boolean(attribute(profile)));
}

export function referenceOfferKey(row) {
  const url = new URL(row.sourceUrl);
  url.hash = '';
  for (const key of [...url.searchParams.keys()]) {
    if (/^utm_|^(?:gclid|fbclid)$/i.test(key)) url.searchParams.delete(key);
  }
  url.searchParams.sort();
  return JSON.stringify([url.hostname.replace(/^www\./, ''), url.pathname.replace(/\/$/, ''), url.search,
    priceText(row.brand), priceText(model(row)), row.isbn ? normalizeIsbn(row.isbn) : '',
    edition(row), variant(row), packageType(row), includedLens(row)]);
}
