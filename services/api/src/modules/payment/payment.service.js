import mongoose from 'mongoose';
import { paymentAdapter } from '../../integrations/paymentAdapter.js';
import { AppError } from '../../core/errors.js';
import { BookingModel } from '../booking/booking.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { UserModel } from '../user/user.model.js';
import { PAYMENT_STATUSES, PAYMENT_TYPES } from './payment.model.js';
import { paymentRepository } from './payment.repository.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { PaymentModel } from './payment.model.js';
import { bookingBalance, cents, planAllocations } from './paymentLedger.js';
import { commitLifecycle, recoverListingOperations } from '../../operations/lifecycleJournal.js';

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
  if (await paymentRepository.findCapture(booking.publicId)) return null;
  const authorization = await paymentRepository.findAuthorization(booking.publicId);
  if (!authorization || authorization.status !== 'authorized') return null;
  await paymentAdapter.voidAuthorization({ amount: authorization.amount });
  const voided = await paymentRepository.updateStatus(authorization._id, 'voided');
  booking.paymentStatus = 'voided';
  return voided;
}

export async function prepareVoidBookingPayment(booking) {
  if (await paymentRepository.findCapture(booking.publicId)) return null;
  const authorization = await paymentRepository.findAuthorization(booking.publicId);
  if (!authorization || authorization.status !== 'authorized') return null;
  authorization.status = 'voided';
  booking.paymentStatus = 'voided';
  return authorization;
}

export async function planPhysicalSettlement(booking, deduction) {
  const capture = await paymentRepository.findCapture(booking.publicId);
  if (!capture) {
    throw new AppError('Captured payment not found', 409, 'CAPTURE_MISSING');
  }
  const key = `physical-settlement:${booking._id}`;
  const extensions = await PaymentModel.find({ bookingId: booking.publicId, type: 'capture', status: 'succeeded', 'metadata.extensionId': { $exists: true } });
  const extraCents = extensions.reduce((sum, entry) => sum + cents(entry.amount), 0);
  return planAllocations(booking, key, [
    { type: 'deposit_release', amount: (cents(booking.pricing.securityDeposit) - cents(deduction)) / 100 },
    { type: 'deposit_deduction', amount: deduction, reason: 'Owner-confirmed return deduction (allocation memo, not another payout)' },
    { type: 'owner_settlement', amount: (cents(booking.pricing.baseAmount) + cents(booking.pricing.damageWaiverFee) + cents(booking.pricing.deliveryFee ?? 0) + cents(deduction) + extraCents) / 100 },
  ]);
}

export async function recordPhysicalSettlement(booking, deduction, rental, ensureOwned = async () => {}, preparedEntries) {
  const key = `physical-settlement:${booking._id}`;
  const entries = preparedEntries ?? await planPhysicalSettlement(booking, deduction);
  booking.paymentStatus = 'settled';
  await commitLifecycle(key, booking.listingId, [...entries, ...(rental ? [rental] : []), booking], ensureOwned,
    rental ? { completion: { rentalId: rental.publicId, bookingId: booking.publicId }, notifications: [{
      userId: booking.renterId, category: 'rental', type: 'rental_completed', title: 'Rental completed',
      body: `${booking.listingTitle} return was confirmed.`, entityType: 'rental', entityId: rental.publicId,
      dedupeKey: `rental:${rental.publicId}:completed`,
    }] } : {});
}

export async function recordServiceSettlement(booking, rental, ensureOwned = async () => {}) {
  const capture = await paymentRepository.findCapture(booking.publicId);
  if (!capture) {
    throw new AppError('Captured payment not found', 409, 'CAPTURE_MISSING');
  }
  const key = `service-settlement:${booking._id}`;
  const entries = await planAllocations(booking, key, [
    { type: 'owner_settlement', amount: booking.pricing.baseAmount },
    { type: 'platform_retention', amount: booking.pricing.platformFee },
  ]);
  booking.paymentStatus = 'settled';
  await commitLifecycle(key, booking.listingId, [...entries, ...(rental ? [rental] : []), booking], ensureOwned,
    rental ? { completion: { rentalId: rental.publicId, bookingId: booking.publicId }, notifications: [{
      userId: booking.ownerId, category: 'rental', type: 'service_completed', title: 'Service completion confirmed',
      body: `${booking.listingTitle} was confirmed complete by the renter.`, entityType: 'rental', entityId: rental.publicId,
      dedupeKey: `rental:${rental.publicId}:service-completed`,
    }] } : {});
}

function assertAttemptMatches(existing, input, identity, outcome) {
  if (existing && (existing.type !== 'authorization' || existing.bookingId !== input.bookingId ||
      existing.payerId !== identity.authId || existing.method !== input.method ||
      (existing.metadata?.get('simulationOutcome') ?? 'success') !== outcome)) {
    throw new AppError('Idempotency key is already in use', 409, 'IDEMPOTENCY_CONFLICT');
  }
}

// Covers a process dying after recording an initial authorization while a
// concurrent cancellation/expiry has already made the request non-payable.
export async function voidTerminalPaymentHolds() {
  const candidates = await PaymentModel.aggregate([
    { $match: { type: 'authorization', status: 'authorized', 'metadata.extensionId': { $exists: false } } },
    { $lookup: { from: BookingModel.collection.name, localField: 'bookingId', foreignField: 'publicId', as: 'booking' } },
    { $unwind: '$booking' },
    { $match: { 'booking.status': { $in: ['expired', 'rejected', 'cancelled'] } } },
    { $limit: 100 },
    { $project: { bookingId: 1, listingId: '$booking.listingId' } },
  ]);
  let voided = 0;
  for (const candidate of candidates) {
    await withOperationLock('listing-decision', candidate.listingId, async (ensureOwned) => {
      await recoverListingOperations(candidate.listingId, ensureOwned);
      const booking = await BookingModel.findOne({ publicId: candidate.bookingId, status: { $in: ['expired', 'rejected', 'cancelled'] } });
      if (!booking) return;
      const authorization = await prepareVoidBookingPayment(booking);
      if (!authorization) return;
      await commitLifecycle(`terminal-hold:${authorization._id}`, candidate.listingId, [authorization, booking], ensureOwned);
      voided++;
    });
  }
  return voided;
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
    const filter = { $or: [{ payerId: identity.authId }, { payeeId: identity.authId }] };
    if (PAYMENT_TYPES.includes(query.type)) filter.type = query.type;
    if (PAYMENT_STATUSES.includes(query.status)) filter.status = query.status;
    const [items, total] = await paymentRepository.list({ page, limit, filter });
    return { items, meta: { page, limit, total } };
  },

  async listBooking(bookingId, identity) {
    await requireActiveUser(identity);
    const booking = await BookingModel.findOne({ publicId: bookingId });
    const participant =
      booking &&
      (booking.renterId === identity.authId ||
        booking.ownerId === identity.authId ||
        identity.roles.includes('admin'));
    if (!participant) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return paymentRepository.listByBooking(bookingId);
  },

  async balance(bookingId, identity) {
    await this.listBooking(bookingId, identity);
    const booking = await BookingModel.findOne({ publicId: bookingId });
    return withOperationLock('listing-decision', booking.listingId, async (ensureOwned) => {
      await recoverListingOperations(booking.listingId, ensureOwned);
      return bookingBalance(bookingId);
    });
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
    const context = await BookingModel.findOne({ publicId: capture.bookingId });
    if (!context) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
      await recoverListingOperations(context.listingId, ensureOwned);
      const idempotencyKey = input.idempotencyKey;
      const existing = await paymentRepository.findByIdempotencyKey(idempotencyKey);
      const requestedAmount = input.amount == null ? 'remaining' : String(input.amount);
      if (existing) {
        if (
          existing.type !== 'refund' ||
          existing.parentTransactionId !== capture.publicId ||
          (existing.metadata?.get('requestedAmount') != null
            ? existing.metadata.get('requestedAmount') !== requestedAmount
            : input.amount != null && existing.amount !== input.amount) ||
          existing.reason !== input.reason
        ) {
          throw new AppError(
            'Idempotency key is already in use',
            409,
            'IDEMPOTENCY_CONFLICT',
          );
        }
      }
      const refunded = await paymentRepository.sumRefunds(capture.publicId);
      const balance = await bookingBalance(capture.bookingId);
      const refundableCents = Math.min(Math.max(cents(capture.amount) - cents(refunded), 0), cents(balance.held));
      const amountCents = input.amount == null ? refundableCents : Math.round(input.amount * 100);
      if (!existing && (balance.reconciliationRequired || amountCents <= 0 || amountCents > refundableCents)) {
        throw new AppError('Refund amount exceeds the refundable balance', 400, 'INVALID_REFUND');
      }
      const amount = amountCents / 100;
      let refund = existing;
      if (!refund) {
        await ensureOwned();
        const gateway = await paymentAdapter.refund({ amount });
        await ensureOwned();
        refund = new PaymentModel({
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
          metadata: { requestedAmount },
          simulated: true,
        });
      }
      if (refund.status !== 'succeeded') {
        if (refund.isNew) await refund.save();
        return refund;
      }
      // Reconcile a durable refund whose booking-status update was interrupted.
      const allRefunds = await PaymentModel.find({ bookingId: capture.bookingId, type: 'refund', status: 'succeeded' }).select('amount');
      const totalRefundedCents = allRefunds.reduce((sum, entry) => sum + cents(entry.amount), 0) + (refund.isNew ? cents(refund.amount) : 0);
      await ensureOwned();
      const booking = await BookingModel.findOne({ publicId: capture.bookingId });
      if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
      if (booking) {
        const current = await bookingBalance(capture.bookingId);
        if (refund.isNew) {
          current.distributed = (cents(current.distributed) + cents(refund.amount)) / 100;
          current.held = Math.max(cents(current.captured) - cents(current.distributed), 0) / 100;
        }
        booking.paymentStatus = current.held === 0 ? (current.distributed === totalRefundedCents / 100 ? 'refunded' : 'settled') : 'partially_refunded';
        if (!refund.isNew) await booking.save();
        else await commitLifecycle(`refund:${refund._id}`, booking.listingId, [refund, booking], ensureOwned, {
          notifications: [{ userId: booking.renterId, category: 'payment', type: 'payment_refunded', title: 'Refund processed',
            body: `RM ${refund.amount.toFixed(2)} was refunded for ${booking.listingTitle}.`, entityType: 'payment', entityId: refund.publicId,
            dedupeKey: `refund:${refund.publicId}:processed` }],
        });
      }
      if (booking) {
        await notifyUser({
          userId: booking.renterId,
          category: 'payment',
          type: 'payment_refunded',
          title: 'Refund processed',
          body: `RM ${refund.amount.toFixed(2)} was refunded for ${booking.listingTitle}.`,
          entityType: 'payment',
          entityId: refund.publicId,
          dedupeKey: `refund:${refund.publicId}:processed`,
        });
      }
      return refund;
    });
  },
};
