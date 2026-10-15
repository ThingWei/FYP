import { createHash, randomUUID } from 'node:crypto';
import { setTimeout } from 'node:timers/promises';
import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';

// A short creation mutex, NOT an availability reservation. Different renters
// never share a lock. The built-in unique _id works on standalone MongoDB too.
const schema = new mongoose.Schema({
  _id: String,
  token: { type: String, required: true },
  expiresAt: { type: Date, required: true },
}, { versionKey: false });
schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
export const BookingRequestLockModel = mongoose.models.BookingRequestLock ??
  mongoose.model('BookingRequestLock', schema);

function busy() {
  return new AppError('A booking request is still processing. Check your bookings before trying again.',
    409, 'BOOKING_REQUEST_IN_PROGRESS');
}

export async function withBookingRequestLock(renterId, listingId, operation) {
  const _id = createHash('sha256').update(JSON.stringify([renterId, listingId])).digest('hex');
  const token = randomUUID();
  let acquired = false;
  // Briefly wait for an ordinary concurrent double tap, then fail safely.
  for (let attempt = 0; attempt < 80; attempt++) {
    try {
      acquired = Boolean(await BookingRequestLockModel.findOneAndUpdate(
        { _id, expiresAt: { $lte: new Date() } },
        { $set: { token, expiresAt: new Date(Date.now() + 60_000) } },
        { upsert: true, new: true },
      ));
      break;
    } catch (error) {
      if (error?.code !== 11000) throw error;
      await setTimeout(25);
    }
  }
  if (!acquired) throw busy();
  const ensureOwned = async () => {
    // Renew immediately before persistence, not after an expired lease.
    if (!await BookingRequestLockModel.findOneAndUpdate(
      { _id, token, expiresAt: { $gt: new Date() } },
      { $set: { expiresAt: new Date(Date.now() + 60_000) } },
    )) {
      throw busy();
    }
  };
  try {
    return await operation(ensureOwned);
  } finally {
    // Never release a successor's lease. A failed cleanup expires safely.
    await BookingRequestLockModel.deleteOne({ _id, token }).catch(() => {});
  }
}
