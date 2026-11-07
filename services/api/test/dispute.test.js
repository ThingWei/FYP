import test, { after, afterEach, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { adminModule } from '../src/modules/admin/index.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { ClaimModel } from '../src/modules/dispute/claim.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from '../src/modules/loyalty/loyalty.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { blockchainAdapter } from '../src/integrations/blockchainAdapter.js';
import { LifecycleOperationModel } from '../src/operations/lifecycleJournal.js';

let mongodb;
const originalOpenDispute = blockchainAdapter.openDispute;
const originalComplete = blockchainAdapter.complete;
afterEach(() => {
  blockchainAdapter.openDispute = originalOpenDispute;
  blockchainAdapter.complete = originalComplete;
});

const identity = (id, roles, name) => ({
  'x-user-id': id,
  'x-user-email': `${id}@renthub.my`,
  'x-user-name': name,
  'x-user-roles': roles,
});

const renter = identity('u-renter', 'renter', 'Alex Tan');
const owner = identity('u-owner', 'owner', 'Sarah J.');
const outsider = identity('u-outsider', 'renter', 'Mei Lin');
const admin = identity('u-admin', 'admin', 'Admin Farah');

async function seedProfiles() {
  for (const headers of [renter, owner, outsider, admin]) {
    const response = await request(app).post('/api/v1/users/session').set(headers);
    assert.equal(response.status, 201);
  }
}

async function seedRental(type = 'physical') {
  const physical = type === 'physical';
  const bookingId = physical ? 'RH-BKG-2026-DSP001' : 'RH-SVC-2026-DSP002';
  const rentalId = physical ? 'RH-RNT-2026-DSP001' : 'RH-RNT-2026-DSP002';
  await BookingModel.create({
    publicId: bookingId,
    listingId: physical ? 'l-camera' : 'l-photo',
    listingTitle: physical ? 'Sony Alpha Camera' : 'Event Photography Package',
    listingType: type,
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-owner',
    startDate: new Date('2026-09-20'),
    endDate: new Date('2026-09-22'),
    ...(physical ? { fulfilmentMethod: 'pickup' } : { serviceVenue: 'Petaling Jaya' }),
    damageWaiverSelected: physical,
    pricing: {
      baseAmount: physical ? 255 : 450,
      securityDeposit: physical ? 300 : 0,
      damageWaiverFee: physical ? 15 : 0,
      platformFee: 0,
      total: physical ? 570 : 450,
      currency: 'MYR',
    },
    paymentStatus: 'captured',
    status: 'active',
  });
  await RentalModel.create({
    publicId: rentalId,
    bookingId,
    listingId: physical ? 'l-camera' : 'l-photo',
    listingType: type,
    renterId: 'u-renter',
    ownerId: 'u-owner',
    startDate: new Date('2026-09-20'),
    endDate: new Date('2026-09-22'),
    status: 'active',
  });
  await PaymentModel.create({ publicId: `TXN-CAP-${physical ? 'DSP1' : 'DSP2'}`, bookingId,
    payerId: 'u-renter', payeeId: 'u-owner', type: 'capture', amount: physical ? 570 : 450,
    status: 'succeeded', method: 'card', gatewayReference: 'sim_capture_fixture', idempotencyKey: `fixture:${bookingId}` });
  return { bookingId, rentalId };
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    BookingModel.init(),
    RentalModel.init(),
    DisputeModel.init(),
    ClaimModel.init(),
    NotificationModel.init(),
    adminModule.Model.init(),
    LoyaltyAccountModel.init(),
    LoyaltyConfigModel.init(),
    ReferralModel.init(),
    RewardLedgerModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    PaymentModel.deleteMany({}),
    BookingModel.deleteMany({}),
    RentalModel.deleteMany({}),
    DisputeModel.deleteMany({}),
    ClaimModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    adminModule.Model.deleteMany({}),
    LoyaltyAccountModel.deleteMany({}),
    LoyaltyConfigModel.deleteMany({}),
    ReferralModel.deleteMany({}),
    RewardLedgerModel.deleteMany({}),
    LifecycleOperationModel.deleteMany({}),
  ]);
  await seedProfiles();
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('opens a participant-only physical dispute and prevents duplicates', async () => {
  const { rentalId, bookingId } = await seedRental();
  const opened = await request(app).post('/api/v1/disputes').set(renter).send({
    rentalId,
    category: 'damaged_item',
    summary: 'Lens damage was found',
    description: 'The lens casing was scratched when the item was returned.',
    evidence: ['evidence://return-photo-1'],
  });
  assert.equal(opened.status, 201, JSON.stringify(opened.body));
  assert.equal(opened.body.data.status, 'awaiting_response');
  assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'disputed');
  assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, 'disputed');

  const hidden = await request(app)
    .get(`/api/v1/disputes/${opened.body.data.id}`)
    .set(outsider);
  assert.equal(hidden.status, 404);
  const duplicate = await request(app).post('/api/v1/disputes').set(owner).send({
    rentalId,
    category: 'return_condition',
    summary: 'Duplicate dispute',
    description: 'This second dispute should be rejected by the API.',
  });
  assert.equal(duplicate.status, 409);
});

test('handles responses, damage claims and simulated admin resolution', async () => {
  const { rentalId } = await seedRental();
  const opened = await request(app).post('/api/v1/disputes').set(renter).send({
    rentalId,
    category: 'return_condition',
    summary: 'Return condition differs',
    description: 'The recorded return condition does not match the handover evidence.',
  });
  const id = opened.body.data.id;

  const response = await request(app)
    .post(`/api/v1/disputes/${id}/responses`)
    .set(owner)
    .send({
      text: 'I have added the inspection images and collection notes.',
      evidence: ['evidence://inspection-photo'],
    });
  assert.equal(response.status, 200);
  assert.equal(response.body.data.status, 'under_review');

  const claim = await request(app)
    .post(`/api/v1/disputes/${id}/claims`)
    .set(owner)
    .send({
      description: 'The inspection shows repairable damage to the camera body.',
      amountRequested: 150,
      evidence: ['evidence://repair-quotation'],
    });
  assert.equal(claim.status, 201, JSON.stringify(claim.body));
  assert.equal(claim.body.data.status, 'pending');
  const renterClaims = await request(app)
    .get('/api/v1/disputes/claims/mine')
    .set(renter);
  assert.equal(renterClaims.status, 200);
  assert.equal(renterClaims.body.meta.total, 1);

  const moreEvidence = await request(app)
    .patch(`/api/v1/disputes/${id}/review-status`)
    .set(admin)
    .send({
      status: 'more_evidence_required',
      note: 'Please provide a dated repair quotation.',
    });
  assert.equal(moreEvidence.status, 200);

  const adminCase = await request(app)
    .get(`/api/v1/disputes/${id}`)
    .set(admin);
  assert.equal(adminCase.status, 200);
  assert.equal(adminCase.body.data.caseContext.agreement.listingType, 'physical');
  assert.equal(adminCase.body.data.caseContext.inspection.status, 'disputed');

  const decision = await request(app)
    .patch(`/api/v1/disputes/claims/${claim.body.data.id}/decision`)
    .set(admin)
    .send({
      status: 'approved',
      approvedAmount: 120,
      reason: 'Damage evidence and quotation are consistent.',
    });
  assert.equal(decision.status, 200);
  assert.equal(decision.body.data.decision.approvedAmount, 120);

  const resolved = await request(app)
    .patch(`/api/v1/disputes/${id}/resolve`)
    .set(admin)
    .send({
      outcome: 'split',
      renterAmount: 420,
      ownerAmount: 150,
      notes: 'The evidence supports a partial deduction for repair costs.',
      responsibleParty: 'renter',
    });
  assert.equal(resolved.status, 200, JSON.stringify(resolved.body));
  assert.equal(resolved.body.data.status, 'resolved');
  assert.equal(resolved.body.data.resolution.responsibleParty, 'renter');
  assert.equal(resolved.body.data.resolution.simulatedSettlement, true);
  assert.equal(
    resolved.body.data.resolution.blockchainReference,
    'BLOCKCHAIN_UNAVAILABLE',
  );
  assert.equal(resolved.body.data.resolution.blockchainStatus, 'unavailable');
  assert.equal(await adminModule.Model.countDocuments(), 3);
  const hiddenAudit = await request(app).get('/api/v1/admin').set(renter);
  assert.equal(hiddenAudit.status, 403);
  const audit = await request(app).get('/api/v1/admin').set(admin);
  assert.equal(audit.status, 200);
  assert.equal(audit.body.meta.total, 3);
});

test('keeps service disputes free of physical-item claims and categories', async () => {
  const { rentalId } = await seedRental('service');
  const invalid = await request(app).post('/api/v1/disputes').set(renter).send({
    rentalId,
    category: 'damaged_item',
    summary: 'Invalid physical category',
    description: 'A service dispute cannot use a physical-item damage category.',
  });
  assert.equal(invalid.status, 400);

  const opened = await request(app).post('/api/v1/disputes').set(renter).send({
    rentalId,
    category: 'scope_mismatch',
    summary: 'Package scope was incomplete',
    description: 'The delivered photography package omitted the agreed edited gallery.',
  });
  assert.equal(opened.status, 201, JSON.stringify(opened.body));
  const claim = await request(app)
    .post(`/api/v1/disputes/${opened.body.data.id}/claims`)
    .set(owner)
    .send({
      description: 'Insurance should not be available for a service booking.',
      amountRequested: 100,
      evidence: ['evidence://not-applicable'],
    });
  assert.equal(claim.status, 409);
  assert.equal(claim.body.error.code, 'CLAIM_NOT_AVAILABLE');
});

const issue = (rentalId, type = 'physical') => ({ rentalId,
  category: type === 'physical' ? 'return_condition' : 'service_quality',
  summary: 'Condition needs review', description: 'Please review the item or service before confirming completion.' });
const raise = (rentalId, type = 'physical', headers = renter) =>
  request(app).post('/api/v1/disputes').set(headers).send(issue(rentalId, type));
async function prepareCompletion(rentalId, type) {
  await RentalModel.updateOne({ publicId: rentalId }, { $set: {
    status: type === 'physical' ? 'return_submitted' : 'completion_pending',
  } });
}
const finish = (rentalId, type) => type === 'physical'
  ? request(app).post(`/api/v1/rentals/${rentalId}/return/confirm`).set(owner)
    .send({ condition: 'Good', notes: 'Inspected the returned item.', depositDeduction: 0 })
  : request(app).post(`/api/v1/rentals/${rentalId}/service-completion`).set(renter);

for (const type of ['physical', 'service']) {
  test(`${type}: final completion closes new cases for both participants without side effects`, async () => {
    const { rentalId, bookingId } = await seedRental(type);
    await prepareCompletion(rentalId, type);
    await finish(rentalId, type).expect(200);
    const before = {
      rental: await RentalModel.findOne({ publicId: rentalId }).lean(),
      booking: await BookingModel.findOne({ publicId: bookingId }).lean(),
      payments: await PaymentModel.find({ bookingId }).sort({ publicId: 1 }).lean(),
      notifications: await NotificationModel.countDocuments(),
      operations: await LifecycleOperationModel.countDocuments(),
    };
    let chainCalls = 0;
    blockchainAdapter.openDispute = async (...args) => { chainCalls++; return originalOpenDispute.apply(blockchainAdapter, args); };
    for (const participant of [renter, owner]) {
      const result = await raise(rentalId, type, participant).expect(409);
      assert.equal(result.body.error.code, 'DISPUTE_WINDOW_CLOSED');
      assert.equal(result.body.error.message, 'This rental is complete, so a new dispute can no longer be opened.');
    }
    await raise(rentalId, type, outsider).expect(404);
    assert.deepEqual(await RentalModel.findOne({ publicId: rentalId }).lean(), before.rental);
    assert.deepEqual(await BookingModel.findOne({ publicId: bookingId }).lean(), before.booking);
    assert.deepEqual(await PaymentModel.find({ bookingId }).sort({ publicId: 1 }).lean(), before.payments);
    assert.equal(await DisputeModel.countDocuments(), 0);
    assert.equal(await NotificationModel.countDocuments(), before.notifications);
    assert.equal(await LifecycleOperationModel.countDocuments(), before.operations);
    assert.equal(chainCalls, 0);
  });

  for (const completedRecord of ['booking', 'rental']) {
    test(`${type}: a completed ${completedRecord} blocks cases even with a stale linked state`, async () => {
      const { rentalId, bookingId } = await seedRental(type);
      await (completedRecord === 'booking' ? BookingModel : RentalModel).updateOne(
        { publicId: completedRecord === 'booking' ? bookingId : rentalId }, { $set: { status: 'completed' } });
      for (const participant of [renter, owner]) {
        const result = await raise(rentalId, type, participant).expect(409);
        assert.equal(result.body.error.code, 'DISPUTE_WINDOW_CLOSED');
      }
      assert.equal(await DisputeModel.countDocuments(), 0);
    });
  }

  test(`${type}: completion racing a new case cannot reopen or settle a disputed rental`, async () => {
    const { rentalId, bookingId } = await seedRental(type);
    await prepareCompletion(rentalId, type);
    const results = await Promise.all([finish(rentalId, type), raise(rentalId, type)]);
    const saved = await RentalModel.findOne({ publicId: rentalId });
    if (results[0].status === 200) {
      assert.equal(results[1].status, 409);
      assert.equal(results[1].body.error.code, 'DISPUTE_WINDOW_CLOSED');
      assert.equal(saved.status, 'completed');
      assert.equal(await DisputeModel.countDocuments(), 0);
    } else {
      assert.equal(results[0].status, 409);
      assert.equal(results[1].status, 201);
      assert.equal(saved.status, 'disputed');
      assert.equal(await DisputeModel.countDocuments(), 1);
      assert.equal(await PaymentModel.countDocuments({ bookingId }), 1);
    }
    assert.equal((await BookingModel.findOne({ publicId: bookingId })).status, saved.status);
  });
}

for (const [type, status] of [['physical', 'active'], ['physical', 'overdue'],
  ['physical', 'return_submitted'], ['service', 'active'], ['service', 'completion_pending']]) {
  test(`${type}: ${status} remains disputable after its calendar end with captured payment`, async () => {
    const { rentalId } = await seedRental(type);
    await RentalModel.updateOne({ publicId: rentalId }, { $set: { status } });
    await raise(rentalId, type).expect(201);
    assert.equal((await RentalModel.findOne({ publicId: rentalId })).status, 'disputed');
  });
}

test('completed rental retains authorized access to its existing resolved case', async () => {
  const { rentalId, bookingId } = await seedRental();
  const opened = await raise(rentalId).expect(201);
  const id = opened.body.data.id;
  await DisputeModel.updateOne({ publicId: id }, { $set: { status: 'resolved' } });
  await RentalModel.updateOne({ publicId: rentalId }, { $set: { status: 'completed' } });
  await BookingModel.updateOne({ publicId: bookingId }, { $set: { status: 'completed' } });
  for (const participant of [renter, owner, admin]) {
    const read = await request(app).get(`/api/v1/disputes/${id}`).set(participant).expect(200);
    assert.equal(read.body.data.status, 'resolved');
  }
  await request(app).get(`/api/v1/disputes/${id}`).set(outsider).expect(404);
  await raise(rentalId).expect(409);
  assert.equal(await DisputeModel.countDocuments(), 1);
});
