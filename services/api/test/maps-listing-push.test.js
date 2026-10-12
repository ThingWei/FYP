import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { mapsAdapter } from '../src/integrations/mapsAdapter.js';
import { env } from '../src/config/env.js';

let mongo, originalSearch, originalResolve;
const owner = { 'x-user-id': 'map-owner', 'x-user-name': 'Map Owner', 'x-user-roles': 'owner' };
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); originalSearch = mapsAdapter.search; originalResolve = mapsAdapter.resolvePin;
  await request(app).post('/api/v1/users/session').set(owner).expect(201); });
after(async () => { mapsAdapter.search = originalSearch; mapsAdapter.resolvePin = originalResolve; await disconnectDatabase(); await mongo.stop(); });

test('map search requires authentication, validates queries and safely exposes only map configuration', async () => {
  let queries = [];
  mapsAdapter.search = async (q) => { queries.push(q); return { provider: 'openstreetmap', items: [] }; };
  const authMode = env.authMode; env.authMode = 'local';
  try { await request(app).get('/api/v1/maps/search?q=KL').expect(401); } finally { env.authMode = authMode; }
  for (const q of ['', 'a', 'x'.repeat(161)]) await request(app).get('/api/v1/maps/search').query({ q }).set(owner).expect(422);
  assert.equal(queries.length, 0);
  await request(app).get('/api/v1/maps/search').query({ q: 'Kuala Lumpur' }).set(owner).expect(200);
  assert.deepEqual(queries, ['Kuala Lumpur']);
  const config = await request(app).get('/api/v1/maps/config').set(owner).expect(200);
  assert.ok(config.body.data.tileUrl.startsWith('https://'));
  assert.equal(config.body.data.searchMode, 'explicit');
  assert.ok(!JSON.stringify(config.body).includes('private_key'));
});
test('listing pins persist and location changes require reconfirmed coordinates', async () => {
  const input = { title: 'Camera with pickup point', category: 'Devices', listingType: 'physical', condition: 'Good',
    fulfilmentMethods: ['pickup'], dailyPrice: 65, location: 'KLCC, Kuala Lumpur', coordinates: { latitude: 3.1579, longitude: 101.7116 } };
  const created = await request(app).post('/api/v1/listings').set(owner).send(input).expect(201);
  const id = created.body.data.publicId;
  assert.deepEqual(created.body.data.coordinates, input.coordinates);
  let response = await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ dailyPrice: 70 }).expect(200);
  assert.deepEqual(response.body.data.coordinates, input.coordinates);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ coordinates: null }).expect(422);
  await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ location: 'Shah Alam' }).expect(422);
  response = await request(app).patch(`/api/v1/listings/${id}`).set(owner).send({ location: 'Shah Alam', coordinates: input.coordinates }).expect(200);
  assert.deepEqual(response.body.data.coordinates, input.coordinates);
  const read = await request(app).get('/api/v1/listings/owner/mine').set(owner).expect(200);
  assert.deepEqual(read.body.data.find((row) => row.publicId === id).coordinates, input.coordinates);
});

test('pin lookup requires authentication, finite coordinates and explicit public-place confirmation', async () => {
  const points = [];
  mapsAdapter.resolvePin = async (point) => { points.push(point); return { provider: 'openstreetmap', item: null }; };
  const authMode = env.authMode; env.authMode = 'local';
  try { await request(app).post('/api/v1/maps/resolve-pin').send({}).expect(401); } finally { env.authMode = authMode; }
  for (const coordinates of [null, [], { latitude: '3', longitude: 101 }, { latitude: 3, longitude: 181 }, { latitude: 3 }, { latitude: 3, longitude: 101, extra: true }]) {
    await request(app).post('/api/v1/maps/resolve-pin').set(owner).send({ coordinates, publicPointConfirmed: true }).expect(422);
  }
  const coordinates = { latitude: 3.1579, longitude: 101.7116 };
  for (const publicPointConfirmed of [undefined, false, 'true']) {
    await request(app).post('/api/v1/maps/resolve-pin').set(owner).send({ coordinates, publicPointConfirmed }).expect(422);
  }
  assert.equal(points.length, 0);
  await request(app).post('/api/v1/maps/resolve-pin').set(owner).send({ coordinates, publicPointConfirmed: true }).expect(200);
  assert.deepEqual(points, [coordinates]);
});
test('API rejects malformed, incomplete and out-of-range coordinates', async () => {
  for (const coordinates of [{ latitude: '3', longitude: 101 }, { latitude: 91, longitude: 101 },
    { latitude: 3, longitude: 181 }, { latitude: 3 }, [], { latitude: 3, longitude: 101, extra: true }]) {
    await request(app).post('/api/v1/listings').set(owner).send({ title: 'Map test camera', category: 'Devices',
      dailyPrice: 10, condition: 'Good', fulfilmentMethods: ['pickup'], location: 'KL', coordinates }).expect(422);
  }
});
test('push status is authenticated and never claims delivery when FCM is disabled', async () => {
  const authMode = env.authMode; env.authMode = 'local';
  try { await request(app).get('/api/v1/messages/push/status').expect(401); } finally { env.authMode = authMode; }
  const previous = env.fcmMode; env.fcmMode = 'disabled';
  try { const response = await request(app).get('/api/v1/messages/push/status').set(owner).expect(200);
    assert.equal(response.body.data.enabled, false); assert.equal(response.body.data.status, 'disabled');
  } finally { env.fcmMode = previous; }
});
