import mongoose from 'mongoose';
import { paymentAdapter } from '../../integrations/paymentAdapter.js';
import { AppError } from '../../core/errors.js';
import { BookingModel } from '../booking/booking.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { UserModel } from '../user/user.model.js';
import { PAYMENT_STATUSES, PAYMENT_TYPES } from './payment.model.js';
import { paymentRepository } from './payment.repository.js';

function transactionId(type) {
  const code = {
    authorization: 'AUTH',
    capture: 'CAP',
    refund: 'REF',
    deposit_release: 'DEP',
    deposit_deduction: 'DED',
    owner_settlement: 'SET',
  }[type];
  const suffix = new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase();
  return `TXN-${code}-${suffix}`;
}

function pages(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

async function requireActiveUser(identity, role) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) {
    throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  if (role && !user.roles.includes(role)) {
    throw new AppError(`${role} role is required`, 403, 'FORBIDDEN');
  }
  return user;
}

async function systemTransaction({
  booking,
  type,
  amount,
  status = 'succeeded',
  parentTransactionId = '',
  reason = '',
}) {
  const idempotencyKey = `${type}:${booking.publicId}`;
  const existing = await paymentRepository.findByIdempotencyKey(idempotencyKey);
  if (existing) return existing;
  return paymentRepository.create({
    publicId: transactionId(type),
    bookingId: booking.publicId,
    payerId: booking.renterId,
    payeeId: booking.ownerId,
    type,
    amount,
    method: 'system',
    status,
    gatewayReference: `system_${type}_${booking.publicId}`,
    idempotencyKey,
    parentTransactionId,
    reason,
    simulated: true,
  });
}

export async function captureBookingPayment(booking) {
  if (['captured', 'settled', 'partially_refunded', 'refunded'].includes(booking.paymentStatus)) {
    return paymentRepository.findCapture(booking.publicId);
  }
  const authorization = await paymentRepository.findAuthorization(booking.publicId);
  if (!authorization || authorization.status !== 'authorized') {
    throw new AppError(
      'An active payment authorization is required',
      409,
      'PAYMENT_NOT_AUTHORIZED',
    );
  }
  const idempotencyKey = `capture:${booking.publicId}`;
  let capture = await paymentRepository.findByIdempotencyKey(idempotencyKey);
  if (!capture) {
    const gateway = await paymentAdapter.capture({ amount: booking.pricing.total });
    capture = await paymentRepository.create({
      publicId: transactionId('capture'),
      bookingId: booking.publicId,
      payerId: booking.renterId,
      payeeId: booking.ownerId,
      type: 'capture',
      amount: booking.pricing.total,
      method: authorization.method,
      status: gateway.status,
      gatewayReference: gateway.id,
      idempotencyKey,
      parentTransactionId: authorization.publicId,
      simulated: true,
    });
  }
  booking.paymentStatus = 'captured';
  return capture;
}

export async function voidBookingPayment(booking) {
  const authorization = await paymentRepository.findAuthorization(booking.publicId);
  if (!authorization || authorization.status !== 'authorized') return null;
  await paymentAdapter.voidAuthorization({ amount: authorization.amount });
  const voided = await paymentRepository.updateStatus(authorization._id, 'voided');
  booking.paymentStatus = 'voided';
  return voided;
}

export async function recordPhysicalSettlement(booking, deduction) {
  const capture = await paymentRepository.findCapture(booking.publicId);
  if (!capture) {
    throw new AppError('Captured payment not found', 409, 'CAPTURE_MISSING');
  }
  const deposit = booking.pricing.securityDeposit;
  const release = Math.max(deposit - deduction, 0);
  if (release > 0) {
    await systemTransaction({
      booking,
      type: 'deposit_release',
      amount: release,
      parentTransactionId: capture.publicId,
    });
  }
  if (deduction > 0) {
    await systemTransaction({
      booking,
      type: 'deposit_deduction',
      amount: deduction,
      parentTransactionId: capture.publicId,
      reason: 'Owner-confirmed return deduction',
    });
  }
  await systemTransaction({
    booking,
    type: 'owner_settlement',
    amount: booking.pricing.baseAmount + booking.pricing.damageWaiverFee + (booking.pricing.deliveryFee ?? 0) + deduction,
    parentTransactionId: capture.publicId,
  });
  booking.paymentStatus = 'settled';
}

export async function recordServiceSettlement(booking) {
  const capture = await paymentRepository.findCapture(booking.publicId);
  if (!capture) {
    throw new AppError('Captured payment not found', 409, 'CAPTURE_MISSING');
  }
  await systemTransaction({
    booking,
    type: 'owner_settlement',
    amount: booking.pricing.baseAmount,
    parentTransactionId: capture.publicId,
  });
  booking.paymentStatus = 'settled';
}

function assertAttemptMatches(existing, input, identity, outcome) {
  if (existing && (existing.type !== 'authorization' || existing.bookingId !== input.bookingId ||
      existing.payerId !== identity.authId || existing.method !== input.method ||
      (existing.metadata?.get('simulationOutcome') ?? 'success') !== outcome)) {
    throw new AppError('Idempotency key is already in use', 409, 'IDEMPOTENCY_CONFLICT');
  }
}

export const paymentService = {
  async authorize(input, identity) {
    await requireActiveUser(identity, 'renter');
    const outcome = input.simulationOutcome ?? 'success';
    const booking = await BookingModel.findOne({ publicId: input.bookingId, renterId: identity.authId });
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    const existing = await paymentRepository.findByIdempotencyKey(input.idempotencyKey);
    assertAttemptMatches(existing, input, identity, outcome);
    const eligible = { publicId: booking.publicId, renterId: identity.authId, status: 'pending',
      $or: [{ expiresAt: { $gt: new Date() } }, { expiresAt: { $exists: false } }] };
    // Recover a durable authorization whose booking update was interrupted.
    const authorization = existing?.status === 'authorized' ? existing
      : await paymentRepository.findAuthorization(booking.publicId);
    if (authorization?.status === 'authorized') {
      // A successful payment ends the payment deadline, including recovery of a
      // durable authorization written before that deadline by an interrupted call.
      const recordedInTime = !booking.expiresAt ||
        authorization.createdAt instanceof Date && authorization.createdAt <= booking.expiresAt;
      const restored = recordedInTime && await BookingModel.findOneAndUpdate({
        publicId: booking.publicId, renterId: identity.authId, status: 'pending', paymentStatus: 'unpaid',
      }, { $set: { paymentStatus: 'authorized', paymentAuthorizationId: authorization.publicId },
        $unset: { expiresAt: 1 } });
      if (restored || booking.paymentStatus !== 'unpaid') return existing ?? authorization;
      await paymentAdapter.voidAuthorization({ amount: authorization.amount });
      await paymentRepository.updateStatus(authorization._id, 'voided');
      throw new AppError('This request is no longer payable', 409, 'INVALID_BOOKING_STATE');
    }
    if (existing) return existing;
    if (booking.status !== 'pending' || booking.expiresAt && booking.expiresAt <= new Date() || booking.paymentStatus !== 'unpaid') {
      throw new AppError('Only current unpaid requests can be paid', 409, 'INVALID_BOOKING_STATE');
    }
    const token = new mongoose.Types.ObjectId().toString();
    const claim = await BookingModel.findOneAndUpdate({ ...eligible, paymentStatus: 'unpaid',
      $and: [{ $or: [{ paymentLeaseUntil: { $exists: false } }, { paymentLeaseUntil: { $lte: new Date() } }] }] },
      { $set: { paymentLeaseToken: token, paymentLeaseUntil: new Date(Date.now() + 60_000) } });
    if (!claim) throw new AppError('Check payment status before trying again', 409, 'PAYMENT_IN_PROGRESS');
    try {
      // A recovered/crashed attempt may have persisted while the lease was expiring.
      const recorded = await paymentRepository.findByIdempotencyKey(input.idempotencyKey);
      if (recorded) {
        assertAttemptMatches(recorded, input, identity, outcome);
        return recorded;
      }
      const gateway = await paymentAdapter.authorize({ amount: booking.pricing.total, method: input.method, simulationOutcome: outcome });
      if (!await BookingModel.exists({ ...eligible, paymentLeaseToken: token, paymentLeaseUntil: { $gt: new Date() } })) {
        throw new AppError('The request changed during checkout. Check its status.', 409, 'INVALID_BOOKING_STATE');
      }
      let payment;
      try {
        payment = await paymentRepository.create({
          publicId: transactionId('authorization'), bookingId: booking.publicId, payerId: booking.renterId,
          payeeId: booking.ownerId, type: 'authorization', amount: booking.pricing.total, method: input.method,
          status: gateway.status, gatewayReference: gateway.id, idempotencyKey: input.idempotencyKey,
          ...(gateway.status === 'authorized' && { authorizationSlot: booking.publicId }),
          metadata: { simulationOutcome: outcome }, simulated: true,
        });
      } catch (error) {
        if (error.code !== 11000) throw error;
        const byKey = await paymentRepository.findByIdempotencyKey(input.idempotencyKey);
        assertAttemptMatches(byKey, input, identity, outcome);
        payment = byKey ?? await paymentRepository.findAuthorization(booking.publicId);
        if (!payment) throw error;
      }
      if (payment.status === 'authorized') {
        const updated = await BookingModel.findOneAndUpdate({ ...eligible, paymentLeaseToken: token, paymentStatus: 'unpaid' },
          { $set: { paymentStatus: 'authorized', paymentAuthorizationId: payment.publicId },
            $unset: { expiresAt: 1 } });
        if (!updated) {
          const latest = await BookingModel.findOne({ publicId: booking.publicId });
          if (latest?.paymentAuthorizationId !== payment.publicId || latest.status !== 'pending') {
            await paymentAdapter.voidAuthorization({ amount: payment.amount });
            await paymentRepository.updateStatus(payment._id, 'voided');
            throw new AppError('The request is no longer payable', 409, 'INVALID_BOOKING_STATE');
          }
        }
        await notifyUser({ userId: booking.ownerId, category: 'payment', type: 'payment_authorized',
          title: 'Demo payment ready', body: 'The simulated payment for ' + booking.listingTitle + ' is ready. Owner approval is still required.',
          entityType: 'payment', entityId: payment.publicId });
      }
      return payment;
    } finally {
      await BookingModel.updateOne({ publicId: booking.publicId, paymentLeaseToken: token },
        { $unset: { paymentLeaseToken: 1, paymentLeaseUntil: 1 } });
    }
  },

  async listMine(identity, query) {
    await requireActiveUser(identity);
    const { page, limit } = pages(query);
    const filter = { payerId: identity.authId };
    if (PAYMENT_TYPES.includes(query.type)) filter.type = query.type;
    if (PAYMENT_STATUSES.includes(query.status)) filter.status = query.status;
    const [items, total] = await paymentRepository.list({ page, limit, filter });
    return { items, meta: { page, limit, total } };
  },

  async listBooking(bookingId, identity) {
    const booking = await BookingModel.findOne({ publicId: bookingId });
    const participant =
      booking &&
      (booking.renterId === identity.authId ||
        booking.ownerId === identity.authId ||
        identity.roles.includes('admin'));
    if (!participant) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return paymentRepository.listByBooking(bookingId);
  },

  async listAdmin(query) {
    const { page, limit } = pages(query);
    const filter = {};
    if (query.bookingId) filter.bookingId = query.bookingId;
    if (PAYMENT_TYPES.includes(query.type)) filter.type = query.type;
    if (PAYMENT_STATUSES.includes(query.status)) filter.status = query.status;
    const [items, total] = await paymentRepository.list({ page, limit, filter });
    return { items, meta: { page, limit, total } };
  },

  async refund(id, input) {
    const capture = await paymentRepository.findById(id);
    if (!capture || capture.type !== 'capture' || capture.status !== 'succeeded') {
      throw new AppError('Captured transaction not found', 404, 'NOT_FOUND');
    }
    const idempotencyKey = input.idempotencyKey;
    const existing = await paymentRepository.findByIdempotencyKey(idempotencyKey);
    if (existing) {
      if (
        existing.type !== 'refund' ||
        existing.parentTransactionId !== capture.publicId
      ) {
        throw new AppError(
          'Idempotency key is already in use',
          409,
          'IDEMPOTENCY_CONFLICT',
        );
      }
      return existing;
    }
    const refunded = await paymentRepository.sumRefunds(capture.publicId);
    const refundable = Math.max(capture.amount - refunded, 0);
    const amount = input.amount ?? refundable;
    if (amount <= 0 || amount > refundable) {
      throw new AppError('Refund amount exceeds the refundable balance', 400, 'INVALID_REFUND');
    }
    const gateway = await paymentAdapter.refund({ amount });
    const refund = await paymentRepository.create({
      publicId: transactionId('refund'),
      bookingId: capture.bookingId,
      payerId: capture.payeeId,
      payeeId: capture.payerId,
      type: 'refund',
      amount,
      method: 'system',
      status: gateway.status,
      gatewayReference: gateway.id,
      idempotencyKey,
      parentTransactionId: capture.publicId,
      reason: input.reason,
      simulated: true,
    });
    const booking = await BookingModel.findOne({ publicId: capture.bookingId });
    if (booking) {
      booking.paymentStatus =
        refunded + amount >= capture.amount ? 'refunded' : 'partially_refunded';
      await booking.save();
      await notifyUser({
        userId: booking.renterId,
        category: 'payment',
        type: 'payment_refunded',
        title: 'Refund processed',
        body: `RM ${amount.toFixed(2)} was refunded for ${booking.listingTitle}.`,
        entityType: 'payment',
        entityId: refund.publicId,
      });
    }
    return refund;
  },
};
