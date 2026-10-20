import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { PaymentModel } from './payment.model.js';

export const cents = (value) => Math.round(value * 100);
const outflows = new Set(['refund', 'deposit_release', 'dispute_release', 'owner_settlement', 'platform_retention']);

export async function bookingBalance(bookingId) {
  const payments = await PaymentModel.find({ bookingId, status: 'succeeded' });
  let captured = 0;
  let distributed = 0;
  for (const payment of payments) {
    if (payment.type === 'capture') captured += cents(payment.amount);
    if (outflows.has(payment.type)) distributed += cents(payment.amount);
  }
  return { captured: captured / 100, distributed: distributed / 100,
    held: Math.max(captured - distributed, 0) / 100,
    reconciliationRequired: distributed > captured };
}

export function ledgerEntry(booking, type, amount, key, options = {}) {
  return new PaymentModel({
    publicId: `TXN-${type === 'capture' ? 'CAP' : type === 'refund' ? 'REF' : 'SET'}-${new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase()}`,
    bookingId: booking.publicId,
    payerId: type === 'capture' ? booking.renterId : 'renthub:simulated-holding',
    payeeId: ['refund', 'deposit_release', 'dispute_release'].includes(type) ? booking.renterId :
      type === 'platform_retention' ? 'renthub:simulated-platform' : booking.ownerId,
    type, amount, method: 'system', status: 'succeeded',
    gatewayReference: `system_${key}`, idempotencyKey: key, simulated: true, ...options,
  });
}

// Plan all effects before writing any. An interrupted plan is replayed, never
// recomputed against its partially consumed balance.
export async function planAllocations(booking, key, allocations) {
  if (allocations.some((item) => !Number.isFinite(item.amount) || item.amount < 0 || cents(item.amount) / 100 !== item.amount)) {
    throw new AppError('Settlement amounts must be valid MYR amounts', 400, 'INVALID_AMOUNT');
  }
  const balance = await bookingBalance(booking.publicId);
  const requested = allocations.reduce((sum, item) => sum + (item.type === 'deposit_deduction' ? 0 : cents(item.amount)), 0);
  if (balance.reconciliationRequired || requested > cents(balance.held)) {
    throw new AppError('Some money has already been refunded or paid out. An administrator must review the remaining balance.', 409, 'SETTLEMENT_REVIEW_REQUIRED');
  }
  return allocations.filter((item) => item.amount > 0).map((item) =>
    ledgerEntry(booking, item.type, item.amount, `${key}:${item.type}`, { reason: item.reason ?? '', metadata: { operation: key } }));
}
