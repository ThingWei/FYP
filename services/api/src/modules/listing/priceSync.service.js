import { createHash, randomUUID } from 'node:crypto';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { normalizeCatalogText } from '../catalog/catalog.service.js';
import { searchCuratedCatalog } from '../catalog/catalog.curated.js';
import { ProductCatalogModel } from '../catalog/productCatalog.model.js';
import { PricingReferenceModel } from './pricingReference.model.js';
import { PriceSourceModel } from './priceSource.model.js';
import { PRICE_SOURCES, PRICE_SOURCE_COVERAGE, FUTURE_PRICE_DOMAINS, priceSource, productTypeFor, isAllowedSourceUrl } from './priceSources.registry.js';
import { parsePriceSource } from './priceSource.parsers.js';
import { checkSourceAccess, fetchSourceText, robotsAllows } from './priceSource.transport.js';

const DAY = 86_400_000, LEASE_MS = 10 * 60_000;
const pending = new Set();
let writeAudit = async () => {};
export function configurePriceSyncAudit(writer) { writeAudit = writer; }
const audit = (action, id, metadata, actorId = 'system:price-sync') => writeAudit({
  actorId, createdBy: actorId, action, targetType: 'pricing_source', targetId: id, metadata,
});
const approved = (entry) => Boolean(entry.adapter && env.priceSyncApprovedSources.includes(entry.id));
const reject = (code, status = 400) => { throw new AppError('Rental-price source is not ready for this action', status, code); };
function sourceErrorCode(error) {
  return /^(HTTP_\d{3}|ACCESS_RESTRICTED|NO_VALID_QUOTES|SOURCE_DISABLED_OR_LEASE_LOST|PAGE_TOO_LARGE|PAGE_STRUCTURE_LIMIT|URL_NOT_ALLOWED)$/.test(error?.message)
    ? error.message : 'SOURCE_UNAVAILABLE';
}
function sourceFailure(error) {
  const failure = new AppError('Rental-price source could not be checked or refreshed', 503,
    'PRICE_SOURCE_UNAVAILABLE', { errorCode: sourceErrorCode(error) });
  Object.defineProperty(failure, 'cause', { value: error }); // Never part of the HTTP payload.
  return failure;
}

export async function priceSourcesStatus() {
  const records = await PriceSourceModel.find().select('-_id -__v -leaseToken').lean();
  return { sources: PRICE_SOURCES.map((entry) => {
    const record = records.find((row) => row.sourceId === entry.id) ?? {};
    return { sourceId: entry.id, name: entry.name, urls: entry.urls, domains: entry.domains,
      limitation: entry.limitation, adapterAvailable: Boolean(entry.adapter), accessApproved: approved(entry),
      accessStatus: !entry.adapter ? 'adapter_pending' : approved(entry) ? 'approved_by_maintainer' : 'review_required',
      ...record, enabled: record.enabled === true && approved(entry),
      running: Boolean(record.leaseUntil && record.leaseUntil > new Date()),
    };
  }), coverage: PRICE_SOURCE_COVERAGE, futureDomains: FUTURE_PRICE_DOMAINS,
  schedulerEnabled: env.priceSyncJobsEnabled, intervalHours: 24 };
}

function normalizeQuote(row, entry, url, now) {
  if (!PRICE_SOURCE_COVERAGE.some((domain) => domain.category === row.category && domain.subcategory === row.subcategory && domain.sourceIds.includes(entry.id))) throw new Error('wrong_domain');
  if (!row.productType || !row.productModel || row.productModel.length > 120 || (row.brand ?? '').length > 100) throw new Error('unknown_product_type_or_identity');
  if (row.productType !== productTypeFor(row.category, row.subcategory, `${row.brand ?? ''} ${row.productModel}`)) throw new Error('product_type_mismatch');
  const amount = row.quotedAmount, days = row.rentalDurationDays;
  if (!Number.isFinite(amount) || amount <= 0 || Math.abs(amount * 100 - Math.round(amount * 100)) > 1e-6 ||
    !Number.isInteger(days) || days < 1 || days > 365 || amount / days < 1 || amount / days > 1_000_000) throw new Error('invalid_amount_or_period');
  const min = row.durationMinDays ?? days, max = row.durationMaxDays ?? days;
  if (!Number.isInteger(min) || !Number.isInteger(max) || min < 1 || max > 365 || min > max) throw new Error('invalid_duration_band');
  if (/\bfrom\b|starting|chauffeur|crew included|operator included|setup included|service bundle|\$|USD|SGD/i.test(row.packageNotes ?? '')) throw new Error('ambiguous_or_service_quote');
  const productKey = row.sourceProductKey ?? normalizeCatalogText(`${row.brand ?? ''} ${row.productModel}`);
  const key = createHash('sha256').update(JSON.stringify([entry.id, row.category, row.subcategory,
    productKey, row.productType, min, max])).digest('hex');
  return { observationKey: key, publicId: `pr-${key.slice(0, 32)}`, sourceType: 'external_asking_price',
    collectionMethod: 'automatic', sourceId: entry.id, sourceProductKey: `${row.category}:${row.subcategory}:${row.productType}:${productKey}`,
    category: row.category, subcategory: row.subcategory, brand: row.brand ?? '', productModel: row.productModel,
    productType: row.productType, identityLevel: row.identityLevel,
    quotedAmount: amount, rentalDurationDays: days, dailyPrice: amount / days,
    durationMinDays: min, durationMaxDays: max, currency: 'MYR', country: 'MY',
    sourceName: entry.name, sourceUrl: url, observedAt: now, validatedAt: now,
    parserVersion: entry.parserVersion, validationStatus: 'accepted',
    packageNotes: (row.packageNotes ?? '').slice(0, 500), canonicalProductId: null,
  };
}

export async function collectSourceQuotes(entry, { fetchText = fetchSourceText, now = new Date(), signal } = {}) {
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), 5 * 60_000);
  const stop = () => controller.abort();
  signal?.addEventListener('abort', stop, { once: true });
  if (signal?.aborted) controller.abort();
  const urls = [...entry.urls], rows = [], skipped = [];
  try {
    const policy = await checkSourceAccess(entry, urls, fetchText, controller.signal);
    for (let index = 0; index < urls.length && index < 20; index++) {
      if (controller.signal.aborted) throw new Error('SOURCE_UNAVAILABLE');
      // Avoid burst crawling; fixture transports have no network and need no delay.
      if (index > 0 && fetchText === fetchSourceText) await new Promise((resolve) => setTimeout(resolve, 1000));
      const url = urls[index];
      if (!isAllowedSourceUrl(entry, url) || !robotsAllows(policy, url)) { skipped.push('discovery_access_restricted'); continue; }
      const content = await fetchText(url, controller.signal);
      const parsed = parsePriceSource(entry, content, url);
      skipped.push(...parsed.skipped);
      for (const row of parsed.rows.slice(0, 500)) {
        try { rows.push(normalizeQuote(row, entry, url, now)); } catch (error) { skipped.push(error.message); }
      }
      for (const link of parsed.links) if (urls.length < 20 && !urls.includes(link)) urls.push(link);
    }
    const unique = new Map(), conflicts = new Set();
    for (const row of rows) {
      const old = unique.get(row.observationKey);
      if (old && (old.quotedAmount !== row.quotedAmount || old.packageNotes !== row.packageNotes)) conflicts.add(row.observationKey);
      else unique.set(row.observationKey, row);
    }
    for (const key of conflicts) { unique.delete(key); skipped.push('conflicting_quotes'); }
    return { rows: [...unique.values()].slice(0, 500), skipped, pages: Math.min(urls.length, 20) };
  } finally {
    clearTimeout(deadline);
    signal?.removeEventListener('abort', stop);
  }
}

async function localIdentity(row) {
  if (!row.brand || row.identityLevel !== 'named_product') return null;
  const products = await ProductCatalogModel.find({ entityType: 'product', category: row.category,
    subcategory: row.subcategory, normalizedBrand: normalizeCatalogText(row.brand) }).limit(1000).lean();
  const match = products.find((product) => [product.model, ...(product.aliases ?? [])]
    .some((name) => normalizeCatalogText(name) === normalizeCatalogText(row.productModel)));
  const curated = !match && searchCuratedCatalog({ ...row, entityType: 'product', query: '' })
    .find((product) => normalizeCatalogText(product.label) === normalizeCatalogText(row.productModel));
  return match?.canonicalProductId ?? (curated ? `renthub-curated:${curated.id}` : null);
}

export async function setPriceSourceEnabled(id, enabled, identity, { fetchText = fetchSourceText } = {}) {
  const entry = priceSource(id);
  if (!entry) reject('PRICE_SOURCE_NOT_FOUND', 404);
  if (enabled) {
    if (!approved(entry)) reject('PRICE_SOURCE_REVIEW_REQUIRED', 409);
    let probe;
    try { probe = await collectSourceQuotes(entry, { fetchText }); } // Read-only probe, never inserts prices.
    catch (error) { throw sourceFailure(error); }
    if (!probe.rows.length) reject('PRICE_SOURCE_PARSER_UNAVAILABLE', 409);
  }
  const result = await PriceSourceModel.findOneAndUpdate({ sourceId: id }, { $set: {
    enabled, status: enabled ? 'ready' : 'disabled', errorCode: '',
    ...(enabled && { accessCheckedAt: new Date(), accessCheckedBy: identity.authId, nextRunAt: new Date() }),
  } }, { upsert: true, new: true, setDefaultsOnInsert: true }).lean();
  await audit(enabled ? 'pricing_source.enabled' : 'pricing_source.disabled', id, { enabled }, identity.authId);
  return { sourceId: id, enabled: result.enabled };
}

async function acquire(entry, force, now) {
  if (!approved(entry)) reject('PRICE_SOURCE_REVIEW_REQUIRED', 409);
  const token = randomUUID();
  const record = await PriceSourceModel.findOneAndUpdate({ sourceId: entry.id, enabled: true,
    $and: [
      { $or: [{ leaseUntil: { $exists: false } }, { leaseUntil: { $lte: now } }] },
      ...(force ? [] : [{ $or: [{ nextRunAt: { $exists: false } }, { nextRunAt: { $lte: now } }] }]),
    ],
  }, { $set: { leaseToken: token, leaseUntil: new Date(now.getTime() + LEASE_MS),
    lastAttemptAt: now, status: 'running', errorCode: '' } }, { new: true }).lean();
  return record ? token : null;
}

async function execute(entry, token, { fetchText = fetchSourceText, now = new Date() } = {}) {
  const lease = { sourceId: entry.id, enabled: true, leaseToken: token };
  try {
    const collected = await collectSourceQuotes(entry, { fetchText, now });
    if (!collected.rows.length) throw new Error('NO_VALID_QUOTES');
    let acceptedCount = 0;
    for (const row of collected.rows) {
      if (!await PriceSourceModel.exists({ ...lease, leaseUntil: { $gt: new Date() } })) throw new Error('SOURCE_DISABLED_OR_LEASE_LOST');
      row.canonicalProductId = await localIdentity(row);
      await PricingReferenceModel.updateOne({ observationKey: row.observationKey }, {
        $set: row, $setOnInsert: { active: true },
      }, { upsert: true, runValidators: true }); // active/deactivated fields are never reset on refresh.
      acceptedCount++;
    }
    const result = { acceptedCount, skippedCount: collected.skipped.length,
      skipReasons: [...new Set(collected.skipped)].slice(0, 20) };
    await PriceSourceModel.updateOne(lease, { $set: { ...result, lastSuccessAt: now,
      nextRunAt: new Date(now.getTime() + DAY), status: 'ready', errorCode: '', consecutiveFailures: 0 },
      $unset: { leaseToken: '', leaseUntil: '' } });
    await audit('pricing_source.synced', entry.id, result);
    return result;
  } catch (error) {
    const errorCode = sourceErrorCode(error);
    const record = await PriceSourceModel.findOne(lease).select('consecutiveFailures').lean();
    const failures = (record?.consecutiveFailures ?? 0) + 1;
    await PriceSourceModel.updateOne(lease, { $set: { status: 'error', errorCode,
      consecutiveFailures: failures,
      nextRunAt: new Date(now.getTime() + Math.min(24, 2 ** Math.min(failures - 1, 5)) * 60 * 60_000) }, $unset: { leaseToken: '', leaseUntil: '' } });
    await audit('pricing_source.sync_failed', entry.id, { errorCode });
    throw sourceFailure(error);
  } finally {
    // Disabled during collection: release only this worker's lease, without changing disabled status.
    await PriceSourceModel.updateOne({ sourceId: entry.id, leaseToken: token }, { $unset: { leaseToken: '', leaseUntil: '' } });
  }
}

export async function runPriceSourceSync(id, options = {}) {
  const entry = priceSource(id);
  if (!entry) reject('PRICE_SOURCE_NOT_FOUND', 404);
  const now = options.now ?? new Date();
  const token = await acquire(entry, options.force === true, now);
  if (!token) return { skipped: true };
  const job = execute(entry, token, { ...options, now }).finally(() => pending.delete(job));
  pending.add(job);
  return job;
}

export async function requestPriceSourceSync(id, identity) {
  const entry = priceSource(id);
  if (!entry) reject('PRICE_SOURCE_NOT_FOUND', 404);
  const token = await acquire(entry, true, new Date());
  if (!token) reject('PRICE_SOURCE_BUSY_OR_DISABLED', 409);
  try { await audit('pricing_source.sync_requested', id, {}, identity.authId); }
  catch (error) { await PriceSourceModel.updateOne({ sourceId: id, leaseToken: token }, { $unset: { leaseToken: '', leaseUntil: '' } }); throw error; }
  const job = execute(entry, token).catch(() => {}).finally(() => pending.delete(job));
  pending.add(job);
  return { sourceId: id, status: 'running' };
}
export async function drainPriceSyncJobs() { await Promise.allSettled([...pending]); }

// Only automatic records need these gates. Legacy CSV references retain their existing contract.
export function compatiblePriceReferences(records, profile, enabledSourceIds) {
  const selected = new Map(), type = productTypeFor(profile.category, profile.subcategory, `${profile.brand ?? ''} ${profile.product_model ?? ''}`);
  const duration = profile.rental_duration_days ?? 1;
  for (const row of records) {
    if (row.collectionMethod !== 'automatic') { selected.set(row.publicId, row); continue; }
    if (!enabledSourceIds.includes(row.sourceId) || row.validationStatus !== 'accepted' || !row.validatedAt ||
      row.category !== profile.category || row.subcategory !== profile.subcategory || !type || row.productType !== type ||
      duration < row.durationMinDays || duration > row.durationMaxDays) continue;
    const key = `${row.sourceId}:${row.sourceProductKey}`;
    // One source product contributes once even when multiple periods overlap.
    if (!selected.has(key)) selected.set(key, row);
  }
  return [...selected.values()];
}
export async function enabledPriceSourceIds() {
  const records = await PriceSourceModel.find({ enabled: true }).select('sourceId').lean();
  return records.filter((row) => approved(priceSource(row.sourceId) ?? {})).map((row) => row.sourceId);
}
