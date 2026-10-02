import test, { after, afterEach, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { MessageModel } from '../src/modules/communication/message.model.js';
import { MessageReportModel } from '../src/modules/communication/messageReport.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { DeviceRegistrationModel } from '../src/modules/communication/deviceRegistration.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';

let mongodb;
const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);

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

async function setupConversation() {
  for (const headers of [renter, owner, outsider, admin]) {
    await request(app).post('/api/v1/users/session').set(headers);
  }
  await ListingModel.create({
    publicId: 'l-camera',
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    title: 'Sony Alpha a7S III Mirrorless Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 85,
    condition: 'Excellent',
    securityDeposit: 300,
    fulfilmentMethods: ['pickup'],
    location: 'Bukit Bintang, Kuala Lumpur',
    status: 'active',
  });
  const booking = await request(app)
    .post('/api/v1/bookings')
    .set(renter)
    .send({
      listingId: 'l-camera',
      idempotencyKey: 'communication-booking-test',
      startDate: '2026-11-20',
      endDate: '2026-11-22',
      fulfilmentMethod: 'pickup',
      agreementAccepted: true,
      agreementVersion: 'renthub-booking-v1',
    });
  assert.equal(booking.status, 201, JSON.stringify(booking.body));
  const thread = await ThreadModel.findOne({
    bookingId: booking.body.data.id,
  }).lean();
  return { bookingId: booking.body.data.id, threadId: thread.publicId };
}

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    ListingModel.init(),
    BookingModel.init(),
    ThreadModel.init(),
    MessageModel.init(),
    MessageReportModel.init(),
    NotificationModel.init(),
    DeviceRegistrationModel.init(),
    UploadAssetModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    ListingModel.deleteMany({}),
    BookingModel.deleteMany({}),
    ThreadModel.deleteMany({}),
    MessageModel.deleteMany({}),
    MessageReportModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    DeviceRegistrationModel.deleteMany({}),
    UploadAssetModel.deleteMany({}),
  ]);
});

afterEach(async () => {
  const assets = await UploadAssetModel.find({}).select('storagePath').lean();
  await Promise.all(
    assets.map((asset) => storageAdapter.delete(asset.storagePath)),
  );
  await UploadAssetModel.deleteMany({});
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('registers, rotates, lists, and removes an isolated push device', async () => {
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(outsider);
  const firstToken = `fcm-${'a'.repeat(80)}`;
  const secondToken = `fcm-${'b'.repeat(80)}`;

  const registered = await request(app)
    .post('/api/v1/messages/push/devices')
    .set(renter)
    .send({
      deviceId: 'device-renter-phone',
      deviceName: 'Alex Android',
      platform: 'android',
      token: firstToken,
    });
  assert.equal(registered.status, 200);
  assert.equal(registered.body.data.deviceId, 'device-renter-phone');
  assert.equal(registered.body.data.token, undefined);

  const rotated = await request(app)
    .post('/api/v1/messages/push/devices')
    .set(renter)
    .send({
      deviceId: 'device-renter-phone',
      deviceName: 'Alex Android',
      platform: 'android',
      token: secondToken,
    });
  assert.equal(rotated.status, 200);
  assert.equal(
    await DeviceRegistrationModel.countDocuments({ userId: 'u-renter' }),
    1,
  );
  const stored = await DeviceRegistrationModel.findOne({
    userId: 'u-renter',
  }).select('+token');
  assert.equal(stored.token, secondToken);

  const ownerDevices = await request(app)
    .get('/api/v1/messages/push/devices')
    .set(renter);
  assert.equal(ownerDevices.status, 200);
  assert.equal(ownerDevices.body.data.length, 1);
  assert.equal(ownerDevices.body.data[0].token, undefined);
  const otherDevices = await request(app)
    .get('/api/v1/messages/push/devices')
    .set(outsider);
  assert.deepEqual(otherDevices.body.data, []);

  const removed = await request(app)
    .delete('/api/v1/messages/push/devices/device-renter-phone')
    .set(renter);
  assert.equal(removed.status, 200);
  assert.equal(removed.body.data.removed, true);
  assert.equal(await DeviceRegistrationModel.countDocuments(), 0);
});

test('creates a booking-linked participant conversation and notification', async () => {
  const { bookingId, threadId } = await setupConversation();

  assert.equal(await ThreadModel.countDocuments({ bookingId }), 1);
  const notification = await NotificationModel.findOne({
    userId: 'u-owner',
    type: 'booking_created',
  }).lean();
  assert.equal(notification.entityId, bookingId);

  const threads = await request(app).get('/api/v1/messages/threads').set(renter);
  assert.equal(threads.status, 200);
  assert.equal(threads.body.meta.total, 1);
  assert.equal(threads.body.data[0].id, threadId);
  assert.equal(threads.body.data[0].otherParticipant.displayName, 'Sarah J.');

  const hidden = await request(app)
    .get(`/api/v1/messages/threads/${threadId}/messages`)
    .set(outsider);
  assert.equal(hidden.status, 404);
});

test('sends, reads, reports and blocks messages with participant safeguards', async () => {
  const { threadId } = await setupConversation();
  const sent = await request(app)
    .post(`/api/v1/messages/threads/${threadId}/messages`)
    .set(owner)
    .send({ text: 'The camera and lens are ready for collection.' });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.data.recipientId, 'u-renter');

  let renterThreads = await request(app)
    .get('/api/v1/messages/threads')
    .set(renter);
  assert.equal(renterThreads.body.data[0].unreadCount, 1);

  const read = await request(app)
    .post(`/api/v1/messages/threads/${threadId}/read`)
    .set(renter);
  assert.equal(read.status, 200);
  assert.equal(read.body.data.updatedCount, 1);
  renterThreads = await request(app)
    .get('/api/v1/messages/threads')
    .set(renter);
  assert.equal(renterThreads.body.data[0].unreadCount, 0);

  const report = await request(app)
    .post(`/api/v1/messages/${sent.body.data.id}/report`)
    .set(renter)
    .send({ reason: 'inappropriate', details: 'Unsafe collection language' });
  assert.equal(report.status, 201);
  const retry = await request(app)
    .post(`/api/v1/messages/${sent.body.data.id}/report`)
    .set(renter)
    .send({ reason: 'inappropriate', details: 'Unsafe collection language' });
  assert.equal(retry.body.data.id, report.body.data.id);

  const queue = await request(app)
    .get('/api/v1/messages/reports?status=open')
    .set(admin);
  assert.equal(queue.status, 200);
  assert.equal(queue.body.meta.total, 1);
  assert.equal(
    queue.body.data[0].messageText,
    'The camera and lens are ready for collection.',
  );
  const resolved = await request(app)
    .patch(`/api/v1/messages/reports/${report.body.data.id}`)
    .set(admin)
    .send({ status: 'resolved', resolution: 'Warning issued to the Owner' });
  assert.equal(resolved.status, 200);
  assert.equal(resolved.body.data.reviewedBy, 'u-admin');

  await request(app)
    .post('/api/v1/users/me/blocked-users/u-owner')
    .set(renter);
  const blocked = await request(app)
    .post(`/api/v1/messages/threads/${threadId}/messages`)
    .set(owner)
    .send({ text: 'This message must not be stored.' });
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.error.code, 'COMMUNICATION_BLOCKED');
  assert.equal(await MessageModel.countDocuments({ threadId }), 1);
});

test('sends a protected image that only conversation participants can read', async () => {
  const { threadId } = await setupConversation();
  const uploaded = await request(app)
    .post('/api/v1/uploads')
    .set(owner)
    .field('purpose', 'message_image')
    .attach('file', png, { filename: 'camera-condition.png', contentType: 'image/png' });
  assert.equal(uploaded.status, 201);

  const sent = await request(app)
    .post(`/api/v1/messages/threads/${threadId}/messages`)
    .set(owner)
    .send({ attachmentRef: uploaded.body.data.reference });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.data.text, '');
  assert.equal(sent.body.data.attachment.kind, 'image');
  assert.equal(sent.body.data.attachment.contentType, 'image/png');

  const contentUrl = sent.body.data.attachment.contentUrl;
  const participantRead = await request(app).get(contentUrl).set(renter);
  const outsiderRead = await request(app).get(contentUrl).set(outsider);
  assert.equal(participantRead.status, 200);
  assert.deepEqual(participantRead.body, png);
  assert.equal(outsiderRead.status, 403);

  const conversation = await request(app).get('/api/v1/messages/threads').set(renter);
  assert.equal(conversation.body.data[0].lastMessageText, '[Image]');

  const deleteAttached = await request(app)
    .delete(`/api/v1/uploads/${uploaded.body.data.id}`)
    .set(owner);
  assert.equal(deleteAttached.status, 409);
  assert.equal(deleteAttached.body.error.code, 'UPLOAD_IN_USE');
});

test('supports notification filters, read state, individual removal and clear all', async () => {
  const { threadId } = await setupConversation();
  await request(app)
    .post(`/api/v1/messages/threads/${threadId}/messages`)
    .set(owner)
    .send({ text: 'Your collection time is confirmed.' });

  let notifications = await request(app)
    .get('/api/v1/messages/notifications?read=false')
    .set(renter);
  assert.equal(notifications.status, 200);
  assert.equal(notifications.body.meta.unread, 1);
  const notificationId = notifications.body.data[0].id;

  const marked = await request(app)
    .post(`/api/v1/messages/notifications/${notificationId}/read`)
    .set(renter);
  assert.equal(marked.status, 200);
  assert.equal(marked.body.data.read, true);

  const removed = await request(app)
    .delete(`/api/v1/messages/notifications/${notificationId}`)
    .set(renter);
  assert.equal(removed.status, 200);
  assert.equal(removed.body.data.removed, true);

  await request(app)
    .post(`/api/v1/messages/threads/${threadId}/messages`)
    .set(renter)
    .send({ text: 'Thank you, see you then.' });
  const readAll = await request(app)
    .post('/api/v1/messages/notifications/read-all')
    .set(owner);
  assert.equal(readAll.status, 200);
  assert.ok(readAll.body.data.updatedCount >= 1);

  const cleared = await request(app)
    .delete('/api/v1/messages/notifications')
    .set(owner);
  assert.equal(cleared.status, 200);
  assert.ok(cleared.body.data.removedCount >= 1);
});
