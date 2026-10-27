import { CURATED_CATALOG } from '../catalog/catalog.curated.js';
import { isAllowedSourceUrl, productTypeFor } from './priceSources.registry.js';

export function decodeHtml(value) {
  const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”' };
  return String(value).replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (all, entity) => {
    if (entity[0] !== '#') return named[entity.toLowerCase()] ?? all;
    const code = entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '';
  });
}

// Small bounded, non-executing HTML reader. No JS, CSS, image or linked resource fetching.
export function readHtml(html) {
  if (typeof html !== 'string' || Buffer.byteLength(html) > 2_097_152) throw new Error('PAGE_TOO_LARGE');
  const root = { tag: 'root', attrs: {}, children: [] }, stack = [root];
  const clean = html.replace(/<(script|style|svg)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '').replace(/<!--[\s\S]*?-->/g, '');
  let nodes = 0;
  for (const part of clean.matchAll(/<[^>]*>|[^<]+/g)) {
    const token = part[0];
    if (++nodes > 80000 || stack.length > 100) throw new Error('PAGE_STRUCTURE_LIMIT');
    if (!token.startsWith('<')) { stack.at(-1).children.push(decodeHtml(token)); continue; }
    const close = token.match(/^<\/\s*([\w-]+)/);
    if (close) {
      const index = stack.findLastIndex((node) => node.tag === close[1].toLowerCase());
      if (index > 0) stack.length = index;
      continue;
    }
    const open = token.match(/^<\s*([\w-]+)/);
    if (!open) continue;
    const tag = open[1].toLowerCase(), attrs = {};
    for (const attr of token.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) attrs[attr[1].toLowerCase()] = decodeHtml(attr[2] ?? attr[3]);
    const node = { tag, attrs, children: [] };
    stack.at(-1).children.push(node);
    if (!/\/$/.test(token.slice(0, -1)) && !['br', 'hr', 'img', 'input', 'meta', 'link', 'source', 'wbr'].includes(tag)) stack.push(node);
  }
  return root;
}
export const textOf = (node) => typeof node === 'string' ? node : node.children.map(textOf).join(' ').replace(/\s+/g, ' ').trim();
export function findNodes(node, predicate) {
  const output = [];
  const visit = (item) => {
    if (typeof item === 'string') return;
    if (predicate(item)) output.push(item);
    item.children.forEach(visit);
  };
  visit(node);
  return output;
}
const hasClass = (node, value) => (node.attrs.class ?? '').split(/\s+/).includes(value);
const tagged = (node, tag) => findNodes(node, (entry) => entry.tag === tag);
const classed = (node, name) => findNodes(node, (entry) => hasClass(entry, name));
const keyText = (value) => String(value).normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const brands = [...new Set([...CURATED_CATALOG.map((row) => row.brand),
  'Casio', 'NEC', 'Panasonic', 'Maono', 'Boya', 'Motorola', 'Hollyland', 'Blackmagic',
  'Modenas', 'SYM', 'Benelli', 'Cannondale', 'Cube', 'Polygon', 'Lapierre', 'Santa Cruz', 'Eurohit',
])].sort((a, b) => b.length - a.length);

function identity(label, { brand = '', specification = false } = {}) {
  if (!brand && !specification) brand = brands.find((name) => keyText(label).startsWith(keyText(name) + ' ')) ?? '';
  const model = brand && keyText(label).startsWith(keyText(brand) + ' ') ? label.slice(brand.length).trim() : label;
  return { brand, productModel: model, identityLevel: brand && !specification ? 'named_product' : 'specification_only' };
}

function quote(label, category, subcategory, amount, days = 1, extras = {}) {
  const productType = extras.productType ?? productTypeFor(category, subcategory, label);
  return { category, subcategory, ...identity(label, extras), productType,
    quotedAmount: amount, rentalDurationDays: days, durationMinDays: days, durationMaxDays: days,
    packageNotes: '', ...extras };
}
const money = (text) => {
  const match = String(text).match(/^RM\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)$/i);
  return match ? Number(match[1].replaceAll(',', '')) : NaN;
};

function rentism(root) {
  const rows = [];
  let maker = '';
  for (const node of tagged(root, 'p')) {
    const line = textOf(node);
    const heading = brands.find((brand) => new RegExp(`^${brand}(?: Body| Lens)?$`, 'i').test(line));
    if (heading) maker = heading;
    const match = line.match(/^(.+?)\s+RM\s*(\d+(?:\.\d{1,2})?)\s*\/\s*(?:(\d+)\s*)?day(?:s)?(?:\s*\([^)]*\))?$/i);
    if (!match || /from|promo|combo|with.*lens|\+|battery|charger|cable|filter|card|tripod|\bor\b/i.test(match[1])) continue;
    let label = match[1].replace(/\s*\((?:body only|black|wire|wireless)\)\s*/gi, ' ').trim();
    let subcategory;
    if (/Samsung S\d|Galaxy|iPhone/i.test(label)) subcategory = 'Smartphones';
    else if (/microfone|microphone/i.test(label)) subcategory = 'Audio';
    else if (/walkie|video capture|atem|mars 400/i.test(label)) subcategory = 'Other devices';
    else if (/godox.*sk\d|lighting|video light/i.test(label)) subcategory = 'Event equipment';
    else if (/\b(?:ef|rf|fe|af-s|af-p)\b.*\d.*mm|\blens\b|\beos\b|\bd\d{3,4}\b|\bnikon z\d|\bsony (?:alpha|a[679]|fdr|hxr|pxw)|\bfujifilm x[- ]|go\s?pro|insta360|osmo pocket/i.test(label)) subcategory = 'Cameras';
    else continue;
    if (maker && /^(?:EOS |D\d|Z\d|Alpha )/i.test(label)) label = `${maker} ${label}`;
    rows.push(quote(label, subcategory === 'Event equipment' ? 'Equipment' : 'Devices', subcategory,
      Number(match[2]), Number(match[3] ?? 1), { packageNotes: /body only/i.test(line) ? 'Body only; lens excluded.' : 'Published item/set rental; deposit and fulfilment charges excluded.' }));
  }
  return rows;
}

function rentalGuy(root) {
  return classed(root, 'trg-catalogue-card').flatMap((card) => {
    const label = textOf(classed(card, 'trg-product-heading')[0] ?? ''), price = textOf(classed(card, 'trg-reference-price')[0] ?? '');
    if (!/^One-day reference:\s*RM/i.test(price)) return [];
    return [quote(label, 'Equipment', 'Event equipment', money(price.replace(/^One-day reference:\s*/i, '')),
      1, { specification: true, packageNotes: `${textOf(classed(card, 'trg-product-description')[0] ?? '').slice(0, 300)} Before applicable tax; delivery/setup quoted separately.` })];
  });
}

function goritta(root) {
  const rows = [];
  // A section-local rental period and item-local amount are both mandatory.
  // Retail product links are never followed or treated as rental-price evidence.
  for (const section of classed(root, 'advc-carousel-images-with-text')) {
    const heads = classed(section, 'advc-carousel-images-with-text__head');
    if (heads.length !== 1 || !/^Tents\s+Fee covers up to 4 days of usage$/i.test(textOf(heads[0]))) continue;
    for (const card of classed(section, 'advc-carousel-images-with-text__item')) {
      if (/\b(?:maintenance|unavailable|sold out|out of stock|reserved|from|starting|bundle|setup|operator|crew|installation)\b/i.test(textOf(card))) continue;
      const titles = classed(card, 'advc-carousel-images-with-text__item-title');
      const descriptions = classed(card, 'advc-carousel-images-with-text__item-description');
      if (titles.length !== 1 || descriptions.length !== 1) continue;
      const label = textOf(titles[0]), description = textOf(descriptions[0]);
      if (!label || label.length > 120 || (description.match(/\bRM\s*\d/gi) ?? []).length !== 1 ||
          /\b(?:USD|SGD|MYR)|\$|\b(?:deposit|retail|buy|sale|delivery included|service included)\b/i.test(description)) continue;
      const price = description.match(/^(.*?)\b(RM\s*\d+(?:,\d{3})*(?:\.\d{1,2})?)$/i);
      if (!price || /[~–—-]\s*$/.test(price[1])) continue;
      const brand = ['Mobi Garden', 'DOD', 'KZM'].find((name) => keyText(label).startsWith(keyText(name) + ' '));
      if (!brand || productTypeFor('Equipment', 'Sports equipment', label) !== 'camping_tent') continue;
      rows.push(quote(label, 'Equipment', 'Sports equipment', money(price[2]), 4, {
        brand, productType: 'camping_tent',
        // Preserve the colour/version in the source's title, rather than making
        // a retail URL or inferred model into a canonical catalogue ID.
        sourceProductKey: keyText(label),
        packageNotes: `Tent only; advertised package covers up to 4 days. Compared at the full four-day period only. Pickup/return at Goritta, Tebrau City Junction. ${price[1].trim().slice(0, 180)} Other charges not established.`,
      }));
    }
  }
  return rows;
}

function pcRent(root) {
  return tagged(root, 'tr').filter((row) => /^Daily\b/.test(textOf(row))).flatMap((row) => tagged(row, 'td').flatMap((cell) => {
    const match = textOf(cell).match(/^RM\s*(\d+(?:\.\d{1,2})?)\s+(\d+) ANSI Lumens$/i);
    return match ? [quote(`Projector ${match[2]} ANSI lumens`, 'Equipment', 'Event equipment', Number(match[1]), 1,
      { specification: true, packageNotes: 'Specification-only published daily rate; current model and terms require confirmation.' })] : [];
  }));
}

function itpa(root) {
  return classed(root, 'rental-rate-table').flatMap((table) => tagged(table, 'tr').flatMap((row) => {
    const cells = tagged(row, 'td').map(textOf);
    if (cells.length !== 3 || !/RM\s*[\d.]+\s*\/ unit \/ day$/i.test(cells[2])) return [];
    return [quote(cells[0], 'Devices', 'Computers', money(cells[2].replace(/\s*\/ unit \/ day$/i, '')), 1,
      { packageNotes: `${cells[1]}; on-site use; delivery/setup excluded.` })];
  }));
}

function cilt(root) {
  const rows = [];
  // Each heading's parent encloses that console's packages, preventing cross-console attribution.
  for (const panel of findNodes(root, (node) => node.tag === 'div' && node.children.some((child) => typeof child !== 'string' && child.tag === 'h3' && /PlayStation/i.test(textOf(child))))) {
    const label = textOf(panel.children.find((child) => typeof child !== 'string' && child.tag === 'h3'));
    for (const block of tagged(panel, 'div')) {
      const fields = block.children.filter((child) => typeof child !== 'string' && child.tag === 'p').map(textOf);
      const days = { Daily: 1, '3-Day': 3, Weekly: 7 }[fields[0]];
      if (!days || fields.length < 2) continue;
      rows.push(quote(label, 'Devices', 'Gaming', money(fields[1]), days,
        { brand: 'Sony', productModel: label, packageNotes: 'Console with controller, HDMI and power cables; refundable deposit and delivery excluded.' }));
    }
  }
  return rows;
}

function drivor(root) {
  const title = tagged(root, 'h5').map(textOf).find((label) => /^Day based pricing\s*:/i.test(label));
  if (!title) return [];
  const label = title.replace(/^Day based pricing\s*:\s*(?:Private:\s*)?/i, '');
  if (/\b(?:van|bus|lorry|truck|hiace|starex|alphard|vellfire)\b/i.test(label)) return [];
  return classed(root, 'day-ranges-pricing-plan').flatMap((block) => {
    const match = textOf(block).match(/^(\d+)\s*-\s*(\d+) days\s*:\s*RM\s*(\d+(?:\.\d{1,2})?)\s*\/ Day$/i);
    if (!match) return [];
    return [quote(label, 'Vehicles', 'Cars', Number(match[3]) * Number(match[1]), Number(match[1]),
      { durationMinDays: Number(match[1]), durationMaxDays: Number(match[2]),
        packageNotes: `Daily quote applies to ${match[1]}–${match[2]} days. ${textOf(root).match(/\d+\s*km\s*(?:\/|per)\s*day/i)?.[0] ?? 'Mileage restrictions apply'}; deposit, fuel and extras excluded.` })];
  });
}

function alquiler(content) {
  return [...content.matchAll(/^###\s+(.+?)\s+-\s+MYR\s+(\d+(?:\.\d{1,2})?)\/day[^\n]*\n([\s\S]*?)(?=^###|^## |$(?![\s\S]))/gm)].flatMap((match) => {
    const link = match[3].match(/^URL:\s*(https:\/\/alquilermotorbike\.com\/fleet\/[a-z0-9-]+)/m)?.[1];
    if (!link) return [];
    return [quote(match[1], 'Vehicles', 'Motorcycles', Number(match[2]), 1,
      { sourceProductKey: new URL(link).pathname, packageNotes: 'Published motorcycle daily rental; deposit, fuel and gear excluded.' })];
  });
}

function ecocana(root) {
  return classed(root, 'product-layout').flatMap((card) => {
    const description = textOf(classed(card, 'description')[0] ?? '');
    if (!/^Rent \(Daily\) - /i.test(description)) return [];
    const label = textOf(tagged(card, 'h4')[0] ?? ''), price = textOf(classed(card, 'price-new')[0] ?? '');
    if (!/bicycle|bike/i.test(label)) return [];
    return [quote(label, 'Vehicles', 'Bicycles', money(price), 1, { packageNotes: 'Published daily bicycle rental; specification/size and collection terms apply.' })];
  });
}

function jomrent(root) {
  const headings = findNodes(root, (node) => ['h3', 'h4'].includes(node.tag)).map(textOf).filter((label) => !/^\[/.test(label)), rows = [];
  // Detailed sections contain duplicates and can contradict the catalogue. Reject these, not choose a convenient price.
  for (let i = 0; i < headings.length - 1; i++) {
    const label = headings[i].replace(/^Rent /i, ''), match = headings[i + 1].match(/^RM\s*(\d+(?:\.\d{1,2})?)\s*\/\s*(24 Hours|2 days)$/i);
    if (!match || /\+|\bor\b|only.*sell|detergent|bottle|\bcord\b|nozzle|trolley|brush/i.test(label)) continue;
    const subcategory = /drill|ladder/i.test(label) ? 'Tools' : 'Other equipment';
    rows.push(quote(label, 'Equipment', subcategory, Number(match[1]), /2 days/i.test(match[2]) ? 2 : 1,
      { packageNotes: 'Equipment-only quote; deposit, detergent and delivery excluded.' }));
  }
  // If a named product appears elsewhere followed by a different explicit price, quarantine all its quotes.
  const paragraphs = tagged(root, 'p').map(textOf);
  return rows.filter((row) => !paragraphs.some((label, index) => keyText(label) === keyText(`${row.brand} ${row.productModel}`) &&
    /^RM\s*[\d.]+\s*\/\s*24 (hours|jam)/i.test(paragraphs[index + 1] ?? '') &&
    Number((paragraphs[index + 1].match(/[\d.]+/) ?? [])[0]) !== row.quotedAmount));
}

function partymix(root) {
  return tagged(root, 'li').filter((node) => hasClass(node, 'product')).flatMap((card) => {
    const label = textOf(classed(card, 'woocommerce-loop-product__title')[0] ?? '');
    const period = label.match(/\[\s*Rental for (\d+) days?\s*\]/i);
    const price = classed(card, 'price')[0];
    if (!period || !price) return [];
    // This source explicitly separates "plus deposit of" from the rental fee.
    // Accept only the complete known layout; never take the first number from a range.
    const rental = textOf(price).match(/^RM\s*(\d+(?:\.\d{1,2})?)\s+plus deposit of RM\s*\d+(?:\.\d{1,2})?\s*\/\s*(\d+) days?$/i);
    if (!rental || Number(rental[2]) !== Number(period[1])) return [];
    const subcategory = /traditional|hanfu|kurta|sherwani|baju/i.test(label) ? 'Traditional wear'
      : /formal|blazer|suit|tuxedo/i.test(label) ? 'Formal wear' : 'Costumes';
    return [quote(label.replace(period[0], '').trim(), 'Clothing', subcategory, Number(rental[1]), Number(period[1]),
      { specification: true, packageNotes: 'Garment/set rental; refundable deposit excluded; source title retained, manufacturer unknown.' })];
  });
}

function futago(root) {
  const rows = [];
  for (const li of tagged(root, 'li')) {
    const text = textOf(li), match = text.match(/^01 Winter clothing.*?RM\s*(\d+(?:\.\d{1,2})?)\s*(\d+) days \/ item/i);
    if (match) rows.push(quote('Winter clothing', 'Clothing', 'Other clothing', Number(match[1]), Number(match[2]),
      { specification: true, packageNotes: 'Per winter garment; cleaning, delivery and refundable deposit excluded; not a brand/model quote.' }));
  }
  return rows;
}

function irent(root) {
  // A category-page "From" price is never evidence. Read the product's own
  // server-rendered duration table, not scripts, checkout totals or related cards.
  const summary = classed(root, 'entry-summary')[0];
  if (!summary || !/\bCategory:\s*Smartphone Rental\b/i.test(textOf(classed(summary, 'product_meta')[0] ?? ''))) return [];
  const label = textOf(classed(summary, 'product_title')[0] ?? '').replace(/\s+(?:phone\s+)?rental$/i, '').trim();
  if (!label || /\+|\bbundle\b|\bcombo\b|\bset of\b/i.test(label)) return [];
  const rows = [];
  for (const panel of classed(summary, 'irent-discount-table-wrapper')) {
    if (textOf(tagged(panel, 'h4')[0] ?? '') !== 'Rental Pricing Tiers') continue;
    for (const tr of tagged(panel, 'tr')) {
      const cells = tagged(tr, 'td').map(textOf);
      if (cells.length !== 3) continue;
      const duration = cells[0].match(/^(\d+)(?:\s*[-–]\s*(\d+))?\s*Days?$/i);
      const rate = cells[2].match(/^RM\s*(\d+(?:\.\d{1,2})?)\s*\/\s*day$/i);
      if (!duration || !rate) continue; // 31+ Days (Yearly) is deliberately ambiguous.
      const min = Number(duration[1]), max = Number(duration[2] ?? duration[1]);
      if (min < 1 || max > 365 || min > max) continue;
      rows.push(quote(label, 'Devices', 'Smartphones', Math.round(Number(rate[1]) * min * 100) / 100, min,
        { durationMinDays: min, durationMaxDays: max,
          packageNotes: `Explicit daily tier for ${min}-${max} days; deposit and collection/delivery charges excluded. Source stock-substitution terms apply.` }));
    }
  }
  if (rows.some((a, i) => rows.some((b, j) => i !== j && a.durationMinDays <= b.durationMaxDays && b.durationMinDays <= a.durationMaxDays &&
      (a.durationMinDays !== b.durationMinDays || a.durationMaxDays !== b.durationMaxDays)))) return [];
  return rows;
}

function twelveRent(root) {
  const titles = tagged(root, 'h3').map(textOf).filter((title) => /^\[RENTAL\]/i.test(title));
  if (!titles.length) return [];
  return tagged(root, 'ul').flatMap((ul) => {
    const fields = new Map();
    for (const li of ul.children.filter((node) => typeof node !== 'string' && node.tag === 'li')) {
      const pair = textOf(li).match(/^(Status|Brand|Model|Type|Lease Term|Lease Rate|Minimum Rental Period):\s*(.+)$/i);
      if (!pair) continue;
      const key = pair[1].toLowerCase();
      if (fields.has(key) && fields.get(key) !== pair[2]) return [];
      fields.set(key, pair[2]);
    }
    if (fields.get('status') !== 'Rental' || !/^Daily\s*\(DL\)$/i.test(fields.get('lease term') ?? '')) return [];
    const rate = (fields.get('lease rate') ?? '').match(/^RM\s*(\d+(?:\.\d{1,2})?)\s+DL$/i);
    const minimum = (fields.get('minimum rental period') ?? '').match(/^(\d+)\s+Days?$/i);
    const brand = fields.get('brand'), model = fields.get('model'), type = fields.get('type');
    if (!rate || !minimum || !brand || !model || !type) return [];
    const days = Number(minimum[1]), label = `${brand} ${model}`;
    if (days < 1 || days > 365 || /\+|\bbundle\b|operator|crew/i.test(type) ||
        !titles.some((title) => keyText(title).includes(keyText(label)))) return [];
    const productType = productTypeFor('Equipment', 'Tools', `${label} ${type}`);
    return [quote(label, 'Equipment', 'Tools', Math.round(Number(rate[1]) * days * 100) / 100, days,
      { brand, productModel: model, productType,
        packageNotes: `Daily lease rate; minimum ${days} days. Only the minimum-period quote is captured; refundable deposit, consumables and shipping excluded.` })];
  });
}

const parsers = { rentism, itpa, cilt, drivor, ecocana, goritta, 'rental-guy': rentalGuy,
  'pc-rent': pcRent, jomrent, partymix, futago, irent, '12rent': twelveRent };

// Research-only extension. Deliberately absent from the live registry/allowlist.
// A source's event-equipment approval does not onboard a new camping page.
export function parseCampingResearchPreview(content) {
  const root = readHtml(content), rows = [];
  let label = '';
  for (const node of findNodes(root, (n) => ['h2', 'h3', 'p'].includes(n.tag))) {
    const text = textOf(node);
    if (node.tag === 'h2' || node.tag === 'h3') { label = node.tag === 'h3' ? text : ''; continue; }
    if (!/\btent\b/i.test(label) || /bundle|canopy|marquee|\bwith\b|\+/i.test(label)) continue;
    const rate = text.match(/^One.day reference:\s*RM\s*(\d+(?:\.\d{1,2})?)$/i);
    if (!rate) continue;
    rows.push(quote(label, 'Equipment', 'Sports equipment', Number(rate[1]), 1, {
      specification: true, productType: 'camping_tent',
      packageNotes: /before (?:applicable )?tax/i.test(textOf(root)) ? 'One-day reference before tax; date-specific final quote not collected.'
        : 'One-day reference; additional charges unspecified.',
    }));
    label = '';
  }
  return { rows, diagnosticOnly: true, reusePermissionEstablished: false, enabled: false };
}

export function parsePriceSource(entry, content, url = entry.urls[0]) {
  if (!entry.adapter) return { rows: [], skipped: ['adapter_pending'], links: [] };
  const root = readHtml(content);
  const rows = entry.id === 'alquiler' ? alquiler(content) : parsers[entry.adapter](root);
  const discover = entry.discovery && (!entry.discoveryFrom || entry.discoveryFrom.test(new URL(url).pathname));
  const links = discover ? tagged(root, 'a').map((node) => {
    try { return new URL((node.attrs.href ?? '').trim(), url).href; } catch { return ''; }
  }).filter((link) => isAllowedSourceUrl(entry, link)) : [];
  return { rows, links: [...new Set(links)].slice(0, 20), skipped: rows.length ? [] : ['no_supported_quotes_or_layout_changed'] };
}
