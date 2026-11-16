import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { env } from '../src/config/env.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { ItemVisionJobModel, ItemVisionBudgetModel } from '../src/modules/listing/itemVision.model.js';
import { setPhotoConsent, hasPhotoConsent } from '../src/modules/listing/itemVisionConsent.js';
import { enqueueItemVision, runItemVisionJob, reconcileItemVisionJobs, itemVisionSummary, cleanVisionResult, VISION_CONTRACT, VISION_MODEL } from '../src/modules/listing/itemVision.service.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';
const h = id => ({ 'x-user-id': id, 'x-user-name': id, 'x-user-email': `${id}@example.test`, 'x-user-roles': id === 'admin' ? 'admin' : 'renter,owner' });
const models = [UserModel, ListingModel, UploadAssetModel, ItemVisionJobModel, ItemVisionBudgetModel];
const original = { enabled: env.geminiItemReviewEnabled, limit: env.geminiItemReviewDailyLimit, mode: env.aiEnforcementMode };
let mongo, sequence = 0;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(m => m.init())); });
after(async () => { Object.assign(env, { geminiItemReviewEnabled: original.enabled, geminiItemReviewDailyLimit: original.limit, aiEnforcementMode: original.mode }); await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(m => m.deleteMany({})));
  env.geminiItemReviewEnabled = true; env.geminiItemReviewDailyLimit = 20; env.aiEnforcementMode = 'advisory';
  await UserModel.create(['owner', 'foreign', 'admin'].map(authId => ({ authId, email: `${authId}@example.test`, displayName: authId,
    roles: authId === 'admin' ? ['admin'] : ['renter', 'owner'], activeRole: authId === 'admin' ? 'admin' : 'owner',
    verification: { status: 'approved', documentType: 'mykad', documents: [{ documentType: 'mykad', status: 'approved' }] } })));
});
const response = extra => ({ contract: VISION_CONTRACT, model: VISION_MODEL, state: 'ready', observations: {
  item_consistency: 'consistent', photo_consistency: 'consistent', visible_condition: 'cannot_assess', visible_branding: 'not_readable', sensitive_content: false,
  concerns: [], observations: [{ photo: 1, observation: 'The item is visible.' }], ...extra } });
async function photos(owner = 'owner', purpose = 'listing_image') {
  return Promise.all([1, 2, 3].map(async n => {
    const id = `UPL-${++sequence}`;
    await UploadAssetModel.create({ publicId: id, uploadedBy: owner, purpose, visibility: 'private', originalName: 'PRIVATE.jpg',
      contentType: 'image/jpeg', size: 20, storageProvider: 'local', storagePath: `private-${id}`, sha256: String(n).repeat(64) });
    return purpose === 'listing_image' ? `/api/v1/uploads/public/${id}/content` : `upload://${id}`;
  }));
}
async function listing(extra = {}) {
  const row = new ListingModel({ publicId: `l-vision-${++sequence}`, ownerId: 'owner', ownerName: 'Owner', title: 'Camera',
    description: 'Camera with battery.', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', dailyPrice: 40,
    condition: 'Good', fulfilmentMethods: ['pickup'], location: 'Private street', coordinates: { latitude: 3.12, longitude: 101.68 },
    status: 'pending_review', images: await photos(), ...extra });
  setPhotoConsent(row, true, { authId: row.ownerId });
  await row.save(); return row;
}
function provider(t, value = response()) {
  const calls = [];
  t.mock.method(aiClient, 'itemVisionStatus', async () => ({ contract: VISION_CONTRACT, enabled: true, configured: true, model: VISION_MODEL }));
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic photo fixture'));
  t.mock.method(aiClient, 'reviewItemVision', async payload => { calls.push(payload); return typeof value === 'function' ? value(payload) : value; });
  return calls;
}
test('one consented snapshot queues once and produces admin-only safe observations', async t => {
  const row = await listing(), calls = provider(t);
  await Promise.all([enqueueItemVision(row), enqueueItemVision(row)]);
  assert.equal(await ItemVisionJobModel.countDocuments(), 1);
  await runItemVisionJob();
  assert.equal(calls.length, 1); assert.equal(calls[0].images.length, 3);
  assert.ok(!JSON.stringify(calls[0]).includes('PRIVATE')); assert.equal(calls[0].profile_name, undefined);
  const result = await itemVisionSummary(row);
  assert.equal(result.state, 'ready'); assert.equal(result.authenticityVerified, false);
  assert.equal(result.observations.observations[0].photo, 1);
  assert.equal((await ListingModel.findById(row._id)).status, 'pending_review');
  const detail = (await request(app).get(`/api/v1/admin/records/listings/${row.publicId}`).set(h('admin')).expect(200)).body.data.record;
  assert.equal(detail.itemVisionReview.state, 'ready'); assert.equal(detail.itemVisionConsent, undefined);
  const owned = (await request(app).get(`/api/v1/listings/owner/${row.publicId}`).set(h('owner')).expect(200)).body.data;
  assert.equal(owned.photoReviewConsent, true); assert.equal(owned.itemVisionReview, undefined); assert.equal(owned.itemVisionConsent, undefined);
  await ListingModel.updateOne({ _id: row._id }, { $set: { status: 'active' } });
  const publicRow = (await request(app).get(`/api/v1/listings/${row.publicId}`).expect(200)).body.data;
  assert.equal(publicRow.itemVisionReview, undefined); assert.equal(publicRow.itemVisionConsent, undefined); assert.equal(publicRow.photoReviewConsent, undefined);
  await enqueueItemVision(row, { retry: true }); await runItemVisionJob(); assert.equal(calls.length, 1);
});
test('legacy omissions, forged result input, changed photos and revoked consent cannot forward photos', async t => {
  const row = await listing(), calls = provider(t);
  setPhotoConsent(row, false, { authId: 'owner' }); await row.save();
  await enqueueItemVision(row); await runItemVisionJob(); assert.equal(calls.length, 0);
  await request(app).patch(`/api/v1/listings/${row.publicId}`).set(h('owner')).send({ itemVisionConsent: { version: 'fake' } }).expect(422);
  row.status = 'draft'; setPhotoConsent(row, true, { authId: 'owner' }); await row.save();
  await request(app).patch(`/api/v1/listings/${row.publicId}`).set(h('owner')).send({ photoReviewConsent: 'true' }).expect(422);
  await request(app).patch(`/api/v1/listings/${row.publicId}`).set(h('owner')).send({ description: 'Updated description.' }).expect(200);
  assert.equal(hasPhotoConsent(await ListingModel.findById(row._id)), true);
  await request(app).patch(`/api/v1/listings/${row.publicId}`).set(h('owner')).send({ images: await photos() }).expect(200);
  const saved = await ListingModel.findById(row._id); assert.equal(hasPhotoConsent(saved), false);
  assert.equal((await itemVisionSummary(saved)).reason, 'consent_required');
});
for (const purpose of ['vehicle_grant', 'verification_document', 'verification_holder_photo', 'avatar']) {
  test(`private/wrong-purpose ${purpose} uploads are never forwarded`, async t => {
    const row = await listing({ images: await photos('owner', purpose) }), calls = provider(t);
    await enqueueItemVision(row); await runItemVisionJob();
    assert.equal(calls.length, 0); assert.equal((await itemVisionSummary(row)).reason, 'invalid_photos');
  });
}
test('foreign uploads and arbitrary URLs cannot be collected by Gemini', async t => {
  const row = await listing({ images: await photos('foreign') }), calls = provider(t);
  await enqueueItemVision(row); await runItemVisionJob(); assert.equal(calls.length, 0);
  row.images = ['https://private.invalid/one', 'https://private.invalid/two', 'https://private.invalid/three'];
  setPhotoConsent(row, true, { authId: 'owner' });
  await enqueueItemVision(row); await runItemVisionJob(); assert.equal(calls.length, 0);
});
test('new submission queues automatically without waiting for Gemini; old clients remain usable', async t => {
  const row = await listing({ status: 'draft' }), calls = provider(t);
  t.mock.method(aiClient, 'verifyItem', async () => ({ outcome: 'manual_review', accepted: false }));
  await request(app).post(`/api/v1/listings/${row.publicId}/submit`).set(h('owner')).expect(200);
  assert.equal(calls.length, 0); assert.equal(await ItemVisionJobModel.countDocuments({ state: 'queued' }), 1);
  await request(app).post(`/api/v1/admin/listings/${row.publicId}/photo-review`).set(h('foreign')).expect(403);
  await request(app).patch(`/api/v1/listings/${row.publicId}/moderation`).set(h('admin')).send({ status: 'active' }).expect(200);
  assert.equal((await ListingModel.findById(row._id)).status, 'active'); // Cloud result is never an approval gate.
});
test('optional consent survives create/reopen and a legacy omission creates no cloud job', async t => {
  provider(t);
  t.mock.method(aiClient, 'verifyItem', async () => ({ outcome: 'manual_review', accepted: false }));
  const input = { title: 'Student camera', category: 'Devices', subcategory: 'Cameras', listingType: 'physical',
    description: 'Camera with battery.', condition: 'Good', dailyPrice: 40, fulfilmentMethods: ['pickup'],
    location: 'Kuala Lumpur', coordinates: { latitude: 3.12, longitude: 101.68 }, images: await photos() };
  const first = (await request(app).post('/api/v1/listings').set(h('owner')).send({ ...input, photoReviewConsent: true }).expect(201)).body.data;
  assert.equal(first.photoReviewConsent, true);
  await request(app).post(`/api/v1/listings/${first.publicId}/submit`).set(h('owner')).expect(200);
  assert.equal(await ItemVisionJobModel.countDocuments(), 1);
  const oldClient = (await request(app).post('/api/v1/listings').set(h('owner')).send({ ...input, images: await photos() }).expect(201)).body.data;
  assert.equal(oldClient.photoReviewConsent, false);
  await request(app).post(`/api/v1/listings/${oldClient.publicId}/submit`).set(h('owner')).expect(200);
  assert.equal(await ItemVisionJobModel.countDocuments(), 1);
});
test('service listings have no cloud item check', async t => {
  const row = await listing({ listingType: 'service', category: 'Services', serviceDetails: { packageName: 'Tuition', durationMinutes: 60 } }), calls = provider(t);
  assert.equal(await enqueueItemVision(row), null); await runItemVisionJob(); assert.equal(calls.length, 0);
});
test('bounded recovery repairs missing jobs and never re-runs a successful snapshot', async t => {
  const row = await listing(), calls = provider(t);
  assert.equal(await ItemVisionJobModel.countDocuments(), 0);
  await reconcileItemVisionJobs(); await reconcileItemVisionJobs();
  assert.equal(await ItemVisionJobModel.countDocuments(), 1);
  await runItemVisionJob();
  await reconcileItemVisionJobs(); await reconcileItemVisionJobs(); await runItemVisionJob();
  assert.equal(calls.length, 1);
  assert.equal((await itemVisionSummary(row)).state, 'ready');
});
test('changed snapshots during inference discard late observations and cannot change moderation', async t => {
  const row = await listing();
  const calls = provider(t, async () => {
    await ListingModel.updateOne({ _id: row._id }, { $set: { condition: 'Fair' } }); return response();
  });
  await enqueueItemVision(row); await runItemVisionJob(); assert.equal(calls.length, 1);
  assert.equal((await ItemVisionJobModel.findOne()).state, 'stale');
  assert.notEqual((await itemVisionSummary(await ListingModel.findById(row._id))).state, 'ready');
});
test('consent revoked after queueing cancels forwarding before any storage/provider request', async t => {
  const row = await listing(), calls = provider(t);
  await enqueueItemVision(row);
  await ListingModel.updateOne({ _id: row._id }, { $unset: { itemVisionConsent: 1 } });
  await runItemVisionJob();
  assert.equal(calls.length, 0); assert.equal(storageAdapter.download.mock.calls.length, 0);
  assert.equal((await ItemVisionJobModel.findOne()).state, 'stale');
});
test('free budget and spacing survive multiple jobs and concurrent scheduler calls', async t => {
  const first = await listing(), second = await listing(), calls = provider(t);
  await enqueueItemVision(first); await enqueueItemVision(second);
  const otherWorker = await import('../src/modules/listing/itemVision.service.js?second-worker');
  await Promise.all([runItemVisionJob(), otherWorker.runItemVisionJob()]);
  assert.equal(calls.length, 1); assert.equal((await ItemVisionBudgetModel.findById('gemini-item-review')).used, 1);
  env.geminiItemReviewDailyLimit = 1;
  await ItemVisionBudgetModel.updateOne({ _id: 'gemini-item-review' }, { $set: { nextAt: new Date(0) } });
  await ItemVisionJobModel.updateMany({ state: 'queued' }, { $set: { nextAt: new Date(0) } });
  await runItemVisionJob(); assert.equal(calls.length, 1);
  assert.equal(storageAdapter.download.mock.calls.length, 3, 'No image downloads after the daily budget is exhausted');
});
test('quota retries are bounded; a timeout or abandoned lease requires explicit retry', async t => {
  const row = await listing(), calls = provider(t, { contract: VISION_CONTRACT, model: VISION_MODEL, state: 'unavailable', reason: 'quota' });
  await enqueueItemVision(row);
  for (let n = 0; n < 4; n++) {
    await ItemVisionBudgetModel.updateMany({}, { $set: { nextAt: new Date(0) } });
    await ItemVisionJobModel.updateMany({ state: 'queued' }, { $set: { nextAt: new Date(0) } });
    await runItemVisionJob();
  }
  assert.equal(calls.length, 3); assert.equal((await itemVisionSummary(row)).state, 'unavailable');
  await ItemVisionJobModel.updateMany({}, { $set: { state: 'running', token: 'abandoned', leaseUntil: new Date(0) } });
  await runItemVisionJob(); assert.equal(calls.length, 3);
  assert.equal((await itemVisionSummary(row)).reason, 'timeout');
});
test('disabled integration and invalid provider outputs remain safe manual review', async t => {
  const row = await listing(), calls = provider(t); env.geminiItemReviewEnabled = false;
  await enqueueItemVision(row); await runItemVisionJob(); assert.equal(calls.length, 0);
  assert.equal((await itemVisionSummary(row)).reason, 'not_enabled');
  for (const raw of [null, { ...response(), model: 'paid-model' }, response({ item_consistency: 'authentic' }),
    response({ observations: [{ photo: 9, observation: 'Unseen image' }] }), response({ observations: [{ photo: 1, observation: 'A genuine product.' }] }), response({ sensitive_content: true })]) {
    assert.equal(cleanVisionResult(raw, 3).state, 'unavailable');
  }
});
test('disabled AI configuration fails promptly before queueing a retry or downloading photos', async t => {
  const row = await listing(), calls = provider(t);
  t.mock.method(aiClient, 'itemVisionStatus', async () => ({ contract: VISION_CONTRACT, enabled: false, configured: false, model: VISION_MODEL }));
  const response = await request(app).post(`/api/v1/admin/listings/${row.publicId}/photo-review`).set(h('admin')).expect(200);
  assert.equal(response.body.data.reason, 'not_enabled');
  assert.equal(await ItemVisionJobModel.countDocuments(), 0);
  await enqueueItemVision(row); await runItemVisionJob();
  assert.equal((await itemVisionSummary(row)).reason, 'not_enabled');
  assert.equal(calls.length, 0); assert.equal(storageAdapter.download.mock.calls.length, 0);
  assert.equal(await ItemVisionBudgetModel.countDocuments(), 0);
});
test('missing configuration and unreachable AI status are distinct safe retry results', async t => {
  const row = await listing(); provider(t);
  t.mock.method(aiClient, 'itemVisionStatus', async () => ({ contract: VISION_CONTRACT, enabled: true, configured: false, model: VISION_MODEL }));
  let result = await request(app).post(`/api/v1/admin/listings/${row.publicId}/photo-review`).set(h('admin')).expect(200);
  assert.equal(result.body.data.reason, 'not_configured');
  t.mock.method(aiClient, 'itemVisionStatus', async () => ({ contract: VISION_CONTRACT, unavailable: true }));
  result = await request(app).post(`/api/v1/admin/listings/${row.publicId}/photo-review`).set(h('admin')).expect(200);
  assert.equal(result.body.data.reason, 'provider_unavailable');
});
