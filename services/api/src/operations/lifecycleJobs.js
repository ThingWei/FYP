import { env } from '../config/env.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { notifyUser } from '../modules/communication/notification.service.js';
import { voidBookingPayment } from '../modules/payment/payment.service.js';
import { RentalModel } from '../modules/rental/rental.model.js';

const state = {
  enabled: env.lifecycleJobsEnabled,
  running: false,
  startedAt: null,
  lastRunAt: null,
  lastCompletedAt: null,
  lastResult: null,
  lastError: '',
};

let interval;

function addHours(date, hours) {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
}

function subtractMinutes(date, minutes) {
  return new Date(date.getTime() - minutes * 60 * 1000);
}

async function notifyParticipant(rental, userId, type, title, body) {
  return notifyUser({
    userId,
    category: 'rental',
    type,
    title,
    body,
    entityType: 'rental',
    entityId: rental.publicId,
    dedupeKey: `${type}:${rental.publicId}:${userId}`,
  });
}

async function bookingTitle(rental) {
  const booking = await BookingModel.findOne({ publicId: rental.bookingId })
    .select('listingTitle')
    .lean();
  return booking?.listingTitle ?? 'your booking';
}

async function expirePendingBookings(now, expiryMinutes) {
  const fallbackCutoff = subtractMinutes(now, expiryMinutes);
  const bookings = await BookingModel.find({
    status: 'pending',
    paymentStatus: 'unpaid',
    $or: [
      { expiresAt: { $lte: now } },
      { expiresAt: null, createdAt: { $lte: fallbackCutoff } },
    ],
  });

  let expired = 0;
  for (const booking of bookings) {
    const claimed = await BookingModel.findOne({
      _id: booking._id,
      status: 'pending',
      paymentStatus: 'unpaid',
    });
    if (!claimed) continue;
    await voidBookingPayment(claimed);
    claimed.status = 'expired';
    claimed.expiredAt = now;
    claimed.cancellationReason =
      'Automatically expired because payment was not authorized in time.';
    await claimed.save();
    await Promise.all([
      notifyUser({
        userId: claimed.renterId,
        category: 'booking',
        type: 'booking_expired',
        title: 'Booking request expired',
        body: `${claimed.listingTitle} expired before payment authorization.`,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.renterId}`,
      }),
      notifyUser({
        userId: claimed.ownerId,
        category: 'booking',
        type: 'booking_expired',
        title: 'Booking request expired',
        body: `${claimed.listingTitle} expired before payment authorization.`,
        entityType: 'booking',
        entityId: claimed.publicId,
        dedupeKey: `booking_expired:${claimed.publicId}:${claimed.ownerId}`,
      }),
    ]);
    expired += 1;
  }
  return expired;
}

async function sendStartReminders(now, reminderHours) {
  const rentals = await RentalModel.find({
    status: 'scheduled',
    startDate: { $gte: now, $lte: addHours(now, reminderHours) },
    'automation.startReminderSentAt': null,
  });
  let sent = 0;
  for (const rental of rentals) {
    const title = await bookingTitle(rental);
    await Promise.all([
      notifyParticipant(
        rental,
        rental.renterId,
        'rental_start_reminder',
        'Booking starts soon',
        `${title} starts within ${reminderHours} hours.`,
      ),
      notifyParticipant(
        rental,
        rental.ownerId,
        'rental_start_reminder',
        'Booking starts soon',
        `${title} starts within ${reminderHours} hours.`,
      ),
    ]);
    rental.automation ??= {};
    rental.automation.startReminderSentAt = now;
    rental.automation.lastProcessedAt = now;
    await rental.save();
    sent += 2;
  }
  return sent;
}

async function sendPhysicalDueReminders(now, reminderHours) {
  const rentals = await RentalModel.find({
    listingType: 'physical',
    status: 'active',
    endDate: { $gte: now, $lte: addHours(now, reminderHours) },
    'automation.dueReminderSentAt': null,
  });
  let sent = 0;
  for (const rental of rentals) {
    const title = await bookingTitle(rental);
    await Promise.all([
      notifyParticipant(
        rental,
        rental.renterId,
        'rental_return_due',
        'Rental return due soon',
        `${title} is due within ${reminderHours} hours. Prepare return evidence.`,
      ),
      notifyParticipant(
        rental,
        rental.ownerId,
        'rental_return_due',
        'Rental return due soon',
        `${title} is due within ${reminderHours} hours.`,
      ),
    ]);
    rental.automation ??= {};
    rental.automation.dueReminderSentAt = now;
    rental.automation.lastProcessedAt = now;
    await rental.save();
    sent += 2;
  }
  return sent;
}

async function markOverdueRentals(now, graceHours) {
  const cutoff = new Date(now.getTime() - graceHours * 60 * 60 * 1000);
  const rentals = await RentalModel.find({
    listingType: 'physical',
    status: 'active',
    endDate: { $lt: cutoff },
  });
  let marked = 0;
  for (const rental of rentals) {
    rental.status = 'overdue';
    rental.automation ??= {};
    rental.automation.overdueNotifiedAt = now;
    rental.automation.lastProcessedAt = now;
    await rental.save();
    const title = await bookingTitle(rental);
    await Promise.all([
      notifyParticipant(
        rental,
        rental.renterId,
        'rental_overdue',
        'Rental is overdue',
        `${title} is overdue. Submit the return as soon as possible.`,
      ),
      notifyParticipant(
        rental,
        rental.ownerId,
        'rental_overdue',
        'Rental is overdue',
        `${title} has passed its return time without a return submission.`,
      ),
    ]);
    marked += 1;
  }
  return marked;
}

async function sendServiceReminders(now, reminderHours) {
  const due = await RentalModel.find({
    listingType: 'service',
    status: 'active',
    endDate: { $lt: now },
    'automation.serviceDueReminderSentAt': null,
  });
  const completion = await RentalModel.find({
    listingType: 'service',
    status: 'completion_pending',
    serviceDeliveredAt: {
      $lte: new Date(now.getTime() - reminderHours * 60 * 60 * 1000),
    },
    'automation.completionReminderSentAt': null,
  });
  let sent = 0;
  for (const rental of due) {
    const title = await bookingTitle(rental);
    await notifyParticipant(
      rental,
      rental.ownerId,
      'service_delivery_due',
      'Service completion is due',
      `Mark ${title} as delivered when the service is complete.`,
    );
    rental.automation ??= {};
    rental.automation.serviceDueReminderSentAt = now;
    rental.automation.lastProcessedAt = now;
    await rental.save();
    sent += 1;
  }
  for (const rental of completion) {
    const title = await bookingTitle(rental);
    await notifyParticipant(
      rental,
      rental.renterId,
      'service_completion_reminder',
      'Confirm service completion',
      `Please confirm completion for ${title}.`,
    );
    rental.automation ??= {};
    rental.automation.completionReminderSentAt = now;
    rental.automation.lastProcessedAt = now;
    await rental.save();
    sent += 1;
  }
  return sent;
}

export async function runLifecycleJobs({
  now = new Date(),
  expiryMinutes = env.pendingBookingExpiryMinutes,
  reminderHours = env.lifecycleReminderHours,
  graceHours = env.overdueGraceHours,
} = {}) {
  if (state.running) return { skipped: true, reason: 'already_running' };
  state.running = true;
  state.lastRunAt = now;
  state.lastError = '';
  try {
    const [expiredBookings, startReminders, dueReminders, overdueRentals, serviceReminders] =
      await Promise.all([
        expirePendingBookings(now, expiryMinutes),
        sendStartReminders(now, reminderHours),
        sendPhysicalDueReminders(now, reminderHours),
        markOverdueRentals(now, graceHours),
        sendServiceReminders(now, reminderHours),
      ]);
    state.lastResult = {
      expiredBookings,
      startReminders,
      dueReminders,
      overdueRentals,
      serviceReminders,
    };
    state.lastCompletedAt = new Date();
    return state.lastResult;
  } catch (error) {
    state.lastError = error.message;
    throw error;
  } finally {
    state.running = false;
  }
}

export function startLifecycleScheduler() {
  if (!env.lifecycleJobsEnabled || interval) return;
  state.enabled = true;
  state.startedAt = new Date();
  runLifecycleJobs().catch((error) =>
    console.error(`Lifecycle automation failed: ${error.message}`),
  );
  interval = setInterval(() => {
    runLifecycleJobs().catch((error) =>
      console.error(`Lifecycle automation failed: ${error.message}`),
    );
  }, env.lifecycleJobIntervalMs);
  interval.unref();
}

export function stopLifecycleScheduler() {
  if (interval) clearInterval(interval);
  interval = undefined;
  state.running = false;
}

export function lifecycleSchedulerStatus() {
  return {
    ...state,
    intervalMs: env.lifecycleJobIntervalMs,
    expiryMinutes: env.pendingBookingExpiryMinutes,
    reminderHours: env.lifecycleReminderHours,
    overdueGraceHours: env.overdueGraceHours,
  };
}
