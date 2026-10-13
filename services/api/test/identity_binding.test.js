import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel, IDENTITY_BINDING_INDEX } from '../src/modules/user/user.model.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { validMykadFields } from './helpers/mykad.js';
import { fingerprintForNumber, assertBindingReady } from '../src/modules/user/identityBinding.js';
import { auditIdentityBindings } from '../src/modules/user/identityBindingAudit.js';

const KEY = 'synthetic-identity-binding-key-not-a-real-secret-12345';
const ADMIN = { 'x-user-id': 'binding-admin', 'x-user-roles': 'admin',
  'x-user-name': 'Test Admin', 'x-user-email': 'binding-admin@example.invalid' };
const identity = id => ({ 'x-user-id': id, 'x-user-roles': 'renter,owner',
  'x-user-name': 'Test User', 'x-user-email': id + '@example.invalid' });
const input = { documentType: 'mykad', documentRefs: ['local://test/front.png', 'local://test/back.png'] };
let mongo;
const oldKey = env.kycIdentityMatchSecret;
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  await UserModel.init();
});
after(async () => { env.kycIdentityMatchSecret = oldKey; await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await UserModel.deleteMany({}); env.kycIdentityMatchSecret = KEY;
  await request(app).post('/api/v1/users/session').set(ADMIN).expect(201);
});
function mockValid(t, number = '900101-07-1234') {
  t.mock.method(aiClient, 'verifyDocument', async () => ({ accepted: false, outcome: 'manual_review',
    extracted_fields: validMykadFields({ identityNumber: number }), confidence: .95 }));
}
async function submit(id) {
  await request(app).post('/api/v1/users/session').set(identity(id)).expect(201);
  const response = await request(app).post('/api/v1/users/me/verification').set(identity(id)).send(input).expect(200);
  return { id: response.body.data._id, attempt: response.body.data.verification.history.at(-1).attemptId,
    response: response.body.data };
}
function approve(user) {
  return request(app).patch('/api/v1/users/' + user.id + '/verification').set(ADMIN)
    .send({ status: 'approved', attemptId: user.attempt });
}
test('two pending accounts do not reserve identity; first approval blocks the other', async t => {
  mockValid(t);
  const one = await submit('pending-one'), two = await submit('pending-two');
  assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 0);
  await approve(one).expect(200);
  const blocked = await approve(two).expect(409);
  assert.equal(blocked.body.error.code, 'MYKAD_ALREADY_LINKED');
  assert.ok(!JSON.stringify(blocked.body).includes('pending-one'));
  assert.equal((await UserModel.findById(two.id)).verification.status, 'pending');
});
test('simultaneous approvals yield one verified identity with standalone MongoDB', async t => {
  mockValid(t);
  const one = await submit('race-one'), two = await submit('race-two');
  const responses = await Promise.all([approve(one), approve(two)]);
  assert.deepEqual(responses.map(response => response.status).sort(), [200, 409]);
  assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 1);
  assert.equal(await UserModel.countDocuments({ 'verification.status': 'approved' }), 1);
  const loser = responses.find(response => response.status === 409);
  assert.equal(loser.body.error.code, 'MYKAD_ALREADY_LINKED');
});
test('already bound MyKad rejects a different account at submission without creating a pending attempt', async t => {
  mockValid(t);
  const owner = await submit('already-bound'); await approve(owner).expect(200);
  await request(app).post('/api/v1/users/session').set(identity('new-account')).expect(201);
  const blocked = await request(app).post('/api/v1/users/me/verification').set(identity('new-account')).send(input).expect(409);
  assert.equal(blocked.body.error.code, 'MYKAD_ALREADY_LINKED');
  assert.equal((await UserModel.findOne({ authId: 'new-account' })).verification.history.length, 0);
});
test('rejected attempt can be resubmitted on the same account with a fresh private snapshot', async t => {
  mockValid(t);
  const first = await submit('retry-user');
  await request(app).patch('/api/v1/users/' + first.id + '/verification').set(ADMIN)
    .send({ status: 'rejected', attemptId: first.attempt, reason: 'Please provide clearer evidence.' }).expect(200);
  const second = await request(app).post('/api/v1/users/me/verification').set(identity('retry-user')).send(input).expect(200);
  assert.equal(second.body.data.verification.history.length, 2);
  await approve({ id: first.id, attempt: second.body.data.verification.history.at(-1).attemptId }).expect(200);
});
test('approval uses the attempt fingerprint, not mutable profile licence comparison', async t => {
  mockValid(t);
  const user = await submit('snapshot-user');
  const expected = fingerprintForNumber('900101071234', true);
  await UserModel.updateOne({ _id: user.id }, { identityMatchFingerprint: fingerprintForNumber('910101071234', true) });
  await approve(user).expect(200);
  const stored = await UserModel.findById(user.id).select('+verifiedIdentityFingerprint');
  assert.equal(stored.verifiedIdentityFingerprint, expected);
});
test('stale pending attempt and missing attempt snapshot cannot be approved', async t => {
  mockValid(t);
  const user = await submit('stale-user');
  await UserModel.updateOne({ _id: user.id }, { 'verification.documents.0.latestAttemptId': 'KYC-NEWERATTEMPT' });
  const stale = await approve(user).expect(409);
  assert.equal(stale.body.error.code, 'STALE_VERIFICATION_ATTEMPT');
  await UserModel.updateOne({ _id: user.id }, { $set: { 'verification.documents.0.latestAttemptId': user.attempt },
    $unset: { 'verification.history.0.identityFingerprint': 1 } });
  const missing = await approve(user).expect(409);
  assert.equal(missing.body.error.code, 'IDENTITY_BINDING_ATTEMPT_INVALID');
});
test('missing secret fails clearly without persisting a false pending result', async t => {
  mockValid(t);
  env.kycIdentityMatchSecret = undefined;
  await request(app).post('/api/v1/users/session').set(identity('no-key')).expect(201);
  const response = await request(app).post('/api/v1/users/me/verification').set(identity('no-key')).send(input).expect(503);
  assert.equal(response.body.error.code, 'IDENTITY_BINDING_NOT_CONFIGURED');
  assert.equal((await UserModel.findOne({ authId: 'no-key' })).verification.history.length, 0);
});
test('missing unique index prevents new approval and is not silently recreated by the guard', async t => {
  mockValid(t);
  const user = await submit('index-user');
  await UserModel.collection.dropIndex(IDENTITY_BINDING_INDEX);
  try {
    const response = await approve(user).expect(503);
    assert.equal(response.body.error.code, 'IDENTITY_BINDING_INDEX_MISSING');
    assert.equal((await UserModel.findById(user.id)).verification.status, 'pending');
  } finally {
    await UserModel.collection.createIndex({ verifiedIdentityFingerprint: 1 }, { name: IDENTITY_BINDING_INDEX,
      unique: true, partialFilterExpression: { verifiedIdentityFingerprint: { $type: 'string' } } });
  }
});
test('secret rotation cannot silently bypass an existing binding or attempt', async t => {
  mockValid(t);
  const user = await submit('key-user');
  env.kycIdentityMatchSecret = 'different-synthetic-binding-key-1234567890';
  const pending = await approve(user).expect(409);
  assert.equal(pending.body.error.code, 'IDENTITY_BINDING_ATTEMPT_INVALID');
  env.kycIdentityMatchSecret = KEY;
  await approve(user).expect(200);
  env.kycIdentityMatchSecret = 'different-synthetic-binding-key-1234567890';
  await assert.rejects(assertBindingReady(), error => error.code === 'IDENTITY_BINDING_KEY_MISMATCH');
});
test('binding survives deactivation, suspension and banning', async t => {
  mockValid(t);
  const user = await submit('retained-user'); await approve(user).expect(200);
  const fingerprint = fingerprintForNumber('900101071234', true);
  for (const status of ['deactivated', 'suspended', 'banned']) {
    await UserModel.updateOne({ _id: user.id }, { accountStatus: status });
    await request(app).post('/api/v1/users/session').set(identity('other-' + status)).expect(201);
    const response = await request(app).post('/api/v1/users/me/verification').set(identity('other-' + status)).send(input).expect(409);
    assert.equal(response.body.error.code, 'MYKAD_ALREADY_LINKED');
    assert.equal((await UserModel.findById(user.id).select('+verifiedIdentityFingerprint')).verifiedIdentityFingerprint, fingerprint);
  }
});
test('fingerprints are absent from submission, approval, own profile and admin list serialization', async t => {
  mockValid(t);
  const user = await submit('private-user');
  const approved = await approve(user).expect(200);
  const profile = await request(app).get('/api/v1/users/me').set(identity('private-user')).expect(200);
  const list = await request(app).get('/api/v1/users').set(ADMIN).expect(200);
  const fingerprint = fingerprintForNumber('900101071234', true);
  for (const response of [user.response, approved.body, profile.body, list.body]) {
    const text = JSON.stringify(response);
    assert.ok(!text.includes(fingerprint));
    assert.ok(!text.includes('identityFingerprint'));
    assert.ok(!text.includes('verifiedIdentityFingerprint'));
    assert.ok(!text.includes('900101-07-1234'));
  }
});
async function legacy(id, number) {
  await request(app).post('/api/v1/users/session').set(identity(id)).expect(201);
  await UserModel.updateOne({ authId: id }, { 'verification.status': 'approved',
    'verification.documentType': 'mykad',
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }],
    ...(number && { identityMatchFingerprint: fingerprintForNumber(number, true) }) });
}
test('legacy dry run reports aggregate gaps/duplicates and writes nothing; apply quarantines duplicates', async () => {
  await legacy('legacy-one', '900101071234'); await legacy('legacy-two', '900101071234');
  await legacy('legacy-three', '910101071234'); await legacy('legacy-missing');
  const before = await UserModel.collection.find({}).toArray();
  const report = await auditIdentityBindings(UserModel.collection, env);
  assert.equal(report.dryRun, true); assert.equal(report.counts.duplicateGroups, 1);
  assert.equal(report.counts.duplicateAccounts, 2); assert.equal(report.counts.usableUnbound, 1);
  assert.equal(report.counts.missingFingerprints, 1);
  assert.deepEqual(await UserModel.collection.find({}).toArray(), before);
  assert.ok(!JSON.stringify(report).includes('legacy-one'));
  assert.ok(!JSON.stringify(report).includes(fingerprintForNumber('900101071234', true)));
  const applied = await auditIdentityBindings(UserModel.collection, env, { apply: true, reviewed: true });
  assert.equal(applied.counts.applied, 1);
  assert.equal(await UserModel.countDocuments({ 'verification.status': 'approved' }), 4);
  assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 1);
  const replay = await auditIdentityBindings(UserModel.collection, env, { apply: true, reviewed: true });
  assert.equal(replay.counts.applied, 0);
});
test('legacy apply requires review, full bounded coverage and compatible key/index', async () => {
  await legacy('review-legacy', '900101071234'); await legacy('review-second', '910101071234');
  await assert.rejects(auditIdentityBindings(UserModel.collection, env, { apply: true }), /explicit acknowledgment/);
  await assert.rejects(auditIdentityBindings(UserModel.collection, env, { limit: 1, apply: true, reviewed: true }), /truncated/);
  const changed = { ...env, kycIdentityMatchSecret: 'different-synthetic-key-not-production-1234' };
  await assert.rejects(auditIdentityBindings(UserModel.collection, changed, { apply: true, reviewed: true }), /key\/conflict/);
  assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 0);
});
test('usable approved legacy fingerprint blocks a duplicate new claim before optional binding', async t => {
  mockValid(t);
  await legacy('legacy-known', '900101071234');
  await request(app).post('/api/v1/users/session').set(identity('new-vs-legacy')).expect(201);
  await request(app).post('/api/v1/users/me/verification').set(identity('new-vs-legacy')).send(input).expect(409);
  assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 0);
});

test('legacy binding refuses missing key, unsafe limits, missing index and conflicting snapshots', async () => {
  await legacy('guard-legacy', '900101071234');
  for (const limit of [0, 10001, 1.5]) {
    await assert.rejects(auditIdentityBindings(UserModel.collection, env, { limit }), /Limit/);
  }
  await assert.rejects(auditIdentityBindings(UserModel.collection, { ...env, kycIdentityMatchSecret: undefined },
    { apply: true, reviewed: true }), /Configure/);
  await UserModel.collection.dropIndex(IDENTITY_BINDING_INDEX);
  try {
    await assert.rejects(auditIdentityBindings(UserModel.collection, env,
      { apply: true, reviewed: true }), /index is missing/);
    assert.equal(await UserModel.countDocuments({ verifiedIdentityFingerprint: { $exists: true } }), 0);
  } finally {
    await UserModel.collection.createIndex({ verifiedIdentityFingerprint: 1 }, { name: IDENTITY_BINDING_INDEX,
      unique: true, partialFilterExpression: { verifiedIdentityFingerprint: { $type: 'string' } } });
  }
  await UserModel.updateOne({ authId: 'guard-legacy' }, {
    verifiedIdentityFingerprint: fingerprintForNumber('910101071234', true) });
  const report = await auditIdentityBindings(UserModel.collection, env);
  assert.equal(report.counts.conflictingStoredFingerprints, 1);
  await assert.rejects(auditIdentityBindings(UserModel.collection, env,
    { apply: true, reviewed: true }), /key\/conflict/);
});

