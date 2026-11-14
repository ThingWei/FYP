import { AppError } from '../../core/errors.js';

const vehicleType = listing => typeof listing.subcategory === 'string' ? listing.subcategory.normalize('NFKC').trim().toLowerCase() : '';
export const needsVehicleGrant = listing => listing.listingType === 'physical' && listing.category === 'Vehicles' && ['cars', 'motorcycles'].includes(vehicleType(listing));
export function requireVehicleGrant(listing) {
  if (listing.listingType === 'physical' && listing.category === 'Vehicles' && !['cars', 'motorcycles', 'bicycles', 'other vehicles'].includes(vehicleType(listing))) {
    throw new AppError('Choose the specific vehicle category before submitting or approving.', 422, 'VEHICLE_CATEGORY_REQUIRED');
  }
  if (needsVehicleGrant(listing) && !listing.vehicleGrantRef) {
    throw new AppError('Upload the vehicle registration document before submitting this vehicle.', 409, 'VEHICLE_GRANT_REQUIRED');
  }
}
