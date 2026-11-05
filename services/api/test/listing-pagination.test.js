import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { listingRepository } from '../src/modules/listing/listing.repository.js';

let server;
before(async () => {
  server = await MongoMemoryServer.create();
  await connectDatabase(server.getUri());
  const timestamp = new Date('2026-11-05T08:00:00Z');
  await ListingModel.collection.insertMany(Array.from({ length: 67 }, (_, i) => ({
    _id: new mongoose.Types.ObjectId((i + 1).toString(16).padStart(24, '0')),
    publicId: `l-page-fixture-${i}`, ownerId: 'fixture-owner', ownerName: 'Demo Owner',
    title: 'Pagination fixture', category: i < 35 ? 'Devices' : 'Books',
    subcategory: i < 35 ? 'Computers' : 'Fiction',
    listingType: 'physical', status: 'active', sourceType: 'demo_seed',
    dailyPrice: 25, condition: 'Good', fulfilmentMethods: ['pickup'],
    rating: 0, promoted: false, createdAt: timestamp, updatedAt: timestamp,
  })));
});
after(async () => { await disconnectDatabase(); await server?.stop(); });

for (const [label, sort] of Object.entries({
  recommended: { promoted: -1, rating: -1, createdAt: -1 },
  newest: { createdAt: -1 },
  price_low: { dailyPrice: 1 },
  price_high: { dailyPrice: -1 },
  rating: { rating: -1, createdAt: -1 },
})) {
  test(`${label} pages retain every listing when all sort values tie`, async () => {
    const first = await listingRepository.listPublic({ page: 1, limit: 50, filter: {}, sort });
    const second = await listingRepository.listPublic({ page: 2, limit: 50, filter: {}, sort });
    assert.equal(first[1], 67);
    assert.equal(second[1], 67);
    assert.equal(first[0].length, 50);
    assert.equal(second[0].length, 17);
    assert.equal(new Set([...first[0], ...second[0]].map(row => row.publicId)).size, 67,
      'Equal prices/ratings/timestamps must never cause missing or repeated records');
    const repeated = await listingRepository.listPublic({ page: 2, limit: 50, filter: {}, sort });
    assert.deepEqual(repeated[0].map(row => row.publicId), second[0].map(row => row.publicId));
  });
}

test('stable pagination retains category filters and accurate counts', async () => {
  const all = [];
  for (let page = 1; page <= 4; page++) {
    const [items, total] = await listingRepository.listPublic({ page, limit: 10,
      filter: { category: 'Books', subcategory: 'Fiction' }, sort: { dailyPrice: 1 } });
    assert.equal(total, 32);
    assert.ok(items.every(item => item.category === 'Books' && item.subcategory === 'Fiction'));
    all.push(...items.map(item => item.publicId));
  }
  assert.equal(all.length, 32);
  assert.equal(new Set(all).size, 32);
});
