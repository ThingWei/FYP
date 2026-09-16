import test, { after, before, beforeEach } from 'node:test';
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

let mongodb;

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
    });
  assert.equal(resolved.status, 200, JSON.stringify(resolved.body));
  assert.equal(resolved.body.data.status, 'resolved');
  assert.equal(resolved.body.data.resolution.simulatedSettlement, true);
  assert.match(
    resolved.body.data.resolution.mockBlockchainReference,
    /^MOCK-CHAIN-RH-DSP-/,
  );
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
