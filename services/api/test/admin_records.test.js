import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { adminModule } from '../src/modules/admin/index.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { adminRecordRegistry, createAdminRecordsService } from '../src/modules/admin/adminRecords.service.js';
import { resolveKycRequirement } from '../src/modules/user/kycRequirements.js';

const headers = { 'x-user-id': 'admin-reader', 'x-user-roles': 'admin', 'x-user-name': 'Test Administrator', 'x-user-email': 'admin@example.test' };
const registry = adminRecordRegistry(adminModule.Model);
const service = createAdminRecordsService(adminModule.Model);
let mongo;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); });
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all([...new Set(Object.values(registry).map(row => row.model)), adminModule.PlatformSettingModel].map(model => model.deleteMany({})));
});

test('record routes and dashboard require administrator authorization', async () => {
  for (const path of ['/admin/records/users', '/admin/records/users/missing', '/admin/dashboard-summary']) {
    const response = await request(app).get(`/api/v1${path}`).set({ ...headers, 'x-user-roles': 'owner' });
    assert.equal(response.status, 403);
  }
  const previous = env.authMode;
  try { env.authMode = 'local'; assert.equal((await request(app).get('/api/v1/admin/records/users')).status, 401); }
  finally { env.authMode = previous; }
});

test('every approved record type lists and opens its actual stored record without writes', async () => {
  for (const [type, { model }] of Object.entries(registry)) {
    const id = new mongoose.Types.ObjectId();
    await model.collection.insertOne({ _id: id, publicId: `TEST-${type}`, authId: `account-${type}`, displayName: 'Aisha 李', email: `${type}@example.test`, createdAt: new Date('2026-10-28T06:30:00Z'), verification: { status: 'pending', documentType: 'mykad' }, status: 'pending' });
    const listed = await service.list(type);
    assert.ok(listed.items.some(row => row._id === String(id)), type);
    const response = await request(app).get(`/api/v1/admin/records/${type}/${id}`).set(headers);
    assert.equal(response.status, 200, type);
    assert.equal(response.body.data.record._id, String(id));
    assert.equal(response.body.data.recordType, type);
  }
  assert.equal(await adminModule.Model.countDocuments(), 1, 'only explicitly inserted audit fixture exists');
});

test('user details resolve MongoDB ID and account ID and keep identity secrets private', async () => {
  const inserted = await UserModel.collection.insertOne({ authId: 'reader-user', displayName: 'Nur Aisyah', email: 'nur@example.test', phone: '', accountStatus: 'active', passwordHash: 'PRIVATE', verifiedIdentityFingerprint: 'PRIVATE', verification: { status: 'pending', documentType: 'mykad', identityFingerprint: 'PRIVATE', ocrResult: { rawText: 'PRIVATE', extractedFields: { icNumber: 'PRIVATE' }, outcome: 'manual_review' }, history: [{ attemptId: 'A1', status: 'pending', documentType: 'mykad', identityFingerprint: 'PRIVATE', aiEvidence: { outcome: 'manual_review', rawText: 'PRIVATE', extracted_fields: { ic_number: 'PRIVATE' } } }] } });
  for (const id of [String(inserted.insertedId), 'reader-user']) {
    const { record } = await service.get('users', id);
    assert.equal(record.displayName, 'Nur Aisyah'); assert.equal(record.email, 'nur@example.test');
    assert.ok(!JSON.stringify(record).includes('PRIVATE'));
    assert.equal(record.verification.history[0].attemptId, 'A1');
  }
});

test('licence review receives current MyKad status without private document data', async () => {
  const variants = [
    ['current-approved', { documentType: 'driving_licence', status: 'pending', documents: [{ documentType: 'mykad', status: 'approved', identityFingerprint: 'PRIVATE' }] }, 'approved'],
    ['legacy-approved', { documentType: 'mykad', status: 'approved' }, 'approved'],
    ['current-rejected', { documentType: 'mykad', status: 'approved', documents: [{ documentType: 'mykad', status: 'rejected' }] }, 'rejected'],
    ['history-only', { documentType: 'driving_licence', status: 'pending', history: [{ documentType: 'mykad', status: 'approved' }] }, 'unverified'],
    ['passport-only', { documentType: 'passport', status: 'approved' }, 'unverified'],
    ['reset', { documentType: 'mykad', status: 'unverified', history: [{ documentType: 'mykad', status: 'approved' }] }, 'unverified'],
  ];
  for (const [authId, verification, expected] of variants) {
    await UserModel.collection.insertOne({ authId, email: `${authId}@example.test`, displayName: 'Licence applicant', verification, drivingEligibility: { status: 'pending' } });
    for (const type of ['users', 'verification']) {
      const response = await request(app).get(`/api/v1/admin/records/${type}/${authId}`).set(headers);
      assert.equal(response.status, 200);
      const row = response.body.data.record;
      assert.equal(row.mykadIdentityStatus, expected, authId);
      assert.equal(row.verification.documents, undefined);
      assert.ok(!JSON.stringify(row).includes('PRIVATE'));
    }
    assert.equal((await UserModel.findOne({ authId }).lean()).drivingEligibility.status, 'pending', 'display does not approve a licence');
  }
  const listed = await service.list('verification');
  assert.equal(listed.items.find(row => row.authId === 'current-approved').mykadIdentityStatus, 'approved');
});

test('dashboard chart counts stored booking states beyond a page and separates unpaid requests', async () => {
  const empty = await service.summary();
  assert.equal(empty.bookings, 0);
  assert.ok(Object.values(empty.bookingStatusCounts).every(count => count === 0));
  await BookingModel.collection.insertMany([
    ...Array.from({ length: 25 }, (_, index) => ({ status: 'pending', ...(index % 2 ? { paymentStatus: 'unpaid' } : {}) })),
    { status: 'pending', paymentStatus: 'authorized' },
    { status: 'pending', paymentStatus: 'captured' },
    ...['approved', 'active', 'completed', 'disputed', 'cancelled', 'rejected', 'expired'].map(status => ({ status, listingType: 'service', sourceType: 'demo_seed' })),
    { status: 'legacy-unknown' },
  ].map((row, index) => ({ ...row, publicId: `DASHBOARD-${index}` })));
  const response = await request(app).get('/api/v1/admin/dashboard-summary').set(headers);
  assert.equal(response.status, 200);
  const summary = response.body.data;
  assert.equal(summary.bookings, 35);
  assert.deepEqual(summary.bookingStatusCounts, {
    awaitingPayment: 25, awaitingOwner: 2, approved: 1, active: 1,
    completed: 1, disputed: 1, cancelled: 1, rejected: 1, expired: 1, other: 1,
  });
  assert.equal(Object.values(summary.bookingStatusCounts).reduce((sum, count) => sum + count, 0), summary.bookings);
  assert.equal((await service.list('bookings', { limit: '10' })).items.length, 10);
  assert.equal((await service.summary()).bookings, 35);
});

test('dashboard payouts count only successful Owner settlements in Malaysia calendar months', async () => {
  const now = new Date();
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit' }).formatToParts(now).map(part => [part.type, part.value]));
  const start = new Date(Date.UTC(+parts.year, +parts.month - 1, 1) - 8 * 3600000);
  const records = [
    { type: 'owner_settlement', status: 'succeeded', amount: 42.25, createdAt: start },
    { type: 'owner_settlement', status: 'succeeded', amount: 10.10, createdAt: start },
    { type: 'owner_settlement', status: 'succeeded', amount: 7, createdAt: new Date(start.getTime() - 1) },
    { type: 'capture', status: 'succeeded', amount: 500, createdAt: start },
    { type: 'owner_settlement', status: 'failed', amount: 500, createdAt: start },
  ];
  await PaymentModel.collection.insertMany(records.map((row, index) => ({ ...row, publicId: `PAYOUT-${index}`, idempotencyKey: `payout-test:${index}`, simulated: true })));
  const { ownerPayouts } = await service.summary();
  assert.equal(ownerPayouts.months.length, 6);
  assert.equal(ownerPayouts.includesSimulated, true);
  assert.deepEqual(ownerPayouts.months.at(-1), { month: `${parts.year}-${parts.month}`, amount: 52.35, count: 2 });
  assert.equal(ownerPayouts.months.at(-2).amount, 7);
});

test('admin licence hints preserve extracted expiry and classes without exposing OCR identity data', async () => {
  const evidence = { outcome: 'manual_review', identityMatch: 'matched', ocr_text: 'PRIVATE',
    extracted_fields: { identityNumber: 'PRIVATE', name: 'PRIVATE', expiryDateText: 'PRIVATE' },
    drivingAssistance: { validUntil: '2035-12-31', licenceClasses: ['D', 'B2', 'D', 'PRIVATE'], rawText: 'PRIVATE', identityNumber: 'PRIVATE' } };
  await UserModel.collection.insertOne({ authId: 'expiry-review', email: 'expiry@example.test',
    verification: { documentType: 'driving_licence', status: 'pending', ocrResult: evidence,
      history: [
        { attemptId: 'identity', documentType: 'mykad', status: 'approved', aiEvidence: evidence },
        { attemptId: 'licence-new', documentType: 'driving_licence', status: 'pending', aiEvidence: evidence },
      ] } });
  for (const type of ['users', 'verification']) {
    const response = await request(app).get(`/api/v1/admin/records/${type}/expiry-review`).set(headers);
    assert.equal(response.status, 200);
    const row = response.body.data.record;
    const expected = { validUntil: '2035-12-31', licenceClasses: ['D', 'B2'] };
    assert.deepEqual(row.verification.history[1].aiEvidence.drivingAssistance, expected);
    assert.deepEqual(row.verification.ocrResult.drivingAssistance, expected, 'legacy top-level licence evidence also works');
    assert.equal(row.verification.history[0].aiEvidence.drivingAssistance, undefined, 'MyKad is not licence evidence');
    assert.ok(!JSON.stringify(row).includes('PRIVATE'));
    assert.equal(row.verification.history[1].status, 'pending');
  }
});

test('admin expiry hints accept real calendar dates only and do not guess from OCR text', async () => {
  const cases = [
    ['2036-02-29', '2036-02-29'], ['2035-02-29', null], ['2035-02-31', null],
    ['31/12/2035', null], ['2035-12-31T00:00:00Z', null], [null, null], [1234, null],
  ];
  for (const [index, [validUntil, expected]] of cases.entries()) {
    const authId = `expiry-${index}`;
    await UserModel.collection.insertOne({ authId, email: `${authId}@example.test`, verification: {
      documentType: 'driving_licence', status: 'pending',
      history: [{ attemptId: 'latest', documentType: 'driving_licence', status: 'pending', aiEvidence: {
        extracted_fields: { validUntil, expiryDateText: '31 December 2035', identityNumber: 'PRIVATE' },
      } }],
    } });
    const { record } = await service.get('verification', authId);
    assert.equal(record.verification.history[0].aiEvidence.drivingAssistance.validUntil, expected);
    assert.ok(!JSON.stringify(record).includes('PRIVATE'));
  }
});

test('paging is database-wide, filtered before counts and stable beyond old fixed limits', async () => {
  await UserModel.collection.insertMany(Array.from({ length: 125 }, (_, index) => ({ authId: `page-${index}`, displayName: `Person ${String(index).padStart(3, '0')}`, email: `${index}@example.test`, accountStatus: index % 2 ? 'suspended' : 'active', createdAt: new Date('2026-10-28T06:30:00Z') })));
  const first = await service.list('users', { page: '1', limit: '50' });
  const third = await service.list('users', { page: '3', limit: '50' });
  assert.equal(first.meta.total, 125); assert.equal(third.items.length, 25);
  assert.equal(new Set([...first.items, ...third.items].map(row => row.id)).size, 75);
  assert.deepEqual((await service.list('users', { page: '1', limit: '50' })).items.map(row => row.id), first.items.map(row => row.id));
  const filtered = await service.list('users', { status: 'suspended', page: '2', limit: '20' });
  assert.equal(filtered.meta.total, 62); assert.equal(filtered.items.length, 20);
  assert.equal((await service.list('users', { search: 'Person 12', limit: '20' })).meta.total, 5);
  assert.equal((await service.summary()).users, 125);
});

test('verification browsing includes reviewed submissions and filters current document states', async () => {
  const rows = [
    { authId: 'approved', verification: { documentType: 'mykad', status: 'approved', history: [{documentType:'mykad',status:'pending'},{documentType:'mykad',status:'approved'}] } },
    { authId: 'rejected', verification: { documentType: 'mykad', status: 'rejected' } },
    { authId: 'resubmit', verification: { documentType: 'mykad', status: 'resubmission_required' } },
    { authId: 'pending', verification: { documentType: 'mykad', status: 'pending' } },
    { authId: 'licence', drivingEligibility: { status: 'approved' } },
    { authId: 'unsubmitted', verification: { status: 'unverified' } },
  ];
  await UserModel.collection.insertMany(rows.map(row => ({...row, email:`${row.authId}@example.test`,displayName:row.authId,createdAt:new Date()})));
  const all = await service.list('verification');
  assert.equal(all.meta.total,5);
  assert.ok(!all.items.some(row=>row.authId==='unsubmitted'));
  const approved = await service.list('verification',{status:'approved'});
  assert.deepEqual(approved.items.map(row=>row.authId).sort(),['approved','licence']);
  assert.equal(approved.items.find(row=>row.authId==='approved').verificationSummary[0].status,'approved');
  const pending = await service.list('verification',{status:'pending'});
  assert.deepEqual(pending.items.map(row=>row.authId),['pending'],'past pending attempts must not reappear as current work');
  assert.equal((await service.summary()).verification,1);
  const licence = await service.list('verification',{status:'approved',documentType:'driving_licence'});
  assert.deepEqual(licence.items.map(row=>row.authId),['licence']);
  assert.equal((await service.list('verification',{status:'approved',documentType:'mykad'})).meta.total,1);
  assert.equal((await service.list('verification',{status:'rejected'})).meta.total,1);
  assert.equal((await service.list('verification',{status:'resubmission_required'})).meta.total,1);
  await assert.rejects(service.list('verification',{status:'banned'}), error=>error.status===422);
});

test('verification filters count and paginate reviewed records beyond the first page', async () => {
  await UserModel.collection.insertMany(Array.from({length:27},(_,index)=>({authId:`verified-${index}`,email:`verified-${index}@example.test`,displayName:`Verified ${index}`,verification:{documentType:'mykad',status:'approved'},createdAt:new Date()})));
  const page = await service.list('verification',{status:'approved',page:'2',limit:'20'});
  assert.equal(page.meta.total,27); assert.equal(page.items.length,7);
  assert.ok(page.items.every(row=>row.verificationSummary[0].status==='approved'));
});

test('historical verification remains visible without presenting a reset status as approved', async () => {
  await UserModel.collection.insertOne({authId:'past-review',email:'past-review@example.test',verification:{documentType:'mykad',status:'unverified',history:[{documentType:'mykad',status:'approved'}]}});
  const records = await service.list('verification');
  assert.equal(records.meta.total,1);
  assert.equal(records.items[0].verificationSummary[0].status,'unverified');
  assert.equal((await service.list('verification',{status:'approved'})).meta.total,0);
  assert.equal((await service.get('verification','past-review')).record.verificationSummary[0].status,'unverified');
});

test('registry and pagination reject arbitrary collections, invalid filters and malformed inputs', async () => {
  for (const type of ['passwords', '__proto__', 'constructor']) await assert.rejects(service.list(type), error => error.statusCode === 404 || error.status === 404);
  await assert.rejects(service.list('users', { search: {} }), error => error.status === 422);
  for (const query of [{ page: '0' }, { limit: '101' }, { limit: '2.5' }, { status: 'not-a-status' }, { documentType: 'passport' }]) {
    const response = await request(app).get('/api/v1/admin/records/users').query(query).set(headers);
    assert.equal(response.status, 422, JSON.stringify(query));
  }
  assert.equal((await request(app).get('/api/v1/admin/records/users/no-record').set(headers)).status, 404);
});

test('rental display uses saved booking names and lifecycle fields, not present-day profiles', async () => {
  await BookingModel.collection.insertOne({ publicId: 'RH-BKG-2026-SNAPSHOT', listingTitle: 'Camera at booking', renterName: 'Renter at booking', ownerName: 'Owner at booking' });
  const { insertedId } = await registry.rentals.model.collection.insertOne({ publicId: 'R1', bookingId: 'RH-BKG-2026-SNAPSHOT', renterId: 'r1', ownerId: 'o1', listingType: 'physical', returnSubmission: { notes: 'Returned with case' }, extensionHistory: [{ status: 'approved', extraDays: 2 }] });
  const { record } = await service.get('rentals', String(insertedId));
  assert.equal(record.listingTitle, 'Camera at booking'); assert.equal(record.ownerName, 'Owner at booking');
  assert.equal(record.returnSubmission.notes, 'Returned with case'); assert.equal(record.extensionHistory[0].extraDays, 2);
});

test('audit detail has readable safe metadata and excludes arbitrary internals', async () => {
  const { insertedId } = await adminModule.Model.collection.insertOne({ action: 'user.status_changed', metadata: { reason: 'Review requested', password: 'PRIVATE', debugPath: 'PRIVATE', rawText: 'PRIVATE' } });
  const { record } = await service.get('audit-logs', String(insertedId));
  assert.deepEqual(record.metadata, { reason: 'Review requested' });
});

test('message text, dispute allocations and review ratings survive approved detail projections', async () => {
  const message = await registry['message-reports'].model.collection.insertOne({ messageText: 'Please review this reported message.', resolution: 'Reviewed', reporterId: 'reporter' });
  assert.equal((await service.get('message-reports', String(message.insertedId))).record.messageText, 'Please review this reported message.');
  const dispute = await registry.disputes.model.collection.insertOne({ resolution: { outcome: 'split', renterAmount: 30, ownerAmount: 70, notes: 'Allocate remaining funds', simulatedSettlement: true } });
  const decision = (await service.get('disputes', String(dispute.insertedId))).record.resolution;
  assert.equal(decision.renterAmount, 30); assert.equal(decision.ownerAmount, 70); assert.equal(decision.simulatedSettlement, true);
  const review = await registry.reviews.model.collection.insertOne({ overallRating: 4, communicationRating: 5, valueRating: 3 });
  assert.equal((await service.get('reviews', String(review.insertedId))).record.communicationRating, 5);
});

test('Passport is unavailable for new settings or submissions; historical records remain readable', async () => {
  const settings = await adminModule.service.getSettings();
  const rules = settings.kycRequirements.map(row => ({ ...row, documentTypes: ['mykad', 'passport'] }));
  const response = await request(app).put('/api/v1/admin/settings').set(headers).send({ kycRequirements: rules });
  assert.equal(response.status, 422);
  await adminModule.PlatformSettingModel.updateOne({ key: 'platform' }, { $set: { 'kycRequirements.0.documentTypes': ['mykad', 'passport'] } });
  assert.ok(!(await adminModule.service.getSettings()).kycRequirements.flatMap(row => row.documentTypes).includes('passport'));
  const { insertedId } = await UserModel.collection.insertOne({ authId: 'legacy', verification: { status: 'approved', documentType: 'passport' } });
  assert.equal((await service.get('users', String(insertedId))).record.verification.documentType, 'passport');
  assert.ok((await adminModule.PlatformSettingModel.findOne({ key: 'platform' })).kycRequirements[0].documentTypes.includes('passport'), 'read does not migrate stored history');
  assert.deepEqual(resolveKycRequirement({ kycRequirements: rules }, { category: 'Devices' }).requiredDocumentTypes, ['mykad']);
});
