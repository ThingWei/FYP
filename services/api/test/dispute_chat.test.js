import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { DisputeMessageModel } from '../src/modules/dispute/disputeMessage.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { uploadService } from '../src/modules/upload/upload.service.js';
import { adminModule } from '../src/modules/admin/index.js';
import { setSocketServer } from '../src/socket/eventBus.js';
import { registerSocket } from '../src/socket/registerSocket.js';
import { withOperationLock } from '../src/modules/booking/bookingRequestLock.js';

const id = 'RH-DSP-CHAT', path = `/api/v1/disputes/${id}/messages`;
const headers = (who) => ({ 'x-user-id': who, 'x-user-roles': who.startsWith('admin') ? 'admin' : who === 'owner' ? 'owner' : 'renter' });
const send = (who = 'renter', body = {}) => request(app).post(path).set(headers(who))
  .send({ idempotencyKey: 'send-first-0001', text: 'Can we arrange the return?', ...body });
const models = [DisputeModel, DisputeMessageModel, UserModel, NotificationModel, UploadAssetModel, adminModule.Model];
let mongo;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(m => m.init())); });
after(async () => { setSocketServer(undefined); await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  setSocketServer(undefined);
  await Promise.all(models.map(m => m.deleteMany({})));
  await UserModel.create(['renter', 'owner', 'outsider', 'adminone', 'admintwo'].map(authId => ({
    authId, displayName: `Name ${authId}`, email: `${authId}@example.test`,
    roles: authId.startsWith('admin') ? ['admin'] : ['renter', 'owner'],
    activeRole: authId.startsWith('admin') ? 'admin' : authId === 'owner' ? 'owner' : 'renter',
  })));
  await DisputeModel.create({ publicId: id, rentalId: 'RNT-CHAT', bookingId: 'BKG-CHAT', listingId: 'listing-chat',
    listingTitle: 'Camera', listingType: 'physical', raisedById: 'owner', raisedByName: 'Saved Owner', raisedByRole: 'owner',
    respondentId: 'renter', respondentName: 'Saved Renter', respondentRole: 'renter', category: 'late_return',
    summary: 'Return needed', description: 'Please arrange the return of the camera.', status: 'awaiting_response',
    previousBookingStatus: 'active', previousRentalStatus: 'active',
    responses: [{ userId: 'renter', role: 'renter', text: 'Historical response', submittedAt: new Date('2026-01-01') }] });
});

test('both participants and multiple admins share a safe conversation', async () => {
  for (const who of ['renter', 'owner', 'adminone', 'admintwo']) {
    const result = await send(who);
    assert.equal(result.status, 201, JSON.stringify(result.body));
    assert.equal(result.body.data.senderName, `Name ${who}`);
    assert.equal(result.body.data.role, who.startsWith('admin') ? 'admin' : who);
    assert.equal(result.body.data.payloadHash, undefined);
  }
  for (const who of ['renter', 'owner', 'adminone', 'admintwo']) {
    const result = await request(app).get(path).set(headers(who));
    assert.equal(result.status, 200);
    assert.equal(result.body.data.length, 6);
    assert(result.body.data.some(row => row.text === 'Historical response'));
    assert(result.body.data.some(row => row.text === 'Case opened'));
    assert(!JSON.stringify(result.body).includes('idempotencyKey'));
  }
  assert.equal((await DisputeModel.findOne({ publicId: id })).status, 'awaiting_response');
});

test('foreign users cannot read or send and cannot forge admin membership', async () => {
  assert.equal((await request(app).get(path).set(headers('outsider'))).status, 404);
  assert.equal((await send('outsider')).status, 404);
  assert.equal((await request(app).get(path).set({ ...headers('outsider'), 'x-user-roles': 'admin' })).status, 404);
  assert.equal(await DisputeMessageModel.countDocuments(), 0);
});

test('concurrent identical sends create one immutable message and one notification per recipient', async () => {
  const responses = await Promise.all([send(), send()]);
  assert(responses.every(row => row.status === 201));
  assert.equal(responses[0].body.data.id, responses[1].body.data.id);
  assert.equal(await DisputeMessageModel.countDocuments(), 1);
  assert.equal(await NotificationModel.countDocuments(), 3);
  const changed = await send('renter', { text: 'Different content' });
  assert.equal(changed.status, 409);
  assert.equal(changed.body.error.code, 'IDEMPOTENCY_CONFLICT');
});

test('cursor pages include legacy responses without gaps or duplicates at identical times', async () => {
  const at = new Date('2026-11-20T12:00:00Z');
  await DisputeMessageModel.insertMany(Array.from({ length: 43 }, (_, n) => ({ publicId: `DCM-${String(n).padStart(4, '0')}`,
    disputeId: id, senderId: 'renter', senderName: 'Renter', role: 'renter', text: `Message ${n}`,
    idempotencyKey: `page-${n}`, payloadHash: 'hash', createdAt: at, updatedAt: at })));
  const ids = [];
  let cursor;
  do {
    const result = await request(app).get(`${path}?limit=10${cursor ? `&before=${cursor}` : ''}`).set(headers('renter'));
    assert.equal(result.status, 200, JSON.stringify(result.body));
    ids.push(...result.body.data.map(row => row.id));
    cursor = result.body.meta.nextCursor;
  } while (cursor);
  assert.equal(ids.length, 45);
  assert.equal(new Set(ids).size, 45);
  assert.equal((await request(app).get(`${path}?before=invalid`).set(headers('renter'))).status, 422);
});

test('closed cases retain history and successful retries but reject new messages', async () => {
  const first = await send();
  await DisputeModel.updateOne({ publicId: id }, { $set: { status: 'resolved', resolution: { notes: 'Both parties agreed to the outcome.', resolvedAt: new Date() } } });
  assert.equal((await send()).body.data.id, first.body.data.id);
  const blocked = await send('owner');
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error.code, 'DISPUTE_CLOSED');
  const history = await request(app).get(path).set(headers('owner'));
  assert.equal(history.body.meta.status, 'resolved');
  assert(history.body.data.some(row => row.id === 'decision'));
});

test('case updates show only approved notes, never internal audit metadata', async () => {
  await adminModule.Model.create({ actorId: 'adminone', action: 'dispute.more_evidence_required', targetType: 'dispute',
    targetId: id, metadata: { note: 'Please add a photo.', secret: 'PRIVATE-SERVER-DATA' }, createdBy: 'adminone' });
  const result = await request(app).get(path).set(headers('renter'));
  assert(result.body.data.some(row => row.text === 'More information requested: Please add a photo.'));
  assert(!JSON.stringify(result.body).includes('PRIVATE-SERVER-DATA'));
});

test('submitted evidence is participant-only and cannot be deleted or borrowed from another account', async () => {
  await UploadAssetModel.collection.insertOne({ publicId: 'UPL-CHAT', uploadedBy: 'renter', purpose: 'dispute_evidence', visibility: 'private' });
  assert.equal((await send('owner', { evidence: ['upload://UPL-CHAT'] })).status, 400);
  assert.equal((await send('renter', { evidence: ['upload://UPL-CHAT'], text: '' })).status, 201);
  const asset = await uploadService.getPrivate({ authId: 'owner', roles: ['owner'] }, 'UPL-CHAT');
  assert.equal(asset.publicId, 'UPL-CHAT');
  await assert.rejects(uploadService.getPrivate({ authId: 'outsider', roles: ['renter'] }, 'UPL-CHAT'), e => e.status === 403);
  await assert.rejects(uploadService.remove({ authId: 'renter', roles: ['renter'] }, 'UPL-CHAT'), e => e.code === 'UPLOAD_IN_USE');
});

test('empty and oversized messages, invalid keys and privileged upload purposes are rejected', async () => {
  for (const body of [{ text: '' }, { text: 'x'.repeat(2001) }, { idempotencyKey: 'bad' }]) {
    assert.equal((await send('renter', body)).status, 422);
  }
  await UploadAssetModel.collection.insertOne({ publicId: 'UPL-IC', uploadedBy: 'renter', purpose: 'verification_document', visibility: 'private' });
  assert.equal((await send('renter', { evidence: ['upload://UPL-IC'] })).status, 400);
});

test('socket updates invalidate only the authorized case room and contain no message contents', async () => {
  const events = [];
  const bus = { to(room) { events.push(room); return this; }, emit(name, data) { events.push({ name, data }); } };
  setSocketServer(bus);
  await send();
  assert(events.includes(`case:${id}`));
  assert(events.some(event => event.name === 'case:update' && JSON.stringify(event.data) === JSON.stringify({ disputeId: id })));
});

test('case socket subscriptions require participant or admin access and active accounts', async () => {
  let connect;
  const io = { use() {}, on(event, callback) { if (event === 'connection') connect = callback; } };
  registerSocket(io);
  for (const who of ['renter', 'owner', 'adminone', 'outsider']) {
    const rooms = [], handlers = {};
    const socket = { data: { userId: who }, join: room => rooms.push(room), leave() {},
      on: (event, callback) => { handlers[event] = callback; } };
    connect(socket);
    await handlers['case:join'](id);
    assert.equal(rooms.includes(`case:${id}`), who !== 'outsider');
  }
  await UserModel.updateOne({ authId: 'renter' }, { $set: { accountStatus: 'suspended' } });
  const rooms = [], handlers = {};
  connect({ data: { userId: 'renter' }, join: room => rooms.push(room), leave() {}, on: (event, callback) => { handlers[event] = callback; } });
  await handlers['case:join'](id);
  assert(!rooms.includes(`case:${id}`));
});

test('a send racing closure checks fresh status inside the lifecycle lock', async () => {
  let unlock, acquired;
  const ready = new Promise(resolve => { acquired = resolve; });
  const wait = new Promise(resolve => { unlock = resolve; });
  const closing = withOperationLock('listing-decision', 'listing-chat', async () => {
    acquired(); await wait;
    await DisputeModel.updateOne({ publicId: id }, { $set: { status: 'dismissed' } });
  });
  await ready;
  const pending = send().then(response => response);
  unlock(); await closing;
  const response = await pending;
  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'DISPUTE_CLOSED');
  assert.equal(await DisputeMessageModel.countDocuments(), 0);
  assert.equal(await NotificationModel.countDocuments(), 0);
});

test('missing historical timestamps remain missing while cursor paging still works', async () => {
  await DisputeModel.collection.updateOne({ publicId: id }, { $unset: { createdAt: 1, 'responses.0.submittedAt': 1 } });
  const first = await request(app).get(`${path}?limit=1`).set(headers('renter'));
  assert.equal(first.status, 200);
  assert(first.body.meta.nextCursor);
  assert.equal(first.body.data[0].createdAt, undefined);
  const next = await request(app).get(`${path}?limit=1&before=${first.body.meta.nextCursor}`).set(headers('renter'));
  assert.equal(next.status, 200);
  assert.equal(next.body.data[0].createdAt, undefined);
  assert.notEqual(next.body.data[0].id, first.body.data[0].id);
  assert(!JSON.stringify(next.body).includes('_sortAt'));
});
