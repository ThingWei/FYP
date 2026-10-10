import { createHash } from 'node:crypto';
import { AppError } from '../../core/errors.js';
import { textInput, moneyInput, wholeInput, numericInput } from '../../core/inputValidation.js';
import { CATALOG_COVERAGE } from '../catalog/catalog.coverage.js';
import { searchCuratedCatalog } from '../catalog/catalog.curated.js';
import { ProductCatalogModel } from '../catalog/productCatalog.model.js';
import { normalizeCatalogText } from '../catalog/catalog.service.js';
import { PricingReferenceModel } from './pricingReference.model.js';

export const REFERENCE_COLUMNS = ['category', 'subcategory', 'brand', 'model',
  'quotedAmount', 'rentalDays', 'currency', 'sourceName', 'sourceUrl', 'observedDate',
  'location', 'state', 'condition', 'itemAgeYears', 'packageNotes'];
export const REFERENCE_TEMPLATE = REFERENCE_COLUMNS.join(',') + '\r\n';
const requiredColumns = REFERENCE_COLUMNS.slice(0, 10);
const fail = (message, details) => { throw new AppError(message, 400, 'INVALID_PRICE_CSV', details); };

// Bounded RFC4180-style reader. Quotes are legal only at the start of a field.
export function parseReferenceCsv(csv) {
  if (typeof csv !== 'string' || Buffer.byteLength(csv, 'utf8') > 1_048_576) {
    fail('Choose a UTF-8 CSV file no larger than 1 MB');
  }
  const rows = [];
  let row = [], field = '', quoted = false, closed = false;
  const pushField = () => { row.push(field); field = ''; closed = false; };
  const pushRow = () => {
    pushField();
    if (row.some((value) => value.trim())) rows.push(row);
    row = [];
    if (rows.length > 501) fail('A CSV import may contain at most 500 observations');
  };
  const input = csv.replace(/^\uFEFF/, '');
  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"' && input[i + 1] === '"') { field += '"'; i += 1; }
      else if (ch === '"') { quoted = false; closed = true; }
      else field += ch;
    } else if (ch === '"') {
      if (field || closed) fail('CSV has an incorrectly quoted field');
      quoted = true;
    } else if (ch === ',') pushField();
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && input[i + 1] === '\n') i += 1;
      pushRow();
    } else {
      if (closed) fail('CSV has text after a closing quote');
      field += ch;
    }
  }
  if (quoted) fail('CSV contains an unfinished quoted field');
  if (field || closed || row.length) pushRow();
  if (rows.length < 2) fail('Add at least one rental-price observation');
  const headers = rows.shift().map((value) => value.trim());
  if (new Set(headers).size !== headers.length ||
      headers.some((name) => !REFERENCE_COLUMNS.includes(name)) ||
      requiredColumns.some((name) => !headers.includes(name))) {
    fail('CSV headers must match the downloaded template');
  }
  return rows.map((values, index) => {
    if (values.length !== headers.length) fail(`Row ${index + 2} has the wrong number of columns`);
    return Object.fromEntries(headers.map((name, column) => [name, values[column].trim()]));
  });
}

function cleanText(value, max, required = false) {
  textInput(value ?? '');
  const text = String(value ?? '').trim();
  if (required && !text || [...text].length > max) throw new Error(`Enter ${required ? '1–' : 'up to '}${max} characters`);
  return text;
}

function validatedRow(row) {
  const category = cleanText(row.category, 100, true);
  const subcategory = cleanText(row.subcategory, 100, true);
  if (!CATALOG_COVERAGE.some((entry) => entry.category === category && entry.subcategory === subcategory)) {
    throw new Error('Choose a supported physical-item category and subcategory');
  }
  moneyInput(row.quotedAmount);
  wholeInput(row.rentalDays);
  const quotedAmount = Number(row.quotedAmount), rentalDurationDays = Number(row.rentalDays);
  const dailyPrice = quotedAmount / rentalDurationDays;
  if (rentalDurationDays < 1 || rentalDurationDays > 365 || dailyPrice < 1 || dailyPrice > 1_000_000) {
    throw new Error('Rental days must be 1–365 and the equivalent daily price RM 1–1,000,000');
  }
  if (row.currency !== 'MYR') throw new Error('Only Malaysian MYR observations are supported');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(row.observedDate)) throw new Error('Use YYYY-MM-DD for the observation date');
  const observedAt = new Date(`${row.observedDate}T00:00:00.000Z`);
  if (!Number.isFinite(observedAt.getTime()) || observedAt.toISOString().slice(0, 10) !== row.observedDate ||
      row.observedDate > new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }).format(new Date())) {
    throw new Error('Enter a real observation date that is not in the future');
  }
  const sourceUrl = new URL(cleanText(row.sourceUrl, 1000, true));
  if (sourceUrl.protocol !== 'https:' || sourceUrl.username || sourceUrl.password ||
      /^(localhost|127\.|\[?::1\]?)/i.test(sourceUrl.hostname)) throw new Error('Use a public HTTPS source URL');
  sourceUrl.hash = '';
  const condition = cleanText(row.condition, 30);
  if (condition && !['Fair', 'Good', 'Very good', 'Excellent', 'Like New'].includes(condition)) throw new Error('Condition is not supported');
  const itemAgeYears = row.itemAgeYears ? Number(row.itemAgeYears) : null;
  if (row.itemAgeYears) {
    numericInput(row.itemAgeYears);
    if (itemAgeYears > 100) throw new Error('Item age must be between 0 and 100 years');
  }
  const result = { category, subcategory, brand: cleanText(row.brand, 100, true),
    productModel: cleanText(row.model, 120, true), quotedAmount, rentalDurationDays, dailyPrice,
    currency: 'MYR', country: 'MY', sourceType: 'external_asking_price',
    sourceName: cleanText(row.sourceName, 160, true), sourceUrl: sourceUrl.href, observedAt,
    location: cleanText(row.location, 160), state: cleanText(row.state, 80), condition, itemAgeYears,
    packageNotes: cleanText(row.packageNotes, 500) };
  // Reviews must reject minimum/ambiguous quotes and inseparable event services.
  if (/\b(from|starting|chauffeur|crew|operator|setup included|service bundle)\b/i.test(result.packageNotes)) {
    throw new Error('Exclude minimum prices or inseparable service bundles; enter an explicit equipment rental quote');
  }
  result.observationKey = createHash('sha256').update(JSON.stringify([
    category, subcategory, normalizeCatalogText(result.brand), normalizeCatalogText(result.productModel),
    result.sourceUrl, row.observedDate, rentalDurationDays,
  ])).digest('hex');
  result.publicId = `pr-${result.observationKey.slice(0, 32)}`;
  return result;
}

function sameObservation(a, b) {
  return ['quotedAmount', 'location', 'state', 'condition', 'itemAgeYears', 'packageNotes']
    .every((key) => a[key] === b[key]);
}

export async function previewPricingReferences(csv) {
  const raw = parseReferenceCsv(csv), rows = [], errors = [], seen = new Map();
  let duplicateCount = 0;
  for (const [index, row] of raw.entries()) {
    try {
      const item = validatedRow(row);
      const previous = seen.get(item.observationKey);
      if (previous) {
        if (!sameObservation(previous, item)) throw new Error('Conflicting prices/details for the same observation');
        duplicateCount += 1;
      } else { seen.set(item.observationKey, item); rows.push(item); }
    } catch (error) { errors.push({ row: index + 2, message: error.message }); }
  }
  const existing = await PricingReferenceModel.find({ observationKey: { $in: rows.map((row) => row.observationKey) } }).lean();
  for (const record of existing) {
    const item = seen.get(record.observationKey);
    if (!sameObservation(record, item)) errors.push({ row: raw.findIndex((row) => {
      try { return validatedRow(row).observationKey === record.observationKey; } catch { return false; }
    }) + 2, message: 'This source/date/product already exists with different details; use a new observation date or deactivate the incorrect record' });
  }
  const productGroups = new Map();
  for (const item of rows) {
    const contextKey = JSON.stringify([item.category, item.subcategory, normalizeCatalogText(item.brand)]);
    if (!productGroups.has(contextKey)) productGroups.set(contextKey,
      await ProductCatalogModel.find({ entityType: 'product', category: item.category,
        subcategory: item.subcategory, normalizedBrand: normalizeCatalogText(item.brand) }).limit(1000).lean());
    const products = productGroups.get(contextKey);
    const match = products.find((product) => [product.model, ...(product.aliases ?? [])]
      .some((name) => normalizeCatalogText(name) === normalizeCatalogText(item.productModel)));
    const curated = !match && searchCuratedCatalog({ ...item, entityType: 'product', query: '' })
      .find((product) => normalizeCatalogText(product.label) === normalizeCatalogText(item.productModel));
    item.canonicalProductId = match?.canonicalProductId ?? (curated ? `renthub-curated:${curated.id}` : null);
  }
  return { valid: errors.length === 0, rows, errors, rowCount: raw.length,
    duplicateCount: duplicateCount + existing.length, newCount: rows.length - existing.length };
}

export async function importPricingReferences(csv, identity) {
  const preview = await previewPricingReferences(csv);
  if (!preview.valid) fail('Fix CSV errors before importing', preview.errors);
  let imported = 0;
  for (const row of preview.rows) {
    try {
      const result = await PricingReferenceModel.updateOne({ observationKey: row.observationKey }, {
        $setOnInsert: { ...row, active: true, reviewedBy: identity.authId, reviewedAt: new Date() },
      }, { upsert: true });
      imported += result.upsertedCount;
    } catch (error) {
      if (error.code !== 11000) throw error; // Concurrent duplicate import is safe to retry.
    }
    const persisted = await PricingReferenceModel.findOne({ observationKey: row.observationKey }).lean();
    if (!sameObservation(persisted, row)) throw new AppError('A conflicting import was saved concurrently', 409, 'PRICE_REFERENCE_CONFLICT');
  }
  return { imported, duplicates: preview.rows.length - imported + preview.rowCount - preview.rows.length };
}
