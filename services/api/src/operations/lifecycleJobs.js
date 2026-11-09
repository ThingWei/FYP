import { env } from '../config/env.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { notifyUser } from '../modules/communication/notification.service.js';
import { voidTerminalPaymentHolds } from '../modules/payment/payment.service.js';
import { RentalModel } from '../modules/rental/rental.model.js';
import { runDueReportSchedules } from '../modules/admin/report.service.js';
import { withOperationLock } from '../modules/booking/bookingRequestLock.js';
import { recoverLifecycleOperations, recoverListingOperations } from './lifecycleJournal.js';
import { expireRentalExtensions } from '../modules/rental/rental.service.js';
import { physicalRentalDate, physicalRentalReturnDeadline } from '../core/calendarDate.js';
import { sendUnpaidPaymentReminders } from '../modules/booking/bookingPaymentReminders.js';
import { expireDuePendingBookings } from '../modules/booking/bookingExpiry.js';
import { expireUncollectedRentals } from '../modules/rental/uncollectedExpiry.js';

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
let paymentInterval;
let paymentJobsRunning = false;
const paymentIntervalMs = 30_000;

export async function runPaymentDeadlineJobs({ now = new Date() } = {}) {
  if (paymentJobsRunning) return { skipped: true };
  paymentJobsRunning = true;
  try {
    const expired = await expireDuePendingBookings({ now, scope: { paymentStatus: 'unpaid' } });
    const reminders = await sendUnpaidPaymentReminders(now);
    return { expired, reminders };
  } finally { paymentJobsRunning = false; }
}

function addHours(date, hours) {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
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
  const windowEnd = addHours(now, reminderHours);
  const firstDay = physicalRentalDate(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  const lastDayExclusive = new Date(physicalRentalDate(windowEnd).getTime() + 24 * 60 * 60 * 1000);
  const rentals = await RentalModel.find({
    listingType: 'physical',
    status: 'active',
    endDate: { $gte: firstDay, $lt: lastDayExclusive },
    'automation.dueReminderSentAt': null,
  });
  let sent = 0;
  for (const rental of rentals) {
    const deadline = physicalRentalReturnDeadline(rental.endDate);
    if (deadline < now || deadline > windowEnd) continue;
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
  // endDate stores an inclusive calendar day, not its return-time instant.
  // Only days before the current Malaysia day (after grace) have ended.
  const cutoff = physicalRentalDate(new Date(now.getTime() - graceHours * 60 * 60 * 1000));
  const rentals = await RentalModel.find({
    listingType: 'physical',
    status: 'active',
    endDate: { $lt: cutoff },
  });
  let marked = 0;
  for (const rental of rentals) {
    await withOperationLock('listing-decision', rental.listingId, async (ensureOwned) => {
      await recoverListingOperations(rental.listingId, ensureOwned);
      const claimed = await RentalModel.findOneAndUpdate({ _id: rental._id, status: 'active', endDate: { $lt: cutoff } }, {
        $set: { status: 'overdue', 'automation.overdueNotifiedAt': now, 'automation.lastProcessedAt': now },
      }, { new: true });
      if (!claimed) return;
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
    });
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
    const recoveredListings = await recoverLifecycleOperations();
    const expiredExtensions = await expireRentalExtensions(now);
    const voidedTerminalHolds = await voidTerminalPaymentHolds();
    const uncollectedRentals = await expireUncollectedRentals({ now });
    const [
      expiredBookings,
      startReminders,
      dueReminders,
      overdueRentals,
      serviceReminders,
      scheduledReports,
    ] =
      await Promise.all([
        expireDuePendingBookings({ now, expiryMinutes }),
        sendStartReminders(now, reminderHours),
        sendPhysicalDueReminders(now, reminderHours),
        markOverdueRentals(now, graceHours),
        sendServiceReminders(now, reminderHours),
        runDueReportSchedules(now),
      ]);
    state.lastResult = {
      recoveredListings,
      expiredExtensions,
      voidedTerminalHolds,
      uncollectedRentals,
      expiredBookings,
      startReminders,
      dueReminders,
      overdueRentals,
      serviceReminders,
      scheduledReports,
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
  // Payment deadlines need a short heartbeat without rerunning reports and
  // unrelated rental tasks every 30 seconds.
  paymentInterval = setInterval(() => {
    runPaymentDeadlineJobs().catch(() => console.error('Payment deadline check failed; it will be retried.'));
  }, paymentIntervalMs);
  paymentInterval.unref();
  interval = setInterval(() => {
    runLifecycleJobs().catch((error) =>
      console.error(`Lifecycle automation failed: ${error.message}`),
    );
  }, env.lifecycleJobIntervalMs);
  interval.unref();
}

export function stopLifecycleScheduler() {
  if (interval) clearInterval(interval);
  if (paymentInterval) clearInterval(paymentInterval);
  paymentInterval = undefined;
  interval = undefined;
  state.running = false;
}

export function lifecycleSchedulerStatus() {
  return {
    ...state,
    intervalMs: env.lifecycleJobIntervalMs,
    paymentIntervalMs,
    expiryMinutes: env.pendingBookingExpiryMinutes,
    reminderHours: env.lifecycleReminderHours,
    overdueGraceHours: env.overdueGraceHours,
  };
}
