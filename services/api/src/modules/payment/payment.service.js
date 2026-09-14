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
    amount: booking.pricing.baseAmount + booking.pricing.damageWaiverFee + deduction,
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

export const paymentService = {
  async authorize(input, identity) {
    await requireActiveUser(identity, 'renter');
    const existing = await paymentRepository.findByIdempotencyKey(
      input.idempotencyKey,
    );
    if (existing) {
      if (existing.bookingId !== input.bookingId || existing.payerId !== identity.authId) {
        throw new AppError(
          'Idempotency key is already in use',
          409,
          'IDEMPOTENCY_CONFLICT',
        );
      }
      return existing;
    }
    const booking = await BookingModel.findOne({
      publicId: input.bookingId,
      renterId: identity.authId,
    });
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    if (booking.status !== 'pending') {
      throw new AppError(
        'Only pending bookings can be authorized',
        409,
        'INVALID_BOOKING_STATE',
      );
    }
    if (booking.paymentStatus !== 'unpaid') {
      const authorization = await paymentRepository.findAuthorization(
        booking.publicId,
      );
      if (authorization) return authorization;
    }
    const gateway = await paymentAdapter.authorize({
      amount: booking.pricing.total,
      method: input.method,
    });
    const payment = await paymentRepository.create({
      publicId: transactionId('authorization'),
      bookingId: booking.publicId,
      payerId: booking.renterId,
      payeeId: booking.ownerId,
      type: 'authorization',
      amount: booking.pricing.total,
      method: input.method,
      status: gateway.status,
      gatewayReference: gateway.id,
      idempotencyKey: input.idempotencyKey,
      simulated: true,
    });
    booking.paymentStatus = 'authorized';
    booking.paymentAuthorizationId = payment.publicId;
    await booking.save();
    await notifyUser({
      userId: booking.ownerId,
      category: 'payment',
      type: 'payment_authorized',
      title: 'Payment authorized',
      body: `RM ${booking.pricing.total.toFixed(2)} is authorized for ${booking.listingTitle}.`,
      entityType: 'payment',
      entityId: payment.publicId,
    });
    return payment;
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
