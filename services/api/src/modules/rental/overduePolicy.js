import { env } from '../../config/env.js';
import { physicalRentalReturnDeadline } from '../../core/calendarDate.js';

export function overdueSince(rental, graceHours = env.overdueGraceHours) {
  if (rental.listingType !== 'physical' || !rental.endDate || rental.returnSubmission?.recordedAt ||
      !['active', 'overdue', 'disputed'].includes(rental.status)) return null;
  try { return new Date(physicalRentalReturnDeadline(rental.endDate).getTime() + graceHours * 3600000); }
  catch { return null; }
}

export function overdueSummary(rental, now = new Date(), graceHours = env.overdueGraceHours) {
  const since = overdueSince(rental, graceHours);
  const overdue = Boolean(since && since <= now);
  return { isOverdue: overdue, needsAttention: overdue && now - since >= 86400000,
    ...(overdue && { since: since.toISOString() }) };
}
