import mongoose from 'mongoose';

const schema = new mongoose.Schema({
  userId: { type: String, required: true },
  listingId: { type: String, required: true },
  day: { type: String, required: true },
  lastViewedAt: { type: Date, required: true },
  expiresAt: { type: Date, required: true },
});
schema.index({ userId: 1, listingId: 1, day: 1 }, { unique: true });
schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
schema.index({ userId: 1, lastViewedAt: -1 });
schema.index({ lastViewedAt: -1 });
export const ListingViewModel = mongoose.model('ListingView', schema);
