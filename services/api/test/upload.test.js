import test, { after, afterEach, before } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { storageAdapter } from '../src/integrations/storageAdapter.js';
import { UploadAssetModel } from '../src/modules/upload/upload.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { env } from '../src/config/env.js';

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
  const originalAuth = env.authMode;
  env.authMode = 'local';
  try {
    assert.equal((await request(app).get(`/api/v1/uploads/${id}/content`)).status, 401);
  } finally {
    env.authMode = originalAuth;
  }
  assert.equal((await request(app).get(`/api/v1/uploads/public/${id}/content`)).status, 404);
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

for (const purpose of ['vehicle_grant', 'verification_holder_photo']) {
  test(`${purpose} uses the private photo limit and rejects document/PDF uploads`, async () => {
    const previous = { ordinary: env.maxUploadBytes, privatePhoto: env.maxVerificationUploadBytes };
    env.maxUploadBytes = 100;
    env.maxVerificationUploadBytes = 500;
    try {
      const bytes = Buffer.alloc(300);
      png.copy(bytes);
      const upload = await request(app).post('/api/v1/uploads').set(identity())
        .field('purpose', purpose).attach('file', bytes, { filename: 'synthetic.png', contentType: 'image/png' }).expect(201);
      const asset = await UploadAssetModel.findOne({ publicId: upload.body.data.id });
      assert.equal(asset.visibility, 'private');
      assert.equal(asset.purpose, purpose);
      await request(app).get(`/api/v1/uploads/public/${asset.publicId}/content`).expect(404);
      await request(app).get(`/api/v1/uploads/${asset.publicId}/content`).set(identity('other')).expect(403);
      await request(app).post('/api/v1/uploads').set(identity()).field('purpose', purpose)
        .attach('file', Buffer.from('%PDF-1.4 synthetic'), { filename: 'document.pdf', contentType: 'application/pdf' }).expect(415);
      await request(app).post('/api/v1/uploads').set(identity()).field('purpose', purpose)
        .attach('file', Buffer.alloc(501), { filename: 'large.png', contentType: 'image/png' }).expect(413);
    } finally {
      env.maxUploadBytes = previous.ordinary;
      env.maxVerificationUploadBytes = previous.privatePhoto;
    }
  });
}

test('retains item photos referenced by previous moderation evidence', async () => {
  const uploaded = await request(app).post('/api/v1/uploads').set(identity())
    .field('purpose', 'listing_image')
    .attach('file', png, { filename: 'item.png', contentType: 'image/png' });
  assert.equal(uploaded.status, 201);
  const listing = await ListingModel.create({
    ownerId: 'u-owner', ownerName: 'Owner', title: 'Historical photo evidence',
    category: 'Devices', listingType: 'physical', dailyPrice: 50, location: 'Kuala Lumpur',
    condition: 'Good', fulfilmentMethods: ['pickup'],
    images: [], itemVerificationHistory: [{ images: [uploaded.body.data.contentUrl] }],
  });
  try {
    const removed = await request(app).delete(`/api/v1/uploads/${uploaded.body.data.id}`).set(identity());
    assert.equal(removed.status, 409);
    assert.equal(removed.body.error.code, 'UPLOAD_IN_USE');
    assert.equal((await request(app).get(uploaded.body.data.contentUrl)).status, 200);
  } finally {
    await listing.deleteOne();
  }
});

test('retains a public photo stored as an upload reference on a current listing', async () => {
  const uploaded = await request(app).post('/api/v1/uploads').set(identity())
    .field('purpose', 'listing_image')
    .attach('file', png, { filename: 'demo.png', contentType: 'image/png' });
  assert.equal(uploaded.status, 201);
  const listing = await ListingModel.create({
    ownerId: 'u-owner', ownerName: 'Owner', title: 'Demo public photo',
    category: 'Devices', listingType: 'physical', dailyPrice: 50, location: 'Kuala Lumpur',
    condition: 'Good', fulfilmentMethods: ['pickup'], images: [uploaded.body.data.reference],
  });
  try {
    const removed = await request(app).delete(`/api/v1/uploads/${uploaded.body.data.id}`).set(identity());
    assert.equal(removed.status, 409);
    assert.equal(removed.body.error.code, 'UPLOAD_IN_USE');
    const content = await request(app).get(uploaded.body.data.contentUrl);
    assert.equal(content.status, 200);
    assert.deepEqual(content.body, png);
  } finally {
    await listing.deleteOne();
  }
});


test('verification accepts a camera JPEG above ordinary limit, regardless of multipart field order', async () => {
  const photo = Buffer.alloc(env.maxUploadBytes + 1024, 0);
  photo.set([0xff, 0xd8, 0xff]);
  const result = await request(app).post('/api/v1/uploads').set(identity())
    .attach('file', photo, {filename:'camera.jpg',contentType:'image/jpeg'})
    .field('purpose','verification_document');
  assert.equal(result.status,201);
  assert.equal(result.body.data.visibility,'private');
  await request(app).get(`/api/v1/uploads/${result.body.data.id}/content`).set(identity('foreign')).expect(403);
  const ordinary = await request(app).post('/api/v1/uploads').set(identity())
    .field('purpose','listing_image').attach('file',photo,'item.jpg');
  assert.equal(ordinary.status,413);
  assert.equal(ordinary.body.error.details.maxBytes,env.maxUploadBytes);
});

test('oversized verification upload is rejected with the configured limit', async () => {
  const photo = Buffer.alloc(env.maxVerificationUploadBytes + 1,0);
  photo.set([0xff,0xd8,0xff]);
  const result = await request(app).post('/api/v1/uploads').set(identity())
    .field('purpose','verification_document').attach('file',photo,'camera.jpg');
  assert.equal(result.status,413);
  assert.equal(result.body.error.code,'FILE_TOO_LARGE');
  assert.equal(result.body.error.details.maxBytes,env.maxVerificationUploadBytes);
  assert.equal(await UploadAssetModel.countDocuments(),0);
});
