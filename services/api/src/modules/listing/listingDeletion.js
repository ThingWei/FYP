import { AppError } from '../../core/errors.js';
import { ListingModel } from './listing.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';

const openBookings = ['pending', 'approved', 'active', 'disputed'];
const openRentals = ['scheduled', 'active', 'overdue', 'return_submitted', 'completion_pending', 'disputed'];
const explanation = 'Finish or cancel open bookings and resolve outstanding rentals or cases before deleting this listing.';

// Batched for list pages, with the same policy used again under the deletion lock.
export async function listingDeletionEligibility(listingIds) {
  const ids = [...new Set(listingIds)];
  if (!ids.length) return new Map();
  const [bookings, rentals, disputes] = await Promise.all([
    BookingModel.distinct('listingId', { listingId: { $in: ids }, status: { $in: openBookings } }),
    RentalModel.distinct('listingId', { listingId: { $in: ids }, status: { $in: openRentals } }),
    DisputeModel.distinct('listingId', { listingId: { $in: ids }, status: { $nin: ['resolved', 'dismissed'] } }),
  ]);
  const blocked = new Set([...bookings, ...rentals, ...disputes]);
  return new Map(ids.map(id => [id, {
    allowed: !blocked.has(id),
    ...(blocked.has(id) && { reason: explanation, bookingsPath: '/bookings' }),
  }]));
}

export async function withListingDeletionEligibility(listings) {
  const eligibility = await listingDeletionEligibility(listings.map(row => row.publicId));
  for (const row of listings) row.$locals.deleteEligibility = eligibility.get(row.publicId);
  return listings;
}

export async function deleteListing(id, identity, { admin = false } = {}) {
  const context = await ListingModel.findOne({ publicId: id, ...(!admin && { ownerId: identity.authId }) });
  if (!context || admin && !identity.roles?.includes('admin')) {
    throw new AppError('Listing not found', 404, 'NOT_FOUND');
  }
  return withOperationLock('listing-decision', context.publicId, async ensureOwned => {
    const listing = await ListingModel.findById(context._id);
    if (listing.deletedAt) return { id: listing.publicId, deleted: true, alreadyDeleted: true };
    const eligibility = (await listingDeletionEligibility([listing.publicId])).get(listing.publicId);
    if (!eligibility.allowed) throw new AppError(explanation, 409, 'LISTING_HAS_OPEN_BOOKINGS', eligibility);
    await ensureOwned();
    await ListingModel.updateOne({ _id: listing._id, deletedAt: null }, {
      $set: { status: 'inactive', deletedAt: new Date(), deletedBy: identity.authId },
    });
    return { id: listing.publicId, deleted: true };
  });
}
