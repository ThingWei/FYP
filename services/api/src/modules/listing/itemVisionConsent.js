import { createHash } from 'node:crypto';

export const PHOTO_CONSENT_VERSION = 'google-item-photos-v1';
export const photoSetKey = images => createHash('sha256').update(JSON.stringify(images ?? [])).digest('hex');
export function hasPhotoConsent(listing) {
  return listing.listingType === 'physical' && listing.images?.length >= 3 &&
    listing.itemVisionConsent?.version === PHOTO_CONSENT_VERSION &&
    listing.itemVisionConsent?.ownerId === listing.ownerId &&
    listing.itemVisionConsent?.photos === photoSetKey(listing.images);
}
export function setPhotoConsent(listing, declaration, identity) {
  if (declaration === true && listing.listingType === 'physical' && listing.images?.length >= 3) {
    listing.itemVisionConsent = { version: PHOTO_CONSENT_VERSION, ownerId: identity.authId,
      photos: photoSetKey(listing.images), grantedAt: new Date() };
  } else if (declaration === false || !hasPhotoConsent(listing)) listing.itemVisionConsent = undefined;
}
