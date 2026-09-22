import test, { after, afterEach, before } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';

let mongodb;
const identity = (id = 'u-owner') => ({
  'x-user-id': id,
  'x-user-email': `${id}@renthub.my`,
  'x-user-name': id,
  'x-user-roles': 'renter,owner',
});
const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await UploadAssetModel.init();
});

afterEach(async () => {
  const assets = await UploadAssetModel.find({}).select('storagePath').lean();
  await Promise.all(assets.map((asset) => storageAdapter.delete(asset.storagePath)));
  await UploadAssetModel.deleteMany({});
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('stores a public listing image and serves it without authentication', async () => {
  const uploaded = await request(app)
    .post('/api/v1/uploads')
    .set(identity())
    .field('purpose', 'listing_image')
    .attach('file', png, { filename: 'camera.png', contentType: 'image/png' });

  assert.equal(uploaded.status, 201);
  assert.match(uploaded.body.data.reference, /^upload:\/\/UPL-/);
  assert.match(uploaded.body.data.contentUrl, /^\/api\/v1\/uploads\/public\//);

  const content = await request(app).get(uploaded.body.data.contentUrl);
  assert.equal(content.status, 200);
  assert.equal(content.headers['content-type'], 'image/png');
  assert.deepEqual(content.body, png);

  const removed = await request(app)
    .delete(`/api/v1/uploads/${uploaded.body.data.id}`)
    .set(identity());
  assert.equal(removed.status, 200);
  assert.equal(
    (await request(app).get(uploaded.body.data.contentUrl)).status,
    404,
  );
});

test('keeps verification documents private to their uploader and administrators', async () => {
  const uploaded = await request(app)
    .post('/api/v1/uploads')
    .set(identity())
    .field('purpose', 'verification_document')
    .attach('file', png, { filename: 'mykad.png', contentType: 'image/png' });
  const id = uploaded.body.data.id;

  assert.equal(
    (await request(app).get(`/api/v1/uploads/${id}/content`).set(identity())).status,
    200,
  );
  assert.equal(
    (await request(app).get(`/api/v1/uploads/${id}/content`).set(identity('u-outsider'))).status,
    403,
  );
  assert.equal(
    (await request(app).get(`/api/v1/uploads/${id}/content`).set({
      ...identity('u-admin'),
      'x-user-roles': 'admin',
    })).status,
    200,
  );
});

test('rejects a file whose bytes do not match an allowed format', async () => {
  const response = await request(app)
    .post('/api/v1/uploads')
    .set(identity())
    .field('purpose', 'dispute_evidence')
    .attach('file', Buffer.from('not an image'), 'evidence.png');

  assert.equal(response.status, 415);
  assert.equal(response.body.error.code, 'UNSUPPORTED_FILE');
});
