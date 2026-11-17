import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { ClaimModel } from '../src/modules/dispute/claim.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { MessageModel } from '../src/modules/communication/message.model.js';
import { adminModule } from '../src/modules/admin/index.js';

const id = 'RH-DSP-WORKSPACE';
const headers = role => ({ 'x-user-id': role, 'x-user-name': role, 'x-user-email': `${role}@example.test`, 'x-user-roles': role });
let mongo;
const models = [DisputeModel, ClaimModel, BookingModel, RentalModel, PaymentModel, UserModel, ThreadModel, MessageModel, adminModule.Model];
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await Promise.all(models.map(model => model.init())); });
after(async () => { await disconnectDatabase(); await mongo?.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(model => model.deleteMany({})));
  await UserModel.create(['admin', 'owner'].map(authId => ({ authId, displayName: authId, email: `${authId}@example.test`, roles: authId === 'admin' ? ['admin'] : ['renter', 'owner'], activeRole: authId })));
  await DisputeModel.create({ publicId: id, rentalId: 'RNT-ONE', bookingId: 'RH-BKG-2026-ONE', listingId: 'l-one', listingTitle: 'Camera', listingType: 'physical',
    raisedById: 'owner', raisedByName: 'Saved Owner', raisedByRole: 'owner', respondentId: 'renter', respondentName: 'Saved Renter', respondentRole: 'renter',
    category: 'damaged_item', summary: 'Body damage', description: 'Damage is visible on the returned camera body.', status: 'under_review',
    previousBookingStatus: 'active', previousRentalStatus: 'active', evidence: ['upload://UPL-CASE'],
    responses: Array.from({ length: 25 }, (_, index) => ({ userId: 'renter', role: 'renter', text: `Response ${index}`, evidence: [], submittedAt: new Date(1700000000000 + index) })) });
  await BookingModel.collection.insertOne({ publicId: 'RH-BKG-2026-ONE', status: 'disputed', ownerId: 'owner', renterId: 'renter', ownerName: 'Saved Owner', renterName: 'Saved Renter',
    startDate: new Date('2026-11-01'), endDate: new Date('2026-11-03'), pricing: { total: 150, baseAmount: 100, securityDeposit: 50 }, paymentStatus: 'captured',
    paymentLeaseToken: 'PRIVATE-LEASE', pickupLocationSnapshot: { displayAddress: 'PRIVATE ADDRESS' } });
  await RentalModel.collection.insertOne({ publicId: 'RNT-ONE', status: 'disputed', handover: { condition: 'Good', notes: 'Before handover', evidence: ['upload://UPL-HAND'], acknowledgedAt: new Date() },
    returnSubmission: { condition: 'Damaged', evidence: ['upload://UPL-RETURN'] }, lifecycleRevision: 999 });
  await ClaimModel.collection.insertOne({ publicId: 'RH-CLM-ONE', disputeId: id, rentalId: 'RNT-ONE', bookingId: 'RH-BKG-2026-ONE', listingTitle: 'Camera', ownerId: 'owner', renterId: 'renter',
    amountRequested: 40, description: 'Repair for the returned item.', evidence: ['upload://UPL-CLAIM'], status: 'pending' });
  await PaymentModel.collection.insertOne({ publicId: 'TXN-CAP-ONE', bookingId: 'RH-BKG-2026-ONE', status: 'succeeded', type: 'capture', amount: 150, gatewayReference: 'PRIVATE-GATEWAY' });
  await ThreadModel.collection.insertMany([{ publicId: 'THR-ONE', bookingId: 'RH-BKG-2026-ONE' }, { publicId: 'THR-OTHER', bookingId: 'RH-BKG-2026-OTHER' }]);
  await MessageModel.collection.insertMany(Array.from({ length: 25 }, (_, index) => ({ publicId: `MSG-${index}`, threadId: 'THR-ONE', senderId: 'renter', text: `Message ${index}`,
    createdAt: new Date(1700000000000 + index), originalContent: { text: 'PRIVATE-ORIGINAL' }, editHistory: [{ text: 'PRIVATE-EDIT' }] })));
  await MessageModel.collection.insertOne({ publicId: 'MSG-FOREIGN', threadId: 'THR-OTHER', senderId: 'renter', text: 'UNRELATED BOOKING', createdAt: new Date() });
  await adminModule.Model.create(Array.from({ length: 25 }, (_, index) => ({ actorId: 'admin', createdBy: 'admin', action: 'dispute.under_review', targetType: 'dispute', targetId: id,
    metadata: { note: `Update ${index}`, secret: 'PRIVATE-METADATA' } })));
});

test('case workspace is admin-only, projected and read-only', async () => {
  await request(app).get(`/api/v1/admin/cases/${id}`).set(headers('owner')).expect(403);
  const before = await Promise.all([DisputeModel.findOne().lean(), BookingModel.findOne().lean(), RentalModel.findOne().lean(), PaymentModel.countDocuments(), adminModule.Model.countDocuments()]);
  const result = (await request(app).get(`/api/v1/admin/cases/${id}`).set(headers('admin')).expect(200)).body.data;
  assert.equal(result.claim.publicId, 'RH-CLM-ONE');
  assert.equal(result.balance.held, 150); assert.equal(result.actions.canResolve, true);
  assert.equal(result.responseCount, 25); assert.equal(result.record.responses, undefined);
  assert.deepEqual(result.rental.returnSubmission.evidence, ['upload://UPL-RETURN']);
  assert.ok(!JSON.stringify(result).includes('PRIVATE')); assert.equal(result.rental.lifecycleRevision, undefined);
  assert.deepEqual(await Promise.all([DisputeModel.findOne().lean(), BookingModel.findOne().lean(), RentalModel.findOne().lean(), PaymentModel.countDocuments(), adminModule.Model.countDocuments()]), before);
});
test('conversation and activity paginate beyond the first batch and isolate booking context', async () => {
  const first = (await request(app).get(`/api/v1/admin/cases/${id}/conversation?limit=20&page=1`).set(headers('admin')).expect(200)).body;
  const second = (await request(app).get(`/api/v1/admin/cases/${id}/conversation?limit=20&page=2`).set(headers('admin')).expect(200)).body;
  assert.equal(first.meta.total, 25); assert.equal(second.data.length, 5);
  assert.equal(new Set([...first.data, ...second.data].map(row => row.id)).size, 25);
  assert.equal(first.data[0].senderName, 'Saved Renter'); assert.ok(!JSON.stringify(first).includes('PRIVATE'));
  assert.ok(!JSON.stringify(first).includes('UNRELATED'));
  const events = (await request(app).get(`/api/v1/admin/cases/${id}/activity?page=2&limit=20`).set(headers('admin')).expect(200)).body;
  assert.equal(events.meta.total, 25); assert.equal(events.data.length, 5); assert.ok(!JSON.stringify(events).includes('PRIVATE'));
  const responses = (await request(app).get(`/api/v1/admin/cases/${id}/activity?kind=responses&page=2&limit=20`).set(headers('admin')).expect(200)).body;
  assert.equal(responses.meta.total, 25); assert.equal(responses.data.length, 5);
  assert.equal(responses.data[0].authorName, 'Saved Renter');
});
test('recalled conversation content stays protected and missing records remain explicit', async () => {
  await MessageModel.updateOne({ publicId: 'MSG-24' }, { $set: { recalledAt: new Date(), text: 'PRIVATE OLD TEXT', attachment: { reference: 'upload://UPL-PRIVATE' } } });
  const messages = (await request(app).get(`/api/v1/admin/cases/${id}/conversation`).set(headers('admin')).expect(200)).body.data;
  assert.equal(messages[0].text, 'Message recalled'); assert.equal(messages[0].attachment, undefined);
  await RentalModel.deleteMany({});
  const result = (await request(app).get(`/api/v1/admin/cases/${id}`).set(headers('admin')).expect(200)).body.data;
  assert.equal(result.rental, null); assert.equal(result.actions.canResolve, false);
  await request(app).get('/api/v1/admin/cases/RH-DSP-MISSING').set(headers('admin')).expect(404);
  for (const query of ['page=0', 'limit=51', 'page=hello', 'kind=arbitrary']) {
    await request(app).get(`/api/v1/admin/cases/${id}/activity?${query}`).set(headers('admin')).expect(422);
  }
});
test('closed decisions and unfunded claim outcomes are visible without enabling repeated decisions', async () => {
  await DisputeModel.updateOne({ publicId: id }, { $set: { status: 'resolved', resolution: { outcome: 'release_to_renter', renterAmount: 150, ownerAmount: 0, notes: 'Recorded decision', resolvedAt: new Date() } } });
  await ClaimModel.updateOne({ publicId: 'RH-CLM-ONE' }, { $set: { status: 'approved', decision: { approvedAmount: 40, payoutStatus: 'pending_funding', reason: 'Claim approved' } } });
  const result = (await request(app).get(`/api/v1/admin/cases/${id}`).set(headers('admin')).expect(200)).body.data;
  assert.equal(result.actions.canUpdate, false); assert.equal(result.actions.canDecideClaim, false);
  assert.equal(result.claim.decision.payoutStatus, 'pending_funding');
});
