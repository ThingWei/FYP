import mongoose from 'mongoose';
import { AppError } from './errors.js';

export const coordinatesSchema = new mongoose.Schema({
  latitude: { type: Number, required: true, min: -90, max: 90 },
  longitude: { type: Number, required: true, min: -180, max: 180 },
}, { _id: false });
export const locationSchema = new mongoose.Schema({
  coordinates: { type: coordinatesSchema, required: true },
  displayAddress: { type: String, required: true, trim: true, minlength: 2, maxlength: 240 },
  addressLine1: { type: String, trim: true, maxlength: 120 },
  addressLine2: { type: String, trim: true, maxlength: 120 },
  city: { type: String, trim: true, maxlength: 80, default: '' },
  state: { type: String, trim: true, maxlength: 80, default: '' },
  postcode: { type: String, match: /^(?:\d{5})?$/, default: '' },
  source: { type: String, enum: ['map', 'search', 'gps'], default: 'map' },
  accuracyMeters: { type: Number, min: 0, max: 100000 },
}, { _id: false });
export function validCoordinates(value) {
  return value && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).every((key) => ['latitude', 'longitude'].includes(key)) &&
    Number.isFinite(value.latitude) && Number.isFinite(value.longitude) &&
    Math.abs(value.latitude) <= 90 && Math.abs(value.longitude) <= 180;
}
export function validateLocation(value) {
  if (!value || !validCoordinates(value.coordinates) ||
    Object.keys(value).some((key) => !['coordinates', 'displayAddress', 'addressLine1', 'addressLine2', 'city', 'state', 'postcode', 'source', 'accuracyMeters'].includes(key)) ||
    typeof value.displayAddress !== 'string' || value.displayAddress.trim().length < 2 || value.displayAddress.length > 240 ||
    /[\x00-\x1f\x7f]/.test(value.displayAddress) ||
    ['city', 'state'].some((key) => value[key] !== undefined && (typeof value[key] !== 'string' || value[key].length > 80 || /[\x00-\x1f\x7f]/.test(value[key]))) ||
    ['addressLine1', 'addressLine2'].some((key) => value[key] !== undefined && (typeof value[key] !== 'string' || value[key].length > 120 || /[\x00-\x1f\x7f]/.test(value[key]))) ||
    value.postcode !== undefined && (typeof value.postcode !== 'string' || !/^(?:\d{5})?$/.test(value.postcode)) ||
    value.source !== undefined && !['map', 'search', 'gps'].includes(value.source) ||
    value.accuracyMeters !== undefined && (!Number.isFinite(value.accuracyMeters) || value.accuracyMeters < 0 || value.accuracyMeters > 100000)) {
    throw new Error('Confirm a valid map pin and address');
  }
  return true;
}
export function approximatePoint(coordinates) {
  if (!validCoordinates(coordinates)) return undefined;
  const snap = (number) => Number((Math.floor(number / .01) * .01 + .005).toFixed(3));
  return { type: 'Point', coordinates: [Math.min(179.995, snap(coordinates.longitude)), Math.min(89.995, snap(coordinates.latitude))] };
}
export function publicArea(value) {
  const details = value.locationDetails ?? value;
  return [details.city, details.state || value.state].filter(Boolean).join(', ') || 'Area available after confirmation';
}
export function publicListing(value) {
  value.location = publicArea(value);
  const point = value.publicGeoPoint ?? approximatePoint(value.coordinates);
  value.coordinates = point ? { latitude: point.coordinates[1], longitude: point.coordinates[0] } : null;
  value.locationPrecision = point ? 'approximate' : 'none';
  delete value.locationDetails;
  delete value.publicGeoPoint;
  return value;
}
export function ownedListing(document) {
  const value = document.toJSON(); // Public transform remains the safe default everywhere else.
  const raw = document.toObject();
  value.coordinates = raw.coordinates ?? null;
  value.locationDetails = raw.locationDetails;
  value.location = raw.location;
  value.locationPrecision = raw.coordinates ? 'exact' : 'none';
  return value;
}
export function requireListingPin(input, existing) {
  const online = (input.listingType ?? existing?.listingType) === 'service' && (input.serviceDetails ?? existing?.serviceDetails)?.venueMode === 'online';
  const modeChanged = existing && (input.serviceDetails?.venueMode !== undefined && input.serviceDetails.venueMode !== existing.serviceDetails?.venueMode || input.listingType !== undefined && input.listingType !== existing.listingType);
  const changed = !existing || input.location !== undefined && input.location !== existing.location ||
    input.locationDetails !== undefined && JSON.stringify(input.locationDetails) !== JSON.stringify(existing.locationDetails?.toObject?.() ?? existing.locationDetails) ||
    input.coordinates !== undefined && JSON.stringify(input.coordinates) !== JSON.stringify(existing.coordinates?.toObject?.() ?? existing.coordinates);
  const coordinates = input.coordinates !== undefined ? input.coordinates : existing?.coordinates?.toObject?.() ?? existing?.coordinates;
  if (!online && (changed || modeChanged) && (!validCoordinates(coordinates) || input.location !== undefined && input.location !== existing?.location && !validCoordinates(input.coordinates))) throw new AppError('Confirm a map pin for this location', 422, 'LOCATION_PIN_REQUIRED');
  if (input.locationDetails && (!coordinates || input.locationDetails.coordinates.latitude !== coordinates.latitude || input.locationDetails.coordinates.longitude !== coordinates.longitude)) {
    throw new AppError('Location details and pin must agree', 422, 'LOCATION_PIN_REQUIRED');
  }
}
export function nearbyFilter(query) {
  if (query.latitude === undefined) return {};
  return { publicGeoPoint: { $geoWithin: { $centerSphere: [[Number(query.longitude), Number(query.latitude)], Number(query.radiusKm) / 6371.0088] } } };
}
export function validateNearby(value) {
  const keys = ['latitude', 'longitude', 'radiusKm'];
  if (!keys.some((key) => value[key] !== undefined)) return true;
  const decimal = /^-?\d+(?:\.\d+)?$/;
  if (!keys.every((key) => typeof value[key] === 'string' && decimal.test(value[key])) ||
    Math.abs(Number(value.latitude)) > 90 || Math.abs(Number(value.longitude)) > 180 ||
    ![5, 10, 25, 50].includes(Number(value.radiusKm))) throw new Error('Choose a valid map centre and radius');
  return true;
}
const unlocked = new Set(['approved', 'active', 'completed', 'disputed']);
export function bookingLocations(document, identity) {
  const raw = document.toObject?.() ?? document;
  const admin = identity.roles?.includes('admin'), owner = identity.authId === raw.ownerId, renter = identity.authId === raw.renterId;
  if (!admin && !owner && !renter) throw new AppError('Booking not found', 404, 'NOT_FOUND');
  const shared = unlocked.has(raw.status);
  return { shared, pickupLocation: admin || owner || shared ? raw.pickupLocationSnapshot ?? null : null,
    serviceLocation: admin || renter || shared ? raw.serviceLocation ?? null : null,
    deliveryLocation: admin || renter || shared ? raw.deliveryLocation ?? null : null };
}
export function presentBooking(document, identity) {
  const value = document.toJSON(), raw = document.toObject();
  const locations = bookingLocations(document, identity);
  value.pickupLocationSnapshot = locations.pickupLocation;
  value.serviceLocation = locations.serviceLocation;
  value.deliveryLocation = locations.deliveryLocation;
  const ownerVenue = raw.serviceVenueMode === 'owner_location' || !raw.serviceVenueMode && !raw.serviceLocation && !!raw.serviceVenue && raw.serviceVenue !== 'Online';
  if (identity.roles?.includes('admin') || unlocked.has(raw.status) || identity.authId === raw.renterId && !ownerVenue || identity.authId === raw.ownerId && ownerVenue) value.serviceVenue = raw.serviceVenue;
  else if (ownerVenue) value.serviceVenue = 'Venue shared after approval';
  if (raw.serviceLocation && !locations.serviceLocation) value.serviceVenue = publicArea(raw.serviceLocation);
  else if (!unlocked.has(raw.status) && identity.authId !== raw.renterId && !identity.roles?.includes('admin')) value.serviceVenue = raw.serviceVenue ? 'Venue shared after approval' : undefined;
  return value;
}
