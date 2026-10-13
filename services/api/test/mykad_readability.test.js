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

const renter = { 'x-user-id': 'kyc-test-renter', 'x-user-roles': 'renter',
  'x-user-name': 'Test User', 'x-user-email': 'renter@example.invalid' };
const admin = { 'x-user-id': 'kyc-test-admin', 'x-user-roles': 'admin',
  'x-user-name': 'Test Admin', 'x-user-email': 'admin@example.invalid' };
const front = 'upload://UPL-TESTFRONT', back = 'upload://UPL-TESTBACK';
const frame = { contentBase64: Buffer.from('synthetic camera pixels '.repeat(10)).toString('base64'),
  documentType: 'mykad', expectedSide: 'back', validateCapture: true, frontDocumentRef: front };
let mongo, userId;
before(async () => {
  mongo = await MongoMemoryServer.create();
  await connectDatabase(mongo.getUri());
  await Promise.all([UserModel.init(), UploadAssetModel.init()]);
});
after(async () => { await disconnectDatabase(); await mongo.stop(); });
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
    return { adapter: 'opencv-document-yolo-v4', available: true, ready: false,
      capture_validation: { status: 'mismatched', accepted: false } };
  });
  const response = await request(app).post('/api/v1/users/me/verification/scan-frame').set(renter).send(frame).expect(200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].referenceFront.content_base64, Buffer.from('synthetic front bytes').toString('base64'));
  assert.equal(calls[0].referenceFront.content_type, 'image/png');
  assert.ok(!JSON.stringify(response.body).includes('synthetic front bytes'));
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
for (const failure of ['missing', 'mismatch', 'unreadable_address', 'screen_copy', 'unavailable', 'old_contract', 'malformed_sides', 'null_side']) {
  test(failure + ' cannot bypass mandatory submission or admin approval', async t => {
    const fields = validMykadFields();
    if (failure === 'missing') delete fields.mandatoryMykadValidation;
    if (failure === 'mismatch') { fields.mykadSidesConsistent = false; fields.mandatoryMykadValidation.status = 'mismatched'; }
    if (failure === 'unreadable_address') fields.mandatoryMykadValidation.sides[0].requiredFields.front_address.readable = false;
    if (failure === 'screen_copy') fields.mandatoryMykadValidation.sides[0].screenCopy.status = 'detected';
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

