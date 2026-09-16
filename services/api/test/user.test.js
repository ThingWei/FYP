import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { MessageModel } from '../src/modules/communication/message.model.js';
import { MessageReportModel } from '../src/modules/communication/messageReport.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';

let mongodb;
const runFile = promisify(execFile);
const seedScript = fileURLToPath(
  new URL('../src/scripts/seed.js', import.meta.url),
);

const identity = ({
  id = 'u-renter',
  email = 'renter@renthub.my',
  name = 'Alex Tan',
  roles = 'renter',
} = {}) => ({
  'x-user-id': id,
  'x-user-email': email,
  'x-user-name': name,
  'x-user-roles': roles,
});

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await UserModel.init();
});

beforeEach(async () => {
  await UserModel.deleteMany({});
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('starts a session and creates a role-aware MongoDB profile', async () => {
  const response = await request(app)
    .post('/api/v1/users/session')
    .set(identity({ roles: 'renter,owner' }));

  assert.equal(response.status, 201);
  assert.equal(response.body.data.authId, 'u-renter');
  assert.deepEqual(response.body.data.roles, ['renter', 'owner']);
  assert.equal(response.body.data.activeRole, 'renter');

  const stored = await UserModel.findOne({ authId: 'u-renter' }).lean();
  assert.equal(stored.email, 'renter@renthub.my');
});

test('readiness reports MongoDB and the seed script is idempotent', async () => {
  const ready = await request(app).get('/api/v1/ready');
  assert.equal(ready.status, 200);
  assert.equal(ready.body.data.database.state, 'connected');

  const options = {
    env: { ...process.env, MONGODB_URI: mongodb.getUri(), AUTH_MODE: 'mock' },
  };
  await runFile(process.execPath, [seedScript], options);
  await runFile(process.execPath, [seedScript], options);

  assert.equal(await UserModel.countDocuments(), 5);
  assert.equal(await ListingModel.countDocuments(), 13);
  assert.equal(await BookingModel.countDocuments(), 3);
  assert.equal(await RentalModel.countDocuments(), 2);
  assert.equal(await PaymentModel.countDocuments(), 3);
  assert.equal(await ThreadModel.countDocuments(), 2);
  assert.equal(await MessageModel.countDocuments(), 4);
  assert.equal(await NotificationModel.countDocuments(), 4);
  assert.equal(await MessageReportModel.countDocuments(), 1);
  assert.equal(await ReviewModel.countDocuments(), 1);
  const renter = await UserModel.findOne({ authId: 'u-renter' }).lean();
  assert.equal(renter.displayName, 'Alex Tan');
  assert.equal(renter.trustScore, 92);
  const camera = await ListingModel.findOne({ publicId: 'l-camera' }).lean();
  assert.equal(camera.dailyPrice, 85);
  assert.equal(camera.securityDeposit, 300);
  const cameraBooking = await BookingModel.findOne({
    publicId: 'RH-BKG-2026-09142',
  }).lean();
  assert.equal(cameraBooking.pricing.total, 570);
  assert.equal(cameraBooking.paymentStatus, 'captured');
  const serviceBooking = await BookingModel.findOne({
    publicId: 'RH-SVC-2026-03218',
  }).lean();
  assert.equal(serviceBooking.pricing.total, 472.5);
  assert.equal(serviceBooking.paymentStatus, 'authorized');
  const cameraCapture = await PaymentModel.findOne({
    publicId: 'TXN-CAP-2026-09142',
  }).lean();
  assert.equal(cameraCapture.amount, 570);
  assert.equal(cameraCapture.status, 'succeeded');
  const cameraThread = await ThreadModel.findOne({
    bookingId: 'RH-BKG-2026-09142',
  }).lean();
  assert.deepEqual(cameraThread.participantIds, ['u-renter', 'u-owner']);
});

test('validates profile updates and role switching', async () => {
  const headers = identity({ roles: 'renter,owner' });
  await request(app).post('/api/v1/users/session').set(headers);

  const invalid = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({ displayName: '' });
  assert.equal(invalid.status, 422);
  assert.equal(invalid.body.error.code, 'VALIDATION_ERROR');

  const updated = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({
      displayName: 'Alex T.',
      addresses: [
        {
          label: 'Home',
          line1: '18 Jalan Ampang',
          city: 'Kuala Lumpur',
          state: 'Kuala Lumpur',
          postcode: '50450',
          isDefault: true,
        },
      ],
    });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.data.displayName, 'Alex T.');
  assert.equal(updated.body.data.addresses[0].postcode, '50450');

  const switched = await request(app)
    .patch('/api/v1/users/me/active-role')
    .set(headers)
    .send({ role: 'owner' });
  assert.equal(switched.status, 200);
  assert.equal(switched.body.data.activeRole, 'owner');
});

test('rejects more than one default address', async () => {
  const headers = identity();
  await request(app).post('/api/v1/users/session').set(headers);

  const address = {
    label: 'Home',
    line1: '18 Jalan Ampang',
    city: 'Kuala Lumpur',
    state: 'Kuala Lumpur',
    postcode: '50450',
    isDefault: true,
  };
  const response = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({ addresses: [address, { ...address, label: 'Office' }] });

  assert.equal(response.status, 400);
  assert.equal(response.body.error.code, 'VALIDATION_ERROR');
});

test('prevents a renter from selecting an unassigned role', async () => {
  const headers = identity();
  await request(app).post('/api/v1/users/session').set(headers);

  const response = await request(app)
    .patch('/api/v1/users/me/active-role')
    .set(headers)
    .send({ role: 'owner' });

  assert.equal(response.status, 403);
  assert.equal(response.body.error.code, 'ROLE_NOT_ASSIGNED');
});

test('blocks and unblocks an existing Owner', async () => {
  const renter = identity();
  const owner = identity({
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Sarah J.',
    roles: 'owner',
  });
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(owner);

  const blocked = await request(app)
    .post('/api/v1/users/me/blocked-users/u-owner')
    .set(renter);
  assert.equal(blocked.status, 200);
  assert.deepEqual(blocked.body.data.blockedUserIds, ['u-owner']);

  const unblocked = await request(app)
    .delete('/api/v1/users/me/blocked-users/u-owner')
    .set(renter);
  assert.equal(unblocked.status, 200);
  assert.deepEqual(unblocked.body.data.blockedUserIds, []);
});

test('allows only an admin to list and restrict accounts with a reason', async () => {
  const renter = identity();
  const admin = identity({
    id: 'u-admin',
    email: 'admin@renthub.my',
    name: 'Admin Farah',
    roles: 'admin',
  });
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(admin);

  const forbidden = await request(app).get('/api/v1/users').set(renter);
  assert.equal(forbidden.status, 403);

  const directory = await request(app)
    .get('/api/v1/users?role=renter')
    .set(admin);
  assert.equal(directory.status, 200);
  assert.equal(directory.body.meta.total, 1);

  const target = await UserModel.findOne({ authId: 'u-renter' }).lean();
  const missingReason = await request(app)
    .patch(`/api/v1/users/${target._id}/status`)
    .set(admin)
    .send({ status: 'suspended' });
  assert.equal(missingReason.status, 400);
  assert.equal(missingReason.body.error.code, 'REASON_REQUIRED');

  const suspended = await request(app)
    .patch(`/api/v1/users/${target._id}/status`)
    .set(admin)
    .send({ status: 'suspended', reason: 'Repeated safety violations' });
  assert.equal(suspended.status, 200);
  assert.equal(suspended.body.data.accountStatus, 'suspended');
});

test('returns only safe fields from a public profile', async () => {
  const headers = identity({
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Sarah J.',
    roles: 'owner',
  });
  await request(app).post('/api/v1/users/session').set(headers);

  const response = await request(app).get('/api/v1/users/public/u-owner');
  assert.equal(response.status, 200);
  assert.equal(response.body.data.displayName, 'Sarah J.');
  assert.equal(response.body.data.email, undefined);
  assert.equal(response.body.data.accountStatusReason, undefined);
});
