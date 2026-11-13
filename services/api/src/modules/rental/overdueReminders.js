import { randomUUID, createHash } from 'node:crypto';
import { RentalModel } from './rental.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { UserModel } from '../user/user.model.js';
import { OverdueDeliveryModel as Delivery } from './overdueDelivery.model.js';
import { overdueSummary, overdueSince } from './overduePolicy.js';
import { env } from '../../config/env.js';
import { physicalRentalDate } from '../../core/calendarDate.js';
import { notifyUser } from '../communication/notification.service.js';
import { emailClient } from '../../integrations/emailClient.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { recoverListingOperations } from '../../operations/lifecycleJournal.js';

const day = 86400000;
async function enqueue(rental, userId, role, stage, channel, deadline, now) {
  const key = `overdue:${rental.publicId}:${deadline.getTime()}:${stage}:${channel}:${userId}`;
  try {
    await Delivery.updateOne({ key }, { $setOnInsert: { key, rentalId: rental.publicId,
      userId, role, stage, channel, deadline, status: 'pending', attempts: 0, nextAttemptAt: now } }, { upsert: true });
  } catch (error) { if (error.code !== 11000) throw error; }
}

export function deliveryFailure(error) {
  const connectionFailure = (!error?.command || error.command === 'CONN') &&
    ['EDNS', 'ECONNECTION', 'ECONNREFUSED', 'ENOTFOUND', 'ETIMEDOUT'].includes(error?.code);
  const rejected = error?.deliveryOutcome === 'not_sent' || Number(error?.responseCode) >= 400 ||
    ['CONN', 'EHLO', 'HELO', 'AUTH', 'MAIL FROM', 'RCPT TO'].includes(error?.command) ||
    error?.code === 'EAUTH' || connectionFailure;
  return { known: rejected, retryable: rejected && (error?.retryable === true ||
    Number(error?.responseCode) >= 400 && Number(error?.responseCode) < 500 ||
    connectionFailure) };
}

export async function runOverdueReminders({ now = new Date(), graceHours = env.overdueGraceHours,
  sendEmail = input => emailClient.sendOverdueReminder(input), notify = notifyUser, limit = 100 } = {}) {
  await Delivery.init();
  const indexes = await Delivery.collection.indexes();
  if (!indexes.some(index => index.unique === true && index.key?.key === 1 && Object.keys(index.key).length === 1)) {
    throw new Error('Overdue reminder uniqueness index is unavailable');
  }
  const result = { sent: 0, failed: 0, uncertain: 0, escalated: 0 };
  // Stream rather than repeatedly truncating the same first batch. Work per
  // rental and delivery dispatch is bounded; no live data cleanup/backfill.
  const rentals = RentalModel.find({ listingType: 'physical', status: { $in: ['active', 'overdue'] },
    endDate: { $lt: physicalRentalDate(new Date(now.getTime() - graceHours * 3600000)) },
    'returnSubmission.recordedAt': null }).select('publicId bookingId listingId renterId ownerId listingType status endDate returnSubmission').lean().cursor();
  try {
  for await (const candidate of rentals) {
    if (!overdueSummary(candidate, now, graceHours).isOverdue) continue;
    await withOperationLock('listing-decision', candidate.listingId, async ensureOwned => {
      await recoverListingOperations(candidate.listingId, ensureOwned);
      const rental = await RentalModel.findById(candidate._id).lean();
      if (!rental || !['active', 'overdue'].includes(rental.status) || !overdueSummary(rental, now, graceHours).isOverdue) return;
      const deadline = overdueSince(rental, graceHours);
      if (await BookingModel.exists({ publicId: rental.bookingId, status: { $in: ['completed', 'cancelled', 'expired', 'disputed'] } })) return;
      const followup = now - deadline >= day;
      const stage = followup ? 'followup' : 'initial';
      await ensureOwned();
      if (followup) {
        await Delivery.updateMany({ rentalId: rental.publicId, deadline, stage: 'initial', status: { $in: ['pending', 'retry'] } },
          { $set: { status: 'superseded', result: 'newer_reminder' } });
        const changed = await RentalModel.updateOne({ _id: rental._id, 'automation.overdueEscalationDeadline': { $ne: deadline } },
          { $set: { 'automation.overdueEscalatedAt': now, 'automation.overdueEscalationDeadline': deadline } });
        if (changed.modifiedCount) result.escalated++;
        const admins = UserModel.find({ roles: 'admin', accountStatus: 'active' }).select('authId').lean().cursor();
        try { for await (const admin of admins) {
          await enqueue(rental, admin.authId, 'admin', 'admin', 'notification', deadline, now);
        } } finally { await admins.close(); }
      }
      for (const role of ['renter', 'owner']) {
        for (const channel of ['notification', 'email']) {
          await enqueue(rental, rental[`${role}Id`], role, stage, channel, deadline, now);
        }
      }
    });
  }
  } finally { await rentals.close(); }
  // If a worker died during SMTP delivery its result is unknown. Do not
  // automatically resend. Notification delivery is safe to replay by key.
  await Delivery.updateMany({ status: 'sending', leaseUntil: { $lte: now }, channel: 'email' },
    { $set: { status: 'uncertain', result: 'unknown_delivery' }, $unset: { leaseToken: 1, leaseUntil: 1 } });
  await Delivery.updateMany({ status: 'sending', leaseUntil: { $lte: now }, channel: 'notification' },
    { $set: { status: 'retry', nextAttemptAt: now }, $unset: { leaseToken: 1, leaseUntil: 1 } });
  const dispatchStart = performance.now();
  for (let i = 0; i < limit && performance.now() - dispatchStart < 20000; i++) {
    const token = randomUUID();
    const row = await Delivery.findOneAndUpdate({ status: { $in: ['pending', 'retry'] }, nextAttemptAt: { $lte: now } },
      { $set: { status: 'sending', leaseToken: token, leaseUntil: new Date(now.getTime() + 120000) } },
      { new: true, sort: { nextAttemptAt: 1, _id: 1 } });
    if (!row) break;
    const finish = (status, fields = {}) => Delivery.updateOne({ _id: row._id, leaseToken: token, status: 'sending' },
      { $set: { status, ...fields }, $unset: { leaseToken: 1, leaseUntil: 1 } });
    let dispatchStarted = false;
    try {
      // Prepare against fresh lifecycle state, then release its lock before any
      // network delivery. SMTP must not block a renter from submitting a return.
      const context = await RentalModel.findOne({ publicId: row.rentalId }).select('listingId').lean();
      if (!context) { await finish('cancelled', { result: 'state_changed' }); continue; }
      const prepared = await withOperationLock('listing-decision', context.listingId, async ensureOwned => {
        await recoverListingOperations(context.listingId, ensureOwned);
        const rental = await RentalModel.findOne({ publicId: row.rentalId }).lean();
        const info = rental && overdueSummary(rental, now, graceHours);
        if (!rental || !['active', 'overdue'].includes(rental.status) || !info.isOverdue ||
            overdueSince(rental, graceHours)?.getTime() !== row.deadline.getTime() ||
            row.role !== 'admin' && rental[`${row.role}Id`] !== row.userId) {
          await finish('cancelled', { result: 'state_changed' }); return;
        }
        if (row.stage === 'initial' && now - row.deadline >= day) {
          await finish('superseded', { result: 'newer_reminder' }); return;
        }
        const [user, booking] = await Promise.all([
          UserModel.findOne({ authId: row.userId }).select('email displayName settings roles accountStatus').lean(),
          BookingModel.findOne({ publicId: rental.bookingId }).select('listingTitle publicId status').lean(),
        ]);
        if (!user || !booking || row.role === 'admin' && (!user.roles.includes('admin') || user.accountStatus !== 'active')) {
          await finish('skipped', { result: 'recipient_unavailable' }); return;
        }
        if (['completed', 'cancelled', 'expired', 'disputed'].includes(booking.status)) {
          await finish('cancelled', { result: 'state_changed' }); return;
        }
        if (row.channel === 'email' && user.settings?.emailNotifications === false) {
          await finish('skipped', { result: 'opted_out' }); return;
        }
        if (row.channel === 'email' && env.emailMode === 'disabled') {
          await finish('retry', { result: 'disabled', nextAttemptAt: new Date(now.getTime() + 3600000) }); return;
        }
        if (row.channel === 'email' && (!user.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(user.email))) {
          await finish('skipped', { result: 'recipient_unavailable' }); return;
        }
        await ensureOwned();
        const claimed = await Delivery.updateOne({ _id: row._id, leaseToken: token, status: 'sending', leaseUntil: { $gt: now } }, { $inc: { attempts: 1 } });
        if (!claimed.modifiedCount) return;
        return { rental, user, booking };
      });
      if (!prepared) continue;
      const { rental, user, booking } = prepared;
      dispatchStarted = true;
      const followup = row.stage !== 'initial';
        if (row.channel === 'email') {
          const response = await sendEmail({ email: user.email, displayName: user.displayName,
            itemTitle: booking.listingTitle, bookingReference: booking.publicId,
            returnDate: new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(rental.endDate),
            owner: row.role === 'owner', followup });
          if (response?.rejected?.length && !response?.accepted?.length) {
            const error = new Error('Delivery rejected'); error.deliveryOutcome = 'not_sent'; throw error;
          }
          if (!response?.accepted?.some(address => typeof address === 'string' && address.toLowerCase() === user.email.toLowerCase()) &&
              !(typeof response?.id === 'string' && response.id.length > 0)) {
            throw new Error('Delivery acknowledgement unavailable');
          }
        } else {
          await notify({ userId: row.userId, category: 'rental',
            type: row.stage === 'admin' ? 'rental_overdue_attention' : followup ? 'rental_overdue_followup' : 'rental_overdue',
            title: followup ? 'Overdue return needs attention' : 'Rental is overdue',
            body: row.role === 'admin' ? `An item has been unreturned for at least 24 hours. Review ${booking.publicId}.`
              : row.role === 'owner' ? 'Your item has not been recorded as returned. Message the renter or report item not returned in the rental details.'
                : 'Please arrange your return with the Owner. Open the rental to submit your return or report an issue.',
            entityType: 'rental', entityId: rental.publicId,
            dedupeKey: row.key.length <= 180 ? row.key : `overdue:${createHash('sha256').update(row.key).digest('hex')}` });
        }
        const finished = await finish('sent', { result: 'delivered', sentAt: now });
        if (finished.modifiedCount) result.sent++; else result.uncertain++;
    } catch (error) {
      const failure = !dispatchStarted || row.channel === 'notification' ? { known: true, retryable: true } : deliveryFailure(error);
      const attempts = (await Delivery.findById(row._id).select('attempts').lean())?.attempts ?? 1;
      if (!failure.known) { await finish('uncertain', { result: 'unknown_delivery' }); result.uncertain++; }
      else {
        const retry = failure.retryable && attempts < 5;
        await finish(retry ? 'retry' : 'failed', { result: retry ? 'temporary_failure' : 'rejected',
          nextAttemptAt: new Date(now.getTime() + Math.min(3600000, 60000 * 2 ** attempts)) });
        result.failed++;
      }
    }
  }
  return result;
}

export async function overdueDeliverySummary(rentalIds) {
  const rows = await Delivery.find({ rentalId: { $in: rentalIds } }).select('rentalId channel role stage status result sentAt deadline').sort({ deadline: 1, _id: 1 }).lean();
  const result = {};
  for (const row of rows) (result[row.rentalId] ??= []).push({ channel: row.channel, recipient: row.role,
    stage: row.stage, status: row.status, result: row.result, sentAt: row.sentAt, deadline: row.deadline });
  return result;
}
