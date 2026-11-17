import { createHash, randomUUID } from 'node:crypto';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { aiClient } from '../../integrations/aiClient.js';
import { ListingModel } from './listing.model.js';
import { UploadAssetModel } from '../upload/upload.model.js';
import { uploadService } from '../upload/upload.service.js';
import { catalogItemType } from '../catalog/catalog.itemType.js';
import { ItemVisionJobModel, ItemVisionBudgetModel } from './itemVision.model.js';

export const VISION_CONTRACT = 'renthub-item-vision-v3';
export const VISION_MODEL = 'gemini-3.1-flash-lite';
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const allowedReasons = new Set(['not_enabled', 'not_configured', 'invalid_photos', 'invalid_response',
  'quota', 'provider_busy', 'provider_unavailable', 'timeout', 'not_assessed', 'sensitive_content', 'budget', 'rate_limit']);

async function configurationProblem() {
  if (!env.geminiItemReviewEnabled) return 'not_enabled';
  const configuration = await aiClient.itemVisionStatus();
  if (configuration?.unavailable || configuration?.contract !== VISION_CONTRACT) return 'provider_unavailable';
  if (configuration.enabled !== true) return 'not_enabled';
  if (configuration.configured !== true || configuration.model !== VISION_MODEL) return 'not_configured';
  return null;
}

async function snapshot(listing) {
  if (listing.deletedAt || listing.listingType !== 'physical' || !Array.isArray(listing.images) || listing.images.length < 3) return null;
  const ids = listing.images.map(ref => typeof ref === 'string' && /^(?:upload:\/\/|\/api\/v1\/uploads\/(?:public\/)?)UPL-[A-Z0-9]+(?:\/content)?$/i.test(ref)
    ? ref.match(/UPL-[A-Z0-9]+/i)[0] : null);
  if (ids.some(id => !id)) return null; // No arbitrary URL retrieval or legacy local fixtures.
  const assets = await UploadAssetModel.find({ publicId: { $in: ids }, uploadedBy: listing.ownerId,
    purpose: 'listing_image', contentType: { $in: ['image/jpeg', 'image/png', 'image/webp'] }, size: { $lte: 10 * 1024 * 1024 } })
    .select('publicId sha256').lean();
  const byId = new Map(assets.map(row => [row.publicId, row.sha256]));
  if (ids.some(id => !byId.has(id))) return null;
  const productType = await catalogItemType(listing);
  return { key: digest([listing.ownerId, listing.category, listing.subcategory ?? '', listing.condition ?? '',
    listing.brand ?? '', listing.productModel ?? '', productType, VISION_CONTRACT, ids.map(id => byId.get(id))]), productType };
}
const jobId = (listing, key) => digest([listing.publicId, key, VISION_CONTRACT, VISION_MODEL]);

export function cleanVisionResult(value, count) {
  if (value?.contract !== VISION_CONTRACT) return { state: 'unavailable', reason: 'invalid_response' };
  if (value.state !== 'ready') return { state: 'unavailable', reason: allowedReasons.has(value.reason) ? value.reason : 'provider_unavailable' };
  if (value.model !== VISION_MODEL) return { state: 'unavailable', reason: 'invalid_response' };
  const row = value.observations;
  const choices = {
    item_consistency: ['consistent', 'inconsistent', 'cannot_assess'], photo_consistency: ['consistent', 'inconsistent', 'cannot_assess'],
    visible_condition: ['no_obvious_damage', 'visible_wear', 'visible_damage', 'cannot_assess'],
    visible_branding: ['consistent', 'inconsistent', 'not_readable', 'not_applicable'],
  };
  if (!row || Object.entries(choices).some(([key, values]) => !values.includes(row[key])) || row.sensitive_content !== false) {
    return { state: 'unavailable', reason: row?.sensitive_content ? 'sensitive_content' : 'invalid_response' };
  }
  const result = { ...Object.fromEntries(Object.keys(choices).map(key => [key, row[key]])), sensitive_content: false };
  const safeText = text => typeof text === 'string' && text.trim().length > 0 && text.length <= 180 &&
    !/https?:\/\/|\S+@\S+|\d{6,}|\b(authentic|genuine|counterfeit|stolen|legitimate|ownership|verified|functional)\b/i.test(text);
  const validPhoto = photo => Number.isInteger(photo) && photo >= 1 && photo <= count;
  if (!Array.isArray(row.photo_findings) || row.photo_findings.length !== count ||
    new Set(row.photo_findings.map(f => f?.photo)).size !== count || row.photo_findings.some(f => !validPhoto(f?.photo) ||
      !['assessed', 'cannot_assess'].includes(f.status) || !Array.isArray(f.observations) || f.observations.length < 1 || f.observations.length > 3 ||
      !Array.isArray(f.concerns) || f.concerns.length > 3 || f.status === 'cannot_assess' && f.concerns.length > 0 ||
      [...f.observations, ...f.concerns].some(text => !safeText(text))) ||
    !Array.isArray(row.set_findings) || row.set_findings.length > 5 || row.set_findings.some(f =>
      !Array.isArray(f?.photos) || f.photos.length < 2 || f.photos.length > count || new Set(f.photos).size !== f.photos.length ||
      f.photos.some(photo => !validPhoto(photo)) || !['observation', 'concern'].includes(f.kind) || !safeText(f.observation))) {
    return { state: 'unavailable', reason: 'invalid_response' };
  }
  result.photo_findings = row.photo_findings.map(f => ({ photo: f.photo, status: f.status,
    observations: f.observations.map(text => text.trim()), concerns: f.concerns.map(text => text.trim()) })).sort((a, b) => a.photo - b.photo);
  result.set_findings = row.set_findings.map(f => ({ photos: [...f.photos], kind: f.kind, observation: f.observation.trim() }));
  // Older administrators still receive photo-scoped fields, never set-wide notes attributed to one photo.
  result.concerns = result.photo_findings.flatMap(f => f.concerns.map(observation => ({ photo: f.photo, observation }))).slice(0, 10);
  result.observations = result.photo_findings.flatMap(f => f.observations.map(observation => ({ photo: f.photo, observation }))).slice(0, 10);
  return { state: 'ready', authenticityVerified: false, observations: result };
}

export async function itemVisionSummary(listing, { checkConfiguration = true } = {}) {
  if (listing.listingType !== 'physical' || listing.deletedAt) return null;
  const current = await snapshot(listing);
  if (!current) return { state: 'unavailable', reason: 'invalid_photos', canRequest: false };
  const job = await ItemVisionJobModel.findById(jobId(listing, current.key)).lean();
  const reviewKey = jobId(listing, current.key);
  if (job?.state === 'ready') return { ...cleanVisionResult({ contract: VISION_CONTRACT, model: job.model, ...job.result }, listing.images.length),
    checkedAt: job.checkedAt, reviewKey, canRequest: false,
    availability: env.geminiItemReviewEnabled ? { checked: false } : { ready: false, reason: 'not_enabled' } };
  const problem = checkConfiguration ? await configurationProblem()
    : env.geminiItemReviewEnabled ? null : 'not_enabled';
  const availability = { ready: !problem, ...(problem && { reason: problem }) };
  if (problem) return { state: 'unavailable', reason: problem, availability, reviewKey, canRequest: false };
  // Old configuration failures describe the previous attempt, not today's settings.
  const recovered = ['not_enabled', 'not_configured'].includes(job?.reason);
  const state = !job || recovered || job.state === 'stale' ? 'unavailable' : job.state;
  let allowance;
  let reason = !job || recovered || job.state === 'stale' ? 'not_checked' : job.reason;
  if (reason === 'budget') {
    const budget = await ItemVisionBudgetModel.findById('gemini-item-review').select('day used').lean();
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const used = budget?.day === today ? budget.used : 0;
    if (used >= env.geminiItemReviewDailyLimit) {
      allowance = { source: 'renthub', used, limit: env.geminiItemReviewDailyLimit,
        resetsAt: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString() };
    } else {
      reason = 'rate_limit'; // A queued job can retain yesterday's reason until the worker revisits it.
    }
  }
  return { state, reviewKey, reason, ...(allowance && { allowance }),
    checkedAt: job?.checkedAt, availability,
    canRequest: listing.status !== 'draft' && state === 'unavailable' && !['invalid_photos', 'sensitive_content'].includes(job?.reason) };
}

export async function enqueueItemVision(listing, { retry = false, interactive = false } = {}) {
  const current = await snapshot(listing);
  if (!current || listing.listingType !== 'physical') return itemVisionSummary(listing, { checkConfiguration: false });
  const id = jobId(listing, current.key);
  try {
    await ItemVisionJobModel.updateOne({ _id: id }, { $setOnInsert: { listingId: listing.publicId, snapshot: current.key,
      model: VISION_MODEL, promptVersion: VISION_CONTRACT, state: env.geminiItemReviewEnabled ? 'queued' : 'unavailable',
      reason: env.geminiItemReviewEnabled ? undefined : 'not_enabled', nextAt: new Date(), attempts: 0 } }, { upsert: true });
  } catch (error) { if (error.code !== 11000) throw error; }
  if (interactive) await ItemVisionJobModel.updateOne({ _id: id, state: 'queued' }, { $set: { priority: 1 } });
  if (retry && env.geminiItemReviewEnabled) await ItemVisionJobModel.updateOne({ _id: id, state: 'unavailable' },
    { $set: { state: 'queued', attempts: 0, priority: interactive ? 1 : 0, nextAt: new Date() }, $unset: { reason: 1 } });
  return itemVisionSummary(listing, { checkConfiguration: false });
}
export async function retryItemVision(id, intent = 'retry') {
  const listing = await ListingModel.findOne({ publicId: id });
  if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
  if (listing.deletedAt || listing.listingType !== 'physical' || listing.status === 'draft') throw new AppError('Submit an item listing before requesting review', 409, 'ITEM_REVIEW_NOT_AVAILABLE');
  const current = await itemVisionSummary(listing, { checkConfiguration: false });
  if (current?.state === 'ready') return current;
  const problem = await configurationProblem();
  if (problem) return { state: 'unavailable', reason: problem, canRequest: false, availability: { ready: false, reason: problem } };
  return enqueueItemVision(listing, { retry: intent === 'retry' || current?.reason === 'not_checked', interactive: true });
}

let running = false;
let recoveryCursor;
export async function reconcileItemVisionJobs() {
  if (!env.geminiItemReviewEnabled || await configurationProblem()) return;
  const rows = await ListingModel.find({ status: 'pending_review', listingType: 'physical',
    deletedAt: null, ...(recoveryCursor && { _id: { $gt: recoveryCursor } }) })
    .sort({ _id: 1 }).limit(20);
  recoveryCursor = rows.at(-1)?._id;
  for (const row of rows) {
    const current = await snapshot(row);
    const previous = current && await ItemVisionJobModel.findById(jobId(row, current.key)).select('reason').lean();
    await enqueueItemVision(row, { retry: ['not_enabled', 'not_configured'].includes(previous?.reason) });
  }
  // This repairs submission/job-write interruptions while recovering configuration-only failures.
}
export async function runItemVisionJob(now = new Date()) {
  if (running || !env.geminiItemReviewEnabled) return;
  running = true;
  let job, quota;
  const token = randomUUID();
  try {
    // A crashed in-flight request may already have consumed provider quota. Do not blindly resend it.
    await ItemVisionJobModel.updateMany({ state: 'running', leaseUntil: { $lte: now } },
      { $set: { state: 'unavailable', reason: 'timeout' }, $unset: { token: 1 } });
    job = await ItemVisionJobModel.findOneAndUpdate({ state: 'queued', nextAt: { $lte: now } },
      { $set: { state: 'running', token, leaseUntil: new Date(+now + 120000) } }, { sort: { priority: -1, nextAt: 1, _id: 1 }, new: true });
    if (!job) return;
    const listing = await ListingModel.findOne({ publicId: job.listingId });
    const current = listing && await snapshot(listing);
    if (!current || current.key !== job.snapshot || listing.status === 'draft') {
      await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'stale' } }); return;
    }
    const problem = await configurationProblem();
    if (problem) {
      await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'unavailable', reason: problem, checkedAt: new Date() } });
      return;
    }
    const at = new Date(), day = at.toISOString().slice(0, 10);
    try { await ItemVisionBudgetModel.updateOne({ _id: 'gemini-item-review' }, { $setOnInsert: { day, used: 0, nextAt: new Date(0), leaseUntil: new Date(0) } }, { upsert: true }); }
    catch (error) { if (error.code !== 11000) throw error; }
    await ItemVisionBudgetModel.updateOne({ _id: 'gemini-item-review', day: { $ne: day } }, { $set: { day, used: 0 } });
    quota = await ItemVisionBudgetModel.findOneAndUpdate({ _id: 'gemini-item-review', day,
      used: { $lt: env.geminiItemReviewDailyLimit }, nextAt: { $lte: at }, leaseUntil: { $lte: at } },
    { $inc: { used: 1 }, $set: { token, nextAt: new Date(+at + 60000), leaseUntil: new Date(+at + 120000) } }, { new: true });
    if (!quota) {
      const budget = await ItemVisionBudgetModel.findById('gemini-item-review').select('day used').lean();
      const reason = budget?.day === day && budget.used >= env.geminiItemReviewDailyLimit ? 'budget' : 'rate_limit';
      await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'queued', reason, nextAt: new Date(+at + 60000) } }); return;
    }
    // Do not download originals while waiting for quota; that would waste shared storage bandwidth.
    let storageTimer, images;
    try {
      images = await Promise.race([
        uploadService.readOwnedReferences({ authId: listing.ownerId }, listing.images, ['listing_image']),
        new Promise((_, reject) => { storageTimer = setTimeout(() => reject(new Error('storage_unavailable')), 20000); }),
      ]);
    } finally { clearTimeout(storageTimer); }
    if (images.length !== listing.images.length) throw new Error('invalid_photos');
    const fresh = await ListingModel.findById(listing._id), latest = fresh && await snapshot(fresh);
    if (!latest || latest.key !== current.key) {
      await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'stale' } }); return;
    }
    const start = new Date();
    if (!await ItemVisionBudgetModel.findOneAndUpdate({ _id: quota.id, token, leaseUntil: { $gt: start } },
      { $set: { leaseUntil: new Date(+start + 120000), nextAt: new Date(+start + 60000) } })) return;
    if (!await ItemVisionJobModel.findOneAndUpdate({ _id: job.id, token, state: 'running' }, { $inc: { attempts: 1 }, $set: { leaseUntil: new Date(+start + 120000) } })) return;
    const raw = await aiClient.reviewItemVision({ images: images.map(({ content_base64, content_type }) => ({ content_base64, content_type })),
      processing_authorized: true, expected_category: listing.category, expected_subcategory: listing.subcategory ?? '',
      expected_condition: listing.condition, expected_product_type: current.productType,
      brand: listing.brand ?? '', product_model: listing.productModel ?? '' });
    const result = cleanVisionResult(raw, images.length);
    const saved = await ListingModel.findById(listing._id), savedSnapshot = saved && await snapshot(saved);
    if (!savedSnapshot || savedSnapshot.key !== current.key) {
      await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'stale' } }); return;
    }
    const retryable = ['quota', 'provider_busy'].includes(result.reason) && job.attempts < 2;
    const delay = Math.max(60, Math.min(Number(raw?.retryAfterSeconds) || 60, 86400));
    await ItemVisionJobModel.updateOne({ _id: job.id, token, state: 'running' }, { $set: {
      state: retryable ? 'queued' : result.state, reason: result.reason, result,
      checkedAt: new Date(), nextAt: new Date(Date.now() + delay * 1000),
    } });
    if (retryable) await ItemVisionBudgetModel.updateOne({ _id: quota.id, token }, { $set: { nextAt: new Date(Date.now() + delay * 1000) } });
  } catch {
    if (job) await ItemVisionJobModel.updateOne({ _id: job.id, token }, { $set: { state: 'unavailable', reason: 'provider_unavailable', checkedAt: new Date() } }).catch(() => {});
  } finally {
    if (quota) await ItemVisionBudgetModel.updateOne({ _id: quota.id, token }, { $set: { leaseUntil: new Date(0) }, $unset: { token: 1 } }).catch(() => {});
    running = false;
  }
}
