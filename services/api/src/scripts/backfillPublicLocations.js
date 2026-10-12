import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { ListingModel } from '../modules/listing/listing.model.js';
import { approximatePoint } from '../core/location.js';

// Dry-run by default. No external geocoding, no invented location, no private logs.
const apply = process.argv.includes('--apply');
const limitArg = process.argv.find((arg) => arg.startsWith('--limit='));
const limit = limitArg ? Number(limitArg.split('=')[1]) : 500;
if (!Number.isSafeInteger(limit) || limit < 1 || limit > 5000) throw new Error('Limit must be 1–5000');
await connectDatabase();
try {
  let inspected = 0, eligible = 0, updated = 0, invalid = 0;
  for await (const row of ListingModel.find({ coordinates: { $ne: null }, publicGeoPoint: null }).limit(limit).lean().cursor()) {
    inspected++;
    const point = approximatePoint(row.coordinates);
    if (!point) { invalid++; continue; }
    eligible++;
    if (apply) {
      const result = await ListingModel.updateOne({ _id: row._id, publicGeoPoint: null, 'coordinates.latitude': row.coordinates.latitude, 'coordinates.longitude': row.coordinates.longitude }, { $set: { publicGeoPoint: point } });
      updated += result.modifiedCount;
    }
  }
  console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry_run', limit, inspected, eligible, updated, invalid }));
} finally { await disconnectDatabase(); }
