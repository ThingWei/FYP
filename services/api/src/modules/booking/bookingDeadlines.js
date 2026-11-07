export const PAYMENT_WINDOW_MINUTES = 10;
export const PAYMENT_REMINDER_MINUTES = 2;
const milliseconds = PAYMENT_WINDOW_MINUTES * 60_000;
const date = (value) => { const parsed = value ? new Date(value) : null; return parsed && Number.isFinite(parsed.getTime()) ? parsed : null; };

export function bookingPaymentDeadline(booking) {
  const explicit = date(booking.paymentDueAt);
  const created = date(booking.createdAt);
  const due = explicit ?? (created ? new Date(created.getTime() + milliseconds) : null);
  const decision = date(booking.expiresAt);
  return due && decision && decision < due ? decision : due;
}

// Legacy unpaid records use their creation time, never a new window on read.
export const paymentDeadlineExpression = { $min: [
  { $ifNull: ['$paymentDueAt', { $add: ['$createdAt', milliseconds] }] },
  { $ifNull: ['$expiresAt', new Date('9999-12-31T00:00:00Z')] },
] };

export function payableBookingFilter(now = new Date()) {
  return { status: 'pending', paymentStatus: 'unpaid', $expr: { $gt: [paymentDeadlineExpression, now] } };
}
