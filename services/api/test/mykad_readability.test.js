import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { adminModule } from '../src/modules/admin/index.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';
import { validMykadFields } from './helpers/mykad.js';
import { env } from '../src/config/env.js';

const renter = { 'x-user-id': 'kyc-test-renter', 'x-user-roles': 'renter',
  'x-user-name': 'Test User', 'x-user-email': 'renter@example.invalid' };
const admin = { 'x-user-id': 'kyc-test-admin', 'x-user-roles': 'admin',
  'x-user-name': 'Test Admin', 'x-user-email': 'admin@example.invalid' };
const front = 'upload://UPL-TESTFRONT', back = 'upload://UPL-TESTBACK';
const frame = { contentBase64: Buffer.from('synthetic camera pixels '.repeat(10)).toString('base64'),
  documentType: 'mykad', expectedSide: 'back', validateCapture: true, frontDocumentRef: front };
let mongo, userId;
const previousKey = env.kycIdentityMatchSecret;
before(async () => {
  env.kycIdentityMatchSecret = 'synthetic-binding-key-not-a-production-secret-123456';
  mongo = await MongoMemoryServer.create();
  await connectDatabase(mongo.getUri());
  await Promise.all([UserModel.init(), UploadAssetModel.init()]);
});
after(async () => { env.kycIdentityMatchSecret = previousKey; await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await UserModel.deleteMany({}); await UploadAssetModel.deleteMany({});
  await adminModule.PlatformSettingModel.deleteMany({});
  const response = await request(app).post('/api/v1/users/session').set(renter).expect(201);
  userId = response.body.data._id;
  await request(app).post('/api/v1/users/session').set(admin).expect(201);
  for (const id of ['TESTFRONT', 'TESTBACK']) {
    await UploadAssetModel.create({ publicId: 'UPL-' + id, uploadedBy: renter['x-user-id'],
      purpose: 'verification_document', visibility: 'private', originalName: 'synthetic.png',
      contentType: 'image/png', size: 64, storageProvider: 'local',
      storagePath: 'private/tests/' + id, sha256: 'a'.repeat(64) });
  }
});
function submission() {
  return request(app).post('/api/v1/users/me/verification').set(renter)
    .send({ documentType: 'mykad', documentRefs: [front, back] });
}
function mockAnalysis(t, fields, outcome = 'manual_review') {
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic private pixels'));
  t.mock.method(aiClient, 'verifyDocument', async () => ({
    accepted: false, outcome, confidence: .98, extracted_fields: fields,
    ocr_text: 'private full OCR 900101-07-1234', error: 'private technical error',
    reasons: ['Please rescan required details.']
  }));
}
test('final back check loads only an owned verification front and forwards its bytes privately', async t => {
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic front bytes'));
  const calls = [];
  t.mock.method(aiClient, 'inspectDocumentFrame', async input => {
    calls.push(input);
    return { adapter: 'opencv-document-yolo-v6', available: true, ready: false,
      capture_validation: { status: 'mismatched', accepted: false } };
  });
  const response = await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(frame).expect(200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].referenceFront.content_base64, Buffer.from('synthetic front bytes').toString('base64'));
  assert.equal(calls[0].referenceFront.content_type, 'image/png');
  assert.ok(!JSON.stringify(response.body).includes('synthetic front bytes'));
});

test('replacement front loads an owned saved back and forwards bytes privately', async t => {
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic stored back bytes'));
  const calls = [];
  t.mock.method(aiClient, 'inspectDocumentFrame', async input => {
    calls.push(input);
    return { adapter: 'opencv-document-yolo-v6', available: true, ready: false,
      capture_validation: { accepted: false, status: 'mismatched',
        pairMatch: { accepted: false, status: 'mismatched' } } };
  });
  const input = { ...frame, expectedSide: 'front', backDocumentRef: back };
  delete input.frontDocumentRef;
  const response = await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(input).expect(200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].referenceBack.content_base64, Buffer.from('synthetic stored back bytes').toString('base64'));
  assert.equal(calls[0].referenceFront, undefined);
  assert.equal(response.body.data.ready, false);
  assert.ok(!JSON.stringify(response.body).includes('synthetic stored back bytes'));
});

for (const invalid of ['foreign', 'purpose', 'missing']) {
  test('replacement-front saved back rejects ' + invalid + ' upload before AI', async t => {
    if (invalid === 'missing') await UploadAssetModel.deleteOne({ publicId: 'UPL-TESTBACK' });
    else await UploadAssetModel.updateOne({ publicId: 'UPL-TESTBACK' },
      invalid === 'foreign' ? { uploadedBy: 'other-user' } : { purpose: 'listing_image' });
    t.mock.method(aiClient, 'inspectDocumentFrame', async () => assert.fail('No inference for invalid back refs'));
    const input = { ...frame, expectedSide: 'front', backDocumentRef: back };
    delete input.frontDocumentRef;
    await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(input).expect(400);
  });
}

test('saved back context is restricted to final MyKad front capture; no client number authority', async () => {
  const input = { ...frame, expectedSide: 'front', backDocumentRef: back };
  delete input.frontDocumentRef;
  for (const invalid of [{ ...input, expectedSide: 'back' }, { ...input, validateCapture: false },
    { ...input, documentType: 'passport' }, { ...input, backDocumentRef: 'https://example.invalid/back.png' },
    { ...input, backIdentityNumber: '900101071234' }]) {
    await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(invalid).expect(422);
  }
});
for (const invalid of ['foreign', 'purpose', 'missing']) {
  test('front reference with ' + invalid + ' ownership/purpose is rejected before AI', async t => {
    if (invalid === 'missing') await UploadAssetModel.deleteOne({ publicId: 'UPL-TESTFRONT' });
    else await UploadAssetModel.updateOne({ publicId: 'UPL-TESTFRONT' },
      invalid === 'foreign' ? { uploadedBy: 'someone-else' } : { purpose: 'listing_image' });
    t.mock.method(aiClient, 'inspectDocumentFrame', async () => assert.fail('AI must not be called'));
    await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(frame).expect(400);
  });
}
test('frame rejects raw reference identity, remote references and inappropriate front context', async () => {
  for (const value of [{ ...frame, frontDocumentRef: 'https://example.invalid/ic.png' },
    { ...frame, frontIdentityNumber: '900101071234' },
    { ...frame, expectedSide: 'front' }, { ...frame, validateCapture: false },
    { ...frame, documentType: 'passport' }]) {
    await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(value).expect(422);
  }
});
for (const failure of ['missing', 'mismatch', 'unreadable_address', 'screen_copy', 'phone_copy', 'phone_unavailable', 'phone_missing', 'unavailable', 'old_contract', 'malformed_sides', 'null_side']) {
  test(failure + ' cannot bypass mandatory submission or admin approval', async t => {
    const fields = validMykadFields();
    if (failure === 'missing') delete fields.mandatoryMykadValidation;
    if (failure === 'mismatch') { fields.mykadSidesConsistent = false; fields.mandatoryMykadValidation.status = 'mismatched'; }
    if (failure === 'unreadable_address') fields.mandatoryMykadValidation.sides[0].requiredFields.front_address.readable = false;
    if (failure === 'screen_copy') fields.mandatoryMykadValidation.sides[0].screenCopy.status = 'detected';
    if (failure === 'phone_copy') fields.mandatoryMykadValidation.sides[0].screenCopy.phoneScreen.status = 'detected';
    if (failure === 'phone_unavailable') fields.mandatoryMykadValidation.sides[0].screenCopy.phoneScreen.status = 'unavailable';
    if (failure === 'phone_missing') delete fields.mandatoryMykadValidation.sides[0].screenCopy.phoneScreen;
    if (failure === 'old_contract') fields.mandatoryMykadValidation.method = 'old';
    if (failure === 'malformed_sides') fields.mandatoryMykadValidation.sides = { length: 2 };
    if (failure === 'null_side') fields.mandatoryMykadValidation.sides[0] = null;
    mockAnalysis(t, failure === 'unavailable' ? {} : fields, failure === 'unavailable' ? 'unavailable' : 'manual_review');
    const result = await submission().expect(200);
    assert.equal(result.body.data.verification.status, 'resubmission_required');
    const evidence = result.body.data.verification.history[0].aiEvidence;
    assert.equal(evidence.ocr_text, undefined); assert.equal(evidence.error, undefined);
    assert.ok(!JSON.stringify(evidence).includes('900101-07-1234'));
    assert.equal(result.body.data.identityMatchFingerprint, undefined);
    await UserModel.updateOne({ _id: userId }, {
      'verification.status': 'pending', 'verification.history.0.status': 'pending',
      'verification.documents.0.status': 'pending' });
    const approval = await request(app).patch('/api/v1/users/' + userId + '/verification').set(admin)
      .send({ status: 'approved', attemptId: result.body.data.verification.history[0].attemptId }).expect(409);
    assert.equal(approval.body.error.code, 'DOCUMENT_TYPE_VALIDATION_FAILED');
  });
}
test('matched readable pair stays pending for admin and never becomes automatic approval', async t => {
  mockAnalysis(t, validMykadFields());
  const result = await submission().expect(200);
  assert.equal(result.body.data.verification.status, 'pending');
  const approval = await request(app).patch('/api/v1/users/' + userId + '/verification').set(admin)
    .send({ status: 'approved', attemptId: result.body.data.verification.history[0].attemptId }).expect(200);
  assert.equal(approval.body.data.verification.status, 'approved');
});

test('draft pair preflight is private and read-only, and front replacement rechecks retained back', async t => {
  const oldKey = env.kycIdentityMatchSecret;
  env.kycIdentityMatchSecret = undefined;
  t.after(() => { env.kycIdentityMatchSecret = oldKey; });
  await UploadAssetModel.create({ publicId: 'UPL-NEWFRONT', uploadedBy: renter['x-user-id'],
    purpose: 'verification_document', visibility: 'private', originalName: 'synthetic.png',
    contentType: 'image/png', size: 64, storageProvider: 'local',
    storagePath: 'private/tests/NEWFRONT', sha256: 'b'.repeat(64) });
  t.mock.method(storageAdapter, 'download', async path => Buffer.from(path.endsWith('NEWFRONT') ? 'new-front' :
    path.endsWith('TESTFRONT') ? 'old-front' : 'retained-back'));
  const calls = [];
  t.mock.method(aiClient, 'verifyDocument', async input => {
    calls.push(input.images.map(image => Buffer.from(image.content_base64, 'base64').toString()));
    const fields = validMykadFields();
    if (calls.at(-1)[0] === 'new-front') {
      fields.mykadSidesConsistent = false;
      fields.mandatoryMykadValidation.status = 'mismatched';
      fields.mandatoryMykadValidation.accepted = false;
    }
    return { outcome: 'manual_review', extracted_fields: fields, ocr_text: 'private OCR 900101-07-1234' };
  });
  const pair = body => request(app).post('/api/v1/users/me/verification/check-pair').set(renter).send(body);
  const original = await pair({ frontDocumentRef: front, backDocumentRef: back }).expect(200);
  assert.equal(original.body.data.accepted, true);
  const replaced = await pair({ frontDocumentRef: 'upload://UPL-NEWFRONT', backDocumentRef: back }).expect(200);
  assert.equal(replaced.body.data.accepted, false);
  assert.equal(replaced.body.data.status, 'mismatched');
  assert.deepEqual(calls, [['old-front', 'retained-back'], ['new-front', 'retained-back']]);
  assert.equal((await UserModel.findById(userId)).verification.history.length, 0);
  assert.equal(await adminModule.PlatformSettingModel.countDocuments({}), 0);
  for (const response of [original, replaced]) {
    assert.ok(!JSON.stringify(response.body).includes('900101'));
    assert.ok(!JSON.stringify(response.body).includes('ocr_text'));
  }
  const submission = await request(app).post('/api/v1/users/me/verification').set(renter)
    .send({ documentType: 'mykad', documentRefs: ['upload://UPL-NEWFRONT', back] }).expect(200);
  assert.equal(submission.body.data.verification.status, 'resubmission_required');
  assert.deepEqual(calls.at(-1), ['new-front', 'retained-back']);
});

for (const invalid of ['foreign', 'purpose', 'missing']) {
  test('draft pair rejects ' + invalid + ' uploads before inference', async t => {
    if (invalid === 'missing') await UploadAssetModel.deleteOne({ publicId: 'UPL-TESTBACK' });
    else await UploadAssetModel.updateOne({ publicId: 'UPL-TESTBACK' },
      invalid === 'foreign' ? { uploadedBy: 'other-user' } : { purpose: 'listing_image' });
    t.mock.method(aiClient, 'verifyDocument', async () => assert.fail('No inference for invalid refs'));
    await request(app).post('/api/v1/users/me/verification/check-pair').set(renter)
      .send({ frontDocumentRef: front, backDocumentRef: back }).expect(400);
  });
}

test('draft pair fails closed on unavailable and old AI and rejects client match claims', async t => {
  t.mock.method(storageAdapter, 'download', async () => Buffer.from('synthetic pixels'));
  const inference = t.mock.method(aiClient, 'verifyDocument', async () => ({ outcome: 'unavailable' }));
  const route = '/api/v1/users/me/verification/check-pair';
  const body = { frontDocumentRef: front, backDocumentRef: back };
  const authMode = env.authMode;
  env.authMode = 'auth0';
  try { await request(app).post(route).send(body).expect(401); }
  finally { env.authMode = authMode; }
  for (const invalid of [{ ...body, matched: true }, { ...body, frontIdentityNumber: '900101071234' },
    { ...body, backDocumentRef: front }, { ...body, frontDocumentRef: 'https://example.invalid/photo.png' }]) {
    await request(app).post(route).set(renter).send(invalid).expect(422);
  }
  const unavailable = await request(app).post(route).set(renter).send(body).expect(200);
  assert.equal(unavailable.body.data.accepted, false);
  assert.equal(unavailable.body.data.status, 'unavailable');
  inference.mock.mockImplementation(async () => ({ outcome: 'manual_review', extracted_fields: {
    mykadSidesConsistent: true, mandatoryMykadValidation: { method: 'old', accepted: true, status: 'matched' }
  } }));
  const old = await request(app).post(route).set(renter).send(body).expect(200);
  assert.equal(old.body.data.accepted, false);
  assert.equal((await UserModel.findById(userId)).verification.history.length, 0);
});
test('already approved identity is not automatically revoked', async t => {
  await UserModel.updateOne({ _id: userId }, {
    'verification.status': 'approved',
    'verification.documents': [{ documentType: 'mykad', status: 'approved' }] });
  mockAnalysis(t, {});
  await submission().expect(409);
  assert.equal((await UserModel.findById(userId)).verification.status, 'approved');
});

test('resubmission does not permit deleting protected historical photos', async t => {
  mockAnalysis(t, {});
  const result = await submission().expect(200);
  assert.equal(result.body.data.verification.status, 'resubmission_required');
  const deletion = await request(app).delete('/api/v1/uploads/UPL-TESTFRONT').set(renter).expect(409);
  assert.equal(deletion.body.error.code, 'UPLOAD_IN_USE');
  assert.ok(await UploadAssetModel.exists({ publicId: 'UPL-TESTFRONT' }));
  const saved = await UserModel.findById(userId);
  assert.deepEqual([...saved.verification.history[0].documentRefs], [front, back]);
});

