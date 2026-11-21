import { AppError } from '../../core/errors.js';
import { overdueSummary } from '../rental/overduePolicy.js';
export function availableDisputeCategories(rental, role, now = new Date()) {
  if (rental.listingType !== 'physical') return ['service_quality', 'non_delivery', 'scope_mismatch', 'cancellation', 'communication', 'other'];
  const started = rental.handover?.receiptStatus === 'acknowledged' || ['active', 'overdue', 'return_submitted', 'completion_pending'].includes(rental.status);
  const reviewingReceipt = rental.status === 'scheduled' && rental.handover?.receiptStatus === 'pending';
  return [...(started || role === 'renter' && reviewingReceipt ? ['damaged_item', 'missing_item'] : []),
    ...(rental.returnSubmission?.recordedAt ? ['return_condition', 'deposit_deduction'] : []),
    ...(started && overdueSummary(rental, now).isOverdue ? ['late_return'] : []), 'communication', 'other'];
}
export function assertDisputeCategory(rental, role, category, now) {
  const domain = rental.listingType === 'physical'
    ? ['damaged_item', 'return_condition', 'missing_item', 'deposit_deduction', 'late_return', 'communication', 'other']
    : ['service_quality', 'non_delivery', 'scope_mismatch', 'cancellation', 'communication', 'other'];
  if (!domain.includes(category)) throw new AppError('This reason does not apply to this booking type.', 400, 'INVALID_DISPUTE_CATEGORY');
  const available = availableDisputeCategories(rental, role, now);
  if (!available.includes(category)) throw new AppError('This issue does not apply at the current rental stage. Choose another reason.', 409, 'DISPUTE_CATEGORY_UNAVAILABLE', { availableCategories: available });
}
