import { BookingModel } from './booking.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { bookingPaymentDeadline, payableBookingFilter, paymentDeadlineExpression, PAYMENT_REMINDER_MINUTES } from './bookingDeadlines.js';

function timeLabel(value) {
  return new Intl.DateTimeFormat('en-MY', { timeZone: 'Asia/Kuala_Lumpur', hour: 'numeric', minute: '2-digit', hour12: true }).format(value) + ' MYT';
}

export async function notifyPaymentDue(booking) {
  const due = bookingPaymentDeadline(booking);
  if (booking.status !== 'pending' || booking.paymentStatus !== 'unpaid' || !due || due <= new Date()) return;
  return notifyUser({ userId: booking.renterId, category: 'payment', type: 'booking_payment_due',
    title: 'Finish your payment', body: `Pay for ${booking.listingTitle} by ${timeLabel(due)}. Unpaid checkouts expire after 10 minutes.`,
    entityType: 'booking', entityId: booking.publicId, dedupeKey: `booking-payment-due:${booking.publicId}` });
}

export async function sendUnpaidPaymentReminders(now = new Date()) {
  const rows = await BookingModel.find({ ...payableBookingFilter(now),
    $and: [{ $expr: { $lte: [paymentDeadlineExpression, new Date(now.getTime() + PAYMENT_REMINDER_MINUTES * 60_000)] } }],
  }).limit(200);
  let reminders = 0;
  for (const booking of rows) {
    // Recheck immediately before notification; never remind a paid/terminal record.
    if (!await BookingModel.exists({ _id: booking._id, ...payableBookingFilter(now) })) continue;
    const notice = await notifyUser({ userId: booking.renterId, category: 'payment', type: 'booking_payment_reminder',
      title: 'Your payment window is ending', body: `Complete payment for ${booking.listingTitle} by ${timeLabel(bookingPaymentDeadline(booking))}, or this checkout will expire.`,
      entityType: 'booking', entityId: booking.publicId, dedupeKey: `booking-payment-reminder:${booking.publicId}` });
    if (notice) reminders++;
  }
  return reminders;
}
