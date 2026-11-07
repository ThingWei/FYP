import { env } from '../../config/env.js';
import { notifyUser } from '../communication/notification.service.js';
import { voidBookingPayment } from '../payment/payment.service.js';
import { bookingPaymentDeadline, paymentDeadlineExpression } from './bookingDeadlines.js';
import { PaymentModel } from '../payment/payment.model.js';
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
    $and: [{ $or: [
      { paymentStatus: 'unpaid', $expr: { $lte: [paymentDeadlineExpression, now] } },
      { paymentStatus: { $ne: 'unpaid' }, $or: [
        { expiresAt: { $lte: now } },
        { expiresAt: null, createdAt: { $lte: subtractMinutes(now, expiryMinutes) } },
      ] },
    ] }],
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
    // A crash can persist a timely authorization before linking the booking.
    // Recover that durable success, but never a late authorization or terminal row.
    if (booking.paymentStatus === 'unpaid' && (!booking.expiresAt || booking.expiresAt > now)) {
      const due = bookingPaymentDeadline(booking);
      const authorization = due && await PaymentModel.findOne({ bookingId: booking.publicId,
        type: 'authorization', status: 'authorized', createdAt: { $lt: due },
        'metadata.extensionId': { $exists: false }, payerId: booking.renterId,
        amount: booking.pricing.total });
      if (authorization) {
        const restored = await BookingModel.findOneAndUpdate({ _id: booking._id,
          status: 'pending', paymentStatus: 'unpaid',
          $or: [{ expiresAt: { $gt: now } }, { expiresAt: null }],
        }, { $set: { paymentStatus: 'authorized', paymentAuthorizationId: authorization.publicId } });
        if (restored) {
          await notifyUser({ userId: booking.ownerId, category: 'payment', type: 'payment_authorized',
            title: 'Demo payment ready', body: `Payment for ${booking.listingTitle} is ready. Review the booking request.`,
            entityType: 'payment', entityId: authorization.publicId, dedupeKey: `payment-authorized:${authorization.publicId}` });
          continue;
        }
      }
    }
    const claimed = await BookingModel.findOneAndUpdate(
      { _id: booking._id, ...criteria },
      {
        $set: {
          status: 'expired',
          expiredAt: now,
          cancellationReason:
            booking.paymentStatus === 'unpaid' ? 'Payment was not completed within 10 minutes.' : 'Automatically expired because the Owner did not respond in time.',
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
      : `${claimed.listingTitle} checkout expired because payment was not completed within 10 minutes. No payment was taken. You can choose dates and try again.`;
    await Promise.all([
      notifyUser({
        userId: claimed.renterId,
        category: 'booking',
        type: 'booking_expired',
        title: booking.paymentStatus === 'unpaid' ? 'Payment window expired' : 'Booking request expired',
        body,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.renterId}`,
      }),
      notifyUser({
        userId: claimed.ownerId,
        category: 'booking',
        type: 'booking_expired',
        title: booking.paymentStatus === 'unpaid' ? 'Payment window expired' : 'Booking request expired',
        body: booking.paymentStatus === 'unpaid' ? `${claimed.listingTitle} checkout expired without payment.` : `${claimed.listingTitle} expired because it was not decided in time.`,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.ownerId}`,
      }),
    ]);
    expired += 1;
  }
  return expired;
}
