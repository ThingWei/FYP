import { env } from '../../config/env.js';
import { notifyUser } from '../communication/notification.service.js';
import { voidBookingPayment } from '../payment/payment.service.js';
import { BookingModel } from './booking.model.js';

function subtractMinutes(date, minutes) {
  return new Date(date.getTime() - minutes * 60 * 1000);
}

export function duePendingBookingFilter({
  now = new Date(),
  expiryMinutes = env.pendingBookingExpiryMinutes,
  scope = {},
} = {}) {
  return {
    ...scope,
    status: 'pending',
    $or: [
      { expiresAt: { $lte: now } },
      {
        expiresAt: null,
        createdAt: { $lte: subtractMinutes(now, expiryMinutes) },
      },
    ],
  };
}

export async function expireDuePendingBookings({
  now = new Date(),
  expiryMinutes = env.pendingBookingExpiryMinutes,
  scope = {},
} = {}) {
  const criteria = duePendingBookingFilter({ now, expiryMinutes, scope });
  const bookings = await BookingModel.find(criteria);
  let expired = 0;

  for (const booking of bookings) {
    const claimed = await BookingModel.findOneAndUpdate(
      { _id: booking._id, ...criteria },
      {
        $set: {
          status: 'expired',
          expiredAt: now,
          cancellationReason:
            'Automatically expired because the Owner did not respond in time.',
        },
      },
      { new: true },
    );
    if (!claimed) continue;

    const hadAuthorization = claimed.paymentStatus === 'authorized';
    await voidBookingPayment(claimed);
    await claimed.save();
    const body = hadAuthorization
      ? `${claimed.listingTitle} expired because the Owner did not respond in time. Your simulated payment authorization was released.`
      : `${claimed.listingTitle} expired because payment and Owner approval were not completed in time.`;
    await Promise.all([
      notifyUser({
        userId: claimed.renterId,
        category: 'booking',
        type: 'booking_expired',
        title: 'Booking request expired',
        body,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.renterId}`,
      }),
      notifyUser({
        userId: claimed.ownerId,
        category: 'booking',
        type: 'booking_expired',
        title: 'Booking request expired',
        body: `${claimed.listingTitle} expired because it was not decided in time.`,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.ownerId}`,
      }),
    ]);
    expired += 1;
  }
  return expired;
}
