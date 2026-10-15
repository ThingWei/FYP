import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { env } from '../src/config/env.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { recordPhysicalSettlement, captureBookingPayment } from '../src/modules/payment/payment.service.js';
import { approximatePoint, bookingLocations, validateLocation, validateNearby } from '../src/core/location.js';

const headers = (id, role = 'renter') => ({ 'x-user-id': id, 'x-user-name': id, 'x-user-email': `${id}@example.test`, 'x-user-roles': role });
const owner = headers('u-map-owner', 'owner'), renter = headers('u-map-renter'), admin = headers('u-map-admin', 'admin');
const point = { latitude: 3.14234, longitude: 101.68678 };
const place = (displayAddress = 'Private entrance 12', coordinates = point) => ({ displayAddress, coordinates, city: 'Kuala Lumpur', state: 'Kuala Lumpur', postcode: '05000', source: 'map' });
const listingInput = { title: 'Camera location test', category: 'Devices', subcategory: 'Cameras', listingType: 'physical', dailyPrice: 60, condition: 'Good', fulfilmentMethods: ['pickup', 'owner_delivery'], location: 'Kuala Lumpur', state: 'Kuala Lumpur', coordinates: point, locationDetails: place() };
let mongo, sequence = 0;
before(async () => { mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); await ListingModel.init(); });
beforeEach(async () => {
  await Promise.all([ListingModel.deleteMany({}), BookingModel.deleteMany({}), UserModel.deleteMany({})]);
  for (const identity of [owner, renter, admin, headers('u-map-stranger')]) {
    await request(app).post('/api/v1/users/session').set(identity);
  }
  await UserModel.updateOne({ authId: 'u-map-renter' }, { $set: { 'verification.status': 'approved', 'verification.documents': [{ documentType: 'mykad', status: 'approved' }] } });
});
after(async () => { await disconnectDatabase(); await mongo.stop(); });
async function seedListing(overrides = {}) {
  return ListingModel.create({ ...listingInput, publicId: `l-map-${++sequence}`, ownerId: 'u-map-owner', ownerName: 'Map Owner', status: 'active', publicGeoPoint: approximatePoint(point), ...overrides });
}
const bookingInput = (listing, overrides = {}) => ({ listingId: listing.publicId, idempotencyKey: `location-test:${++sequence}`, startDate: '2026-11-10', endDate: '2026-11-11', fulfilmentMethod: 'pickup', agreementAccepted: true, agreementVersion: 'renthub-booking-v1', ...overrides });

test('Owner-set delivery fee is snapshotted, server-controlled, charged once and included in settlement', async () => {
  const listing = await seedListing({ deliveryFee: 23.45 });
  const pickup = await request(app).post('/api/v1/bookings').set(renter).send(bookingInput(listing)).expect(201);
  assert.equal(pickup.body.data.pricing.deliveryFee, 0);
  assert.equal(pickup.body.data.pricing.total, 120);
  const input = bookingInput(listing, { fulfilmentMethod: 'owner_delivery', deliveryLocation: place('Delivery entrance') });
  const delivered = await request(app).post('/api/v1/bookings').set(renter).send(input).expect(201);
  const id = delivered.body.data.publicId;
  assert.equal(delivered.body.data.pricing.deliveryFee, 23.45);
  assert.equal(delivered.body.data.pricing.total, 143.45);
  await ListingModel.updateOne({ _id: listing._id }, { $set: { deliveryFee: 90 } });
  const replay = await request(app).post('/api/v1/bookings').set(renter).send(input).expect(201);
  assert.equal(replay.body.data.pricing.total, 143.45);
  await request(app).post('/api/v1/payments/authorizations').set(renter)
    .send({ bookingId: id, method: 'card', amount: 1, idempotencyKey: `delivery-payment:${sequence}` }).expect(201);
  await request(app).patch(`/api/v1/bookings/${id}/decision`).set(owner).send({ status: 'approved' }).expect(200);
  const agreement = await request(app).get(`/api/v1/bookings/${id}/agreement`).set(renter).expect(200);
  assert.equal(agreement.body.data.booking.pricing.deliveryFee, 23.45);
  const saved = await BookingModel.findOne({ publicId: id });
  await captureBookingPayment(saved);
  await recordPhysicalSettlement(saved, 0);
  const settlement = await PaymentModel.findOne({ bookingId: id, type: 'owner_settlement' });
  assert.equal(settlement.amount, 143.45);
});

test('strict location and nearby validation rejects malformed inputs and retains leading-zero postcodes', () => {
  assert.equal(validateLocation(place()), true);
  for (const bad of [{ ...place(), coordinates: { latitude: '3', longitude: 100 } }, { ...place(), coordinates: { latitude: Infinity, longitude: 100 } }, { ...place(), postcode: 5000 }, { ...place(), coordinates: { latitude: 91, longitude: 100 } }]) assert.throws(() => validateLocation(bad));
  for (const bad of [{ latitude: '3' }, { latitude: '3', longitude: '100', radiusKm: '7' }, { latitude: '3e0', longitude: '100', radiusKm: '10' }]) assert.throws(() => validateNearby(bad));
  assert.equal(validateNearby({ latitude: '3', longitude: '100', radiusKm: '10' }), true);
  assert.deepEqual(approximatePoint(point), { type: 'Point', coordinates: [101.685, 3.145] });
  assert.equal(approximatePoint({ latitude: NaN, longitude: 100 }), undefined);
});

test('new physical locations require pins; legacy unrelated edits remain allowed; online mode is conditional', async () => {
  const { coordinates, locationDetails, ...unpinned } = listingInput;
  await request(app).post('/api/v1/listings').set(owner).send(unpinned).expect(422);
  const legacy = await seedListing({ coordinates: undefined, locationDetails: undefined, publicGeoPoint: undefined });
  await request(app).patch(`/api/v1/listings/${legacy.publicId}`).set(owner).send({ dailyPrice: 65 }).expect(200);
  await request(app).patch(`/api/v1/listings/${legacy.publicId}`).set(owner).send({ location: 'New town' }).expect(422);
  const online = await request(app).post('/api/v1/listings').set(owner).send({ title: 'Online tutoring', category: 'Services', listingType: 'service', dailyPrice: 50, location: 'Online', serviceDetails: { packageName: 'Lesson', durationMinutes: 60, venueMode: 'online' } }).expect(201);
  await request(app).patch(`/api/v1/listings/${online.body.data.publicId}`).set(owner).send({ serviceDetails: { packageName: 'Lesson', durationMinutes: 60, venueMode: 'owner_location' } }).expect(422);
});

test('public feeds, recommendations, wishlist, comparison and profiles never return private location details', async () => {
  const listing = await seedListing();
  for (const path of [`/api/v1/listings/${listing.publicId}`, '/api/v1/listings', '/api/v1/listings/recommended']) {
    const response = await request(app).get(path).set(renter).expect(200);
    const serialized = JSON.stringify(response.body);
    assert.ok(!serialized.includes('Private entrance')); assert.ok(!serialized.includes('101.68678'));
    assert.ok(serialized.includes('approximate'));
  }
  await request(app).put(`/api/v1/users/me/saved-listings/${listing.publicId}`).set(renter).expect(200);
  await request(app).put('/api/v1/users/me/comparison').set(renter).send({ listingIds: [listing.publicId] }).expect(200);
  for (const path of ['/api/v1/users/me/saved-listings', '/api/v1/users/me/comparison', '/api/v1/users/public/u-map-owner']) {
    const response = await request(app).get(path).set(renter).expect(200);
    assert.ok(!JSON.stringify(response.body).includes('Private entrance'));
  }
  const own = await request(app).get('/api/v1/listings/owner/mine').set(owner).expect(200);
  assert.equal(own.body.data[0].locationDetails.displayAddress, 'Private entrance 12');
  const moderation = await request(app).get('/api/v1/listings/admin').set(admin);
  // Admin route is independently covered below through booking locations.
  assert.equal(moderation.status, 200); assert.equal(moderation.body.data[0].locationDetails.displayAddress, 'Private entrance 12');
});

test('pin-only updates cannot retain mismatched private details or GPS accuracy', async () => {
  const listing = await seedListing({ locationDetails: { ...place(), source: 'gps', accuracyMeters: 12 } });
  const coordinates = { latitude: 3.19, longitude: 101.73 };
  const updated = await request(app).patch(`/api/v1/listings/${listing.publicId}`).set(owner).send({ coordinates }).expect(200);
  assert.deepEqual(updated.body.data.locationDetails.coordinates, coordinates);
  assert.equal(updated.body.data.locationDetails.accuracyMeters, undefined);
  await request(app).patch(`/api/v1/listings/${listing.publicId}`).set(owner).send({ coordinates, locationDetails: place() }).expect(422);
  await request(app).post('/api/v1/listings').set(owner).send({ ...listingInput, publicGeoPoint: { type: 'Point', coordinates: [100, 3] } }).expect(422);
});

test('saved addresses require owned stable identifiers and new/changed pins', async () => {
  const address = { label: 'Home', line1: 'Private entrance 12', city: 'KL', state: 'Kuala Lumpur', postcode: '05000', isDefault: true };
  await request(app).patch('/api/v1/users/me').set(renter).send({ addresses: [address] }).expect(422);
  let response = await request(app).patch('/api/v1/users/me').set(renter).send({ addresses: [{ ...address, coordinates: point }] }).expect(200);
  const saved = response.body.data.addresses[0]; assert.equal(saved.postcode, '05000');
  response = await request(app).patch('/api/v1/users/me').set(renter).send({ addresses: [{ ...saved, label: 'Office' }] }).expect(200);
  assert.equal(response.body.data.addresses[0]._id, saved._id);
  await request(app).patch('/api/v1/users/me').set(owner).send({ addresses: [saved] }).expect(422);
  const { coordinates, ...withoutPoint } = saved;
  await request(app).patch('/api/v1/users/me').set(renter).send({ addresses: [{ ...withoutPoint, line1: 'Different entrance' }] }).expect(422);
});

test('booking snapshots remain immutable; pending counterpart locations are withheld; idempotency includes destinations', async () => {
  const listing = await seedListing();
  await request(app).post('/api/v1/bookings').set(renter).send(bookingInput(listing, { fulfilmentMethod: 'owner_delivery' })).expect(422);
  const input = bookingInput(listing, { fulfilmentMethod: 'owner_delivery', deliveryLocation: place('Renter private home', { latitude: 3.15, longitude: 101.70 }) });
  const created = await request(app).post('/api/v1/bookings').set(renter).send(input).expect(201);
  const id = created.body.data.publicId;
  assert.equal(created.body.data.pickupLocationSnapshot, null);
  let response = await request(app).get(`/api/v1/bookings/${id}/locations`).set(owner).expect(200);
  assert.equal(response.body.data.deliveryLocation, null); assert.equal(response.body.data.pickupLocation.displayAddress, 'Private entrance 12');
  const ownerBooking = await request(app).get(`/api/v1/bookings/${id}`).set(owner).expect(200);
  assert.ok(!JSON.stringify(ownerBooking.body).includes('Renter private home'));
  await request(app).get(`/api/v1/bookings/${id}/locations`).set(headers('u-map-stranger')).expect(404);
  const auth = env.authMode; env.authMode = 'local'; try { await request(app).get(`/api/v1/bookings/${id}/locations`).expect(401); } finally { env.authMode = auth; }
  const reordered = { ...input, deliveryLocation: { source: 'map', postcode: '05000', state: 'Kuala Lumpur', city: 'Kuala Lumpur', coordinates: { longitude: 101.70, latitude: 3.15 }, displayAddress: 'Renter private home' } };
  await request(app).post('/api/v1/bookings').set(renter).send(reordered).expect(201);
  await request(app).post('/api/v1/bookings').set(renter).send({ ...input, deliveryLocation: place('Different home') }).expect(409);
  await ListingModel.updateOne({ _id: listing._id }, { $set: { locationDetails: place('Changed owner entrance') } });
  await BookingModel.updateOne({ publicId: id }, { $set: { status: 'approved' } });
  response = await request(app).get(`/api/v1/bookings/${id}/locations`).set(renter).expect(200);
  assert.equal(response.body.data.pickupLocation.displayAddress, 'Private entrance 12');
  const record = await BookingModel.findOne({ publicId: id }); record.pickupLocationSnapshot = place('Illegal change'); await assert.rejects(record.save(), /immutable/);
  assert.equal((await BookingModel.findOne({ publicId: id })).pickupLocationSnapshot.displayAddress, 'Private entrance 12');
  for (const status of ['pending', 'rejected', 'expired', 'cancelled', 'approved', 'active', 'completed', 'disputed']) {
    const raw = { ownerId: 'u-map-owner', renterId: 'u-map-renter', status, pickupLocationSnapshot: place(), deliveryLocation: place('Renter private home') };
    const shared = ['approved', 'active', 'completed', 'disputed'].includes(status);
    assert.equal(!!bookingLocations(raw, { authId: 'u-map-renter', roles: ['renter'] }).pickupLocation, shared);
    assert.equal(!!bookingLocations(raw, { authId: 'u-map-owner', roles: ['owner'] }).deliveryLocation, shared);
    assert.ok(bookingLocations(raw, { authId: 'u-map-admin', roles: ['admin'] }).pickupLocation);
  }
});

test('service venue modes validate pinned destinations and keep owner venues private before approval', async () => {
  for (const mode of ['owner_location', 'renter_location', 'flexible', 'online']) {
    const listing = await seedListing({ category: 'Services', listingType: 'service', condition: undefined, serviceDetails: { packageName: 'Lesson', durationMinutes: 60, venueMode: mode } });
    const input = bookingInput(listing); delete input.fulfilmentMethod;
    if (['flexible', 'renter_location'].includes(mode)) {
      await request(app).post('/api/v1/bookings').set(renter).send(input).expect(422);
      input.serviceLocation = place('Renter service venue');
    }
    const result = await request(app).post('/api/v1/bookings').set(renter).send(input).expect(201);
    const id = result.body.data.publicId;
    if (mode === 'owner_location') assert.ok(!JSON.stringify(result.body).includes('Private entrance'));
    const ownerView = await request(app).get(`/api/v1/bookings/${id}`).set(owner).expect(200);
    if (['flexible', 'renter_location'].includes(mode)) assert.ok(!JSON.stringify(ownerView.body).includes('Renter service venue'));
    if (mode === 'online') {
      assert.equal(result.body.data.serviceVenue, 'Online');
      const locations = await request(app).get(`/api/v1/bookings/${id}/locations`).set(renter).expect(200); assert.equal(locations.body.data.pickupLocation, null);
    }
  }
});

test('nearby filtering uses spherical public points before combined filters, counts and pagination', async () => {
  for (const [latitude, category] of [[3.145, 'Devices'], [3.185, 'Devices'], [3.215, 'Devices'], [3.145, 'Equipment']]) await seedListing({ category, publicGeoPoint: { type: 'Point', coordinates: [101.685, latitude] } });
  await seedListing({ publicGeoPoint: undefined, coordinates: undefined, locationDetails: undefined });
  const query = { latitude: '3.145', longitude: '101.685', radiusKm: '5', category: 'Devices', minPrice: '50', maxPrice: '70', limit: '1' };
  const response = await request(app).get('/api/v1/listings').query(query).expect(200);
  assert.equal(response.body.meta.total, 2); assert.equal(response.body.data.length, 1);
  const page2 = await request(app).get('/api/v1/listings').query({ ...query, page: '2' }).expect(200);
  assert.notEqual(response.body.data[0].publicId, page2.body.data[0].publicId);
  const recommended = await request(app).get('/api/v1/listings/recommended').set(renter).query({ latitude: '3.145', longitude: '101.685', radiusKm: '5' }).expect(200);
  assert.ok(!JSON.stringify(recommended.body).includes('3.215'));
  for (const radiusKm of ['5', '10', '25', '50']) await request(app).get('/api/v1/listings').query({ latitude: '3.145', longitude: '101.685', radiusKm }).expect(200);
  await request(app).get('/api/v1/listings').query({ latitude: '3.145' }).expect(422);
});

test('backfill is bounded, dry-run by default and idempotent against a temporary database', async () => {
  const listing = await seedListing({ publicGeoPoint: undefined });
  const run = promisify(execFile), args = ['src/scripts/backfillPublicLocations.js', '--limit=1'];
  const options = { env: { ...process.env, MONGODB_URI: mongo.getUri() }, cwd: process.cwd() };
  await run(process.execPath, args, options); assert.equal((await ListingModel.findById(listing._id)).publicGeoPoint, undefined);
  await run(process.execPath, [...args, '--apply'], options);
  assert.deepEqual((await ListingModel.findById(listing._id)).publicGeoPoint.coordinates.toObject(), [101.685, 3.145]);
  const result = await run(process.execPath, [...args, '--apply'], options); assert.ok(result.stdout.includes('"updated":0'));
});
