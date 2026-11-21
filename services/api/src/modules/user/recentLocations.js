import { createHash } from 'node:crypto';
import { validateLocation } from '../../core/location.js';
import { UserModel } from './user.model.js';
import { sameSavedPlace, savedLocationKey } from './savedPlaceIdentity.js';

// Remember explicit selections only; never fetch GPS or copy a counterpart pin.
export async function rememberConfirmedLocation(userId, input, label) {
  if (!input) return;
  const location = input.toObject?.() ?? input;
  try { validateLocation(location); } catch { return; }
  const existing = await UserModel.findOne({ authId: userId }).select('addresses recentLocations').lean();
  if ([...(existing?.addresses ?? []), ...(existing?.recentLocations ?? [])].some(row => sameSavedPlace(row, location))) return;
  const key = createHash('sha256').update(savedLocationKey(location)).digest('hex').slice(0, 24);
  await UserModel.updateOne({ authId: userId, 'recentLocations.publicId': { $ne: key } }, {
    $push: { recentLocations: { $each: [{ publicId: key, label, location }], $position: 0, $slice: 10 } },
  });
}

export async function rememberLocationAfterSave(userId, location, label) {
  try { await rememberConfirmedLocation(userId, location, label); }
  catch { /* Do not report a successful primary write as failed. */ }
}
