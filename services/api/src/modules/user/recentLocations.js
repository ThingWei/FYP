import { createHash } from 'node:crypto';
import { validateLocation } from '../../core/location.js';
import { UserModel } from './user.model.js';

// Remember explicit selections only; never fetch GPS or copy a counterpart pin.
export async function rememberConfirmedLocation(userId, input, label) {
  if (!input) return;
  const location = input.toObject?.() ?? input;
  try { validateLocation(location); } catch { return; }
  const key = createHash('sha256').update(JSON.stringify([
    Number(location.coordinates.latitude.toFixed(4)), Number(location.coordinates.longitude.toFixed(4)),
    location.displayAddress.trim().toLocaleLowerCase('en-MY'),
  ])).digest('hex').slice(0, 24);
  await UserModel.updateOne({ authId: userId, 'recentLocations.publicId': { $ne: key } }, {
    $push: { recentLocations: { $each: [{ publicId: key, label, location }], $position: 0, $slice: 10 } },
  });
}

export async function rememberLocationAfterSave(userId, location, label) {
  try { await rememberConfirmedLocation(userId, location, label); }
  catch { /* Do not report a successful primary write as failed. */ }
}
