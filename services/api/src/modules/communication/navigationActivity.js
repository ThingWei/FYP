import { BookingModel } from '../booking/booking.model.js';
import { duePendingBookingFilter } from '../booking/bookingExpiry.js';
import { ListingModel } from '../listing/listing.model.js';
import { MessageModel } from './message.model.js';
import { NotificationModel } from './notification.model.js';

// Account-wide counts must not depend on the current list's filter or page.
export async function navigationActivity(userId, now = new Date()) {
  const notExpired = { $nor: [duePendingBookingFilter({ now })] };
  const [requests, listings, updates, checkouts, messages] = await Promise.all([
    BookingModel.countDocuments({ ownerId: userId, renterId: { $ne: userId },
      status: 'pending', paymentStatus: 'authorized', ...notExpired }),
    ListingModel.countDocuments({ ownerId: userId,
      status: { $in: ['draft', 'pending_review', 'rejected'] } }),
    NotificationModel.countDocuments({ userId, readAt: null,
      category: { $in: ['booking', 'rental', 'payment'] } }),
    BookingModel.countDocuments({ renterId: userId, status: 'pending',
      paymentStatus: 'unpaid', ...notExpired }),
    MessageModel.countDocuments({ recipientId: userId, readAt: null,
      recalledAt: null, deletedFor: { $ne: userId } }),
  ]);
  return { requests, listings, bookings: updates + checkouts, messages };
}
