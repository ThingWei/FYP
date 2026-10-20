import { AppError } from '../../core/errors.js';
import { physicalRentalDate } from '../../core/calendarDate.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { BookingModel } from '../booking/booking.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { AvailabilityModel } from '../listing/availability.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { uploadService } from '../upload/upload.service.js';
import {
  captureBookingPayment,
  recordPhysicalSettlement,
  planPhysicalSettlement,
  recordServiceSettlement,
} from '../payment/payment.service.js';
import { UserModel } from '../user/user.model.js';
import { assertDrivingEligibility } from '../user/drivingEligibility.js';
import { RENTAL_STATUSES } from './rental.model.js';
import { rentalRepository } from './rental.repository.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { blockingBookingCriteria } from '../listing/availabilityRules.js';
import { randomUUID } from 'node:crypto';
import { PaymentModel } from '../payment/payment.model.js';
import { cents, ledgerEntry } from '../payment/paymentLedger.js';
import { commitLifecycle, recoverListingOperations } from '../../operations/lifecycleJournal.js';

const dayMs = 24 * 60 * 60 * 1000;

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
  if (!user.roles.includes(role)) {
    throw new AppError(`${role} role is required`, 403, 'FORBIDDEN');
  }
  return user;
}

async function assertVehicleCredential(rental, endDate) {
  const listing = rental.category ? rental : await ListingModel.findOne({ publicId: rental.listingId });
  if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
  if (listing.category !== 'Vehicles') return;
  const renter = await UserModel.findOne({ authId: rental.renterId });
  if (!renter) throw new AppError('Renter not found', 404, 'NOT_FOUND');
  assertDrivingEligibility(renter, listing, endDate);
}

async function ownedRental(id, identity, role) {
  await requireActiveUser(identity, role);
  const rental = await rentalRepository.findById(id);
  const field = role === 'owner' ? 'ownerId' : 'renterId';
  if (!rental || rental[field] !== identity.authId) {
    throw new AppError('Rental not found', 404, 'NOT_FOUND');
  }
  return rental;
}

async function linkedBooking(rental) {
  const booking = await BookingModel.findOne({ publicId: rental.bookingId });
  if (!booking) throw new AppError('Linked booking not found', 409, 'BOOKING_MISSING');
  return booking;
}

async function mutateRental(id, identity, role, operation) {
  const context = await ownedRental(id, identity, role);
  return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
    await recoverListingOperations(context.listingId, ensureOwned);
    // Re-read state and ownership after waiting for another lifecycle action.
    const rental = await ownedRental(id, identity, role);
    await ensureOwned();
    return operation(rental, ensureOwned);
  });
}

async function assertExtensionAvailable(rental, requestedEndDate) {
  const extensionStart = new Date(rental.endDate.getTime() + dayMs);
  const exclusiveEnd = new Date(requestedEndDate.getTime() + dayMs);
  const [blackout, conflict] = await Promise.all([
    AvailabilityModel.findOne({
      listingId: rental.listingId,
      unavailableRanges: {
        $elemMatch: {
          start: { $lt: exclusiveEnd },
          end: { $gt: extensionStart },
        },
      },
    }).lean(),
    BookingModel.findOne({
      listingId: rental.listingId,
      publicId: { $ne: rental.bookingId },
      ...blockingBookingCriteria(),
      startDate: { $lte: requestedEndDate },
      endDate: { $gte: extensionStart },
    }).lean(),
  ]);
  if (blackout || conflict) {
    throw new AppError(
      'The listing is unavailable for the requested extension',
      409,
      'AVAILABILITY_CONFLICT',
    );
  }
}

function complete(rental, booking) {
  rental.status = 'completed';
  booking.status = 'completed';
  booking.completedAt = new Date();
  return rental;
}

async function voidExtension(rental) {
  if (rental.extension?.paymentStatus === 'authorized') {
    await PaymentModel.updateOne({ publicId: rental.extension.authorizationId, status: 'authorized' }, { $set: { status: 'voided' } });
    rental.extension.paymentStatus = 'voided';
  }
  if (rental.extension?.status === 'pending') {
    rental.extension.status = 'rejected';
    rental.extension.ownerReason = 'Closed because the rental changed or the quote expired.';
    rental.extension.decidedAt = new Date();
  }
}

export async function expireRentalExtensions(now = new Date()) {
  const pending = await rentalRepository.listExpiredExtensions(now);
  let expired = 0;
  for (const context of pending) {
    await withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
      await recoverListingOperations(context.listingId, ensureOwned);
      const rental = await rentalRepository.findById(context.publicId);
      if (rental?.extension.status !== 'pending' || !rental.extension.expiresAt || rental.extension.expiresAt > now) return;
      await voidExtension(rental);
      await ensureOwned();
      await rental.save();
      expired++;
    });
  }
  return expired;
}

export const rentalService = {
  async get(id, identity) {
    const rental = await rentalRepository.findParticipantRental(id, identity);
    if (!rental) throw new AppError('Rental not found', 404, 'NOT_FOUND');
    return withOperationLock('listing-decision', rental.listingId, async (ensureOwned) => {
      await recoverListingOperations(rental.listingId, ensureOwned);
      return rentalRepository.findParticipantRental(id, identity);
    });
  },

  async listMine(identity, query) {
    await requireActiveUser(identity, 'renter');
    const { page, limit } = pages(query);
    const status = RENTAL_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await rentalRepository.listFor({
      field: 'renterId',
      identityId: identity.authId,
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async listOwner(identity, query) {
    await requireActiveUser(identity, 'owner');
    const { page, limit } = pages(query);
    const status = RENTAL_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await rentalRepository.listFor({
      field: 'ownerId',
      identityId: identity.authId,
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async listAdmin(query) {
    const { page, limit } = pages(query);
    const status = RENTAL_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await rentalRepository.listAdmin({
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async confirmHandover(id, input, identity) {
    return mutateRental(id, identity, 'owner', async (rental, ensureOwned) => {
      await uploadService.assertOwnedReferences(identity, input.evidence, ['handover_evidence']);
      if (rental.listingType !== 'physical' || rental.status !== 'scheduled') {
        throw new AppError('Handover is unavailable', 409, 'INVALID_RENTAL_STATE');
      }
      await assertVehicleCredential(rental, rental.endDate);
      rental.handover = {
        condition: input.condition,
        notes: input.notes ?? '',
        evidence: input.evidence,
        recordedAt: new Date(),
      };
      rental.status = 'active';
      const booking = await linkedBooking(rental);
      await captureBookingPayment(booking);
      await ensureOwned();
      booking.status = 'active';
      booking.activatedAt = new Date();
      await commitLifecycle(`handover:${rental._id}`, rental.listingId, [rental, booking], ensureOwned);
      await notifyUser({
        userId: rental.renterId,
        category: 'rental',
        type: 'rental_handover',
        title: 'Rental handover confirmed',
        body: `${booking.listingTitle} is now an active rental.`,
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async startService(id, identity) {
    return mutateRental(id, identity, 'owner', async (rental, ensureOwned) => {
      if (rental.listingType !== 'service' || rental.status !== 'scheduled') {
        throw new AppError('Service cannot be started', 409, 'INVALID_RENTAL_STATE');
      }
      rental.status = 'active';
      const booking = await linkedBooking(rental);
      await captureBookingPayment(booking);
      await ensureOwned();
      booking.status = 'active';
      booking.activatedAt = new Date();
      await commitLifecycle(`service-start:${rental._id}`, rental.listingId, [rental, booking], ensureOwned);
      await notifyUser({
        userId: rental.renterId,
        category: 'rental',
        type: 'service_started',
        title: 'Service started',
        body: `${booking.listingTitle} is now in progress.`,
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async requestExtension(id, input, identity) {
    return mutateRental(id, identity, 'renter', async (rental) => {
      if (
        rental.listingType !== 'physical' ||
        !['active', 'overdue'].includes(rental.status)
      ) {
        throw new AppError('Extension is unavailable', 409, 'INVALID_RENTAL_STATE');
      }
      if (rental.extension.status === 'pending' && rental.extension.id &&
          (rental.extension.paymentStatus === 'authorized' || rental.extension.expiresAt > new Date())) {
        throw new AppError('An extension is already pending', 409, 'EXTENSION_PENDING');
      }
      const requestedEndDate = physicalRentalDate(input.requestedEndDate);
      if (requestedEndDate <= rental.endDate) {
        throw new AppError(
          'The requested end date must be later',
          400,
          'INVALID_EXTENSION_DATE',
        );
      }
      await assertExtensionAvailable(rental, requestedEndDate);
      await assertVehicleCredential(rental, requestedEndDate);
      const booking = await linkedBooking(rental);
      if (booking.pricing.originalDailyRate == null) {
        // Legacy end dates may already include an unpriced extension. Dividing
        // the old total by today's dates could invent an incorrect booked rate.
        throw new AppError('The original rate is unavailable for this older rental. Contact support.', 409, 'EXTENSION_RATE_UNAVAILABLE');
      }
      if (rental.extension.status !== 'none') {
        await voidExtension(rental);
        rental.extensionHistory = [...rental.extensionHistory.map((entry) => entry.toObject()), rental.extension.toObject()];
        rental.markModified('extensionHistory');
      }
      const extraDays = Math.round((requestedEndDate - rental.endDate) / dayMs);
      if (extraDays > 365) throw new AppError('An extension may add at most 365 days', 400, 'INVALID_EXTENSION_DATE');
      rental.extension = {
        id: `EXT-${randomUUID()}`,
        previousEndDate: rental.endDate,
        extraDays,
        dailyRate: booking.pricing.originalDailyRate,
        amount: cents(booking.pricing.originalDailyRate * extraDays) / 100,
        paymentStatus: 'unpaid',
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
        requestedEndDate,
        reason: input.reason,
        status: 'pending',
        requestedAt: new Date(),
      };
      await rental.save();
      await notifyUser({
        userId: rental.ownerId,
        category: 'rental',
        type: 'extension_requested',
        title: 'Extension requested',
        body: 'The renter submitted a new rental extension request.',
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async payExtension(id, input, identity) {
    return mutateRental(id, identity, 'renter', async (rental, ensureOwned) => {
      const extension = rental.extension;
      if (!extension.id || extension.id !== input.extensionId) throw new AppError('The extension changed. Review it again.', 409, 'EXTENSION_CHANGED');
      const existing = await PaymentModel.findOne({ idempotencyKey: input.idempotencyKey });
      if (existing && (existing.metadata?.get('extensionId') !== extension.id || existing.payerId !== identity.authId || existing.method !== input.method || existing.metadata?.get('simulationOutcome') !== input.simulationOutcome)) {
        throw new AppError('Idempotency key is already in use', 409, 'IDEMPOTENCY_CONFLICT');
      }
      if (existing) return rental;
      if (rental.listingType !== 'physical' || !['active', 'overdue'].includes(rental.status) || extension.status !== 'pending' || !extension.expiresAt || extension.expiresAt <= new Date()) {
        throw new AppError('This extension is no longer payable. Request a new quote.', 409, 'INVALID_EXTENSION_STATE');
      }
      if (extension.paymentStatus === 'authorized') return rental;
      await assertExtensionAvailable(rental, extension.requestedEndDate);
      await assertVehicleCredential(rental, extension.requestedEndDate);
      const booking = await linkedBooking(rental);
      const payment = ledgerEntry(booking, 'authorization', extension.amount, input.idempotencyKey, {
        payerId: rental.renterId, payeeId: rental.ownerId, method: input.method,
        status: input.simulationOutcome === 'declined' ? 'failed' : 'authorized',
        metadata: { extensionId: extension.id, simulationOutcome: input.simulationOutcome },
      });
      if (payment.status === 'authorized') {
        extension.paymentStatus = 'authorized';
        extension.authorizationId = payment.publicId;
        extension.expiresAt = undefined;
      }
      await commitLifecycle(`extension-pay:${payment._id}`, rental.listingId, [payment, rental], ensureOwned);
      return rental;
    });
  },

  async decideExtension(id, input, identity) {
    return mutateRental(id, identity, 'owner', async (rental, ensureOwned) => {
      if (rental.listingType !== 'physical' || !['active', 'overdue'].includes(rental.status)) {
        throw new AppError('Extension decision is unavailable', 409, 'INVALID_RENTAL_STATE');
      }
      if (rental.extension.status !== 'pending') {
        throw new AppError('No extension is pending', 409, 'INVALID_RENTAL_STATE');
      }
      if (rental.extension.id && input.extensionId !== rental.extension.id) throw new AppError('The extension changed. Review the current request.', 409, 'EXTENSION_CHANGED');
      if (input.status === 'rejected' && !input.reason?.trim()) {
        throw new AppError('A rejection reason is required', 400, 'REASON_REQUIRED');
      }
      if (input.status === 'approved') {
        if (!rental.extension.id || rental.extension.paymentStatus !== 'authorized' || rental.extension.expiresAt && rental.extension.expiresAt <= new Date()) {
          throw new AppError('The renter must pay a current extension quote before approval.', 409, 'EXTENSION_PAYMENT_REQUIRED');
        }
        await assertExtensionAvailable(rental, rental.extension.requestedEndDate);
        await assertVehicleCredential(rental, rental.extension.requestedEndDate);
        rental.endDate = rental.extension.requestedEndDate;
        const booking = await linkedBooking(rental);
        booking.endDate = rental.endDate;
        const authorization = await PaymentModel.findOne({ publicId: rental.extension.authorizationId, status: 'authorized' });
        if (!authorization || cents(authorization.amount) !== cents(rental.extension.amount)) throw new AppError('Extension payment is unavailable', 409, 'EXTENSION_PAYMENT_REQUIRED');
        const capture = ledgerEntry(booking, 'capture', rental.extension.amount, `extension-capture:${rental.extension.id}`, {
          parentTransactionId: authorization.publicId, metadata: { extensionId: rental.extension.id },
        });
        rental.extension.paymentStatus = 'captured';
        rental.extension.status = 'approved';
        rental.extension.ownerReason = input.reason?.trim() ?? '';
        rental.extension.decidedAt = new Date();
        booking.extensionCharges = [...booking.extensionCharges.map((entry) => entry.toObject()), {
          id: rental.extension.id, extraDays: rental.extension.extraDays, dailyRate: rental.extension.dailyRate,
          amount: rental.extension.amount, requestedEndDate: rental.extension.requestedEndDate,
          decidedAt: rental.extension.decidedAt, paymentStatus: 'captured',
        }];
        booking.markModified('extensionCharges');
        if (rental.status === 'overdue' && rental.endDate > new Date()) {
          rental.status = 'active';
        }
        await commitLifecycle(`extension-approve:${rental.extension.id}`, rental.listingId, [capture, rental, booking], ensureOwned);
        await notifyUser({ userId: rental.renterId, category: 'rental', type: 'extension_approved', title: 'Extension approved',
          body: 'Your extra rental days are approved and the demo payment is captured.', entityType: 'rental', entityId: rental.publicId,
          dedupeKey: `extension:${rental.extension.id}:approved` });
        return rental;
      }
      await voidExtension(rental);
      rental.extension.status = input.status;
      rental.extension.ownerReason = input.reason?.trim() ?? '';
      rental.extension.decidedAt = new Date();
      await rental.save();
      await notifyUser({
        userId: rental.renterId,
        category: 'rental',
        type: `extension_${input.status}`,
        title:
          input.status === 'approved'
            ? 'Extension approved'
            : 'Extension declined',
        body: `Your rental extension was ${input.status}.`,
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async submitReturn(id, input, identity) {
    return mutateRental(id, identity, 'renter', async (rental) => {
      await uploadService.assertOwnedReferences(identity, input.evidence, ['return_evidence']);
      if (
        rental.listingType !== 'physical' ||
        !['active', 'overdue'].includes(rental.status)
      ) {
        throw new AppError('Return cannot be submitted', 409, 'INVALID_RENTAL_STATE');
      }
      rental.returnSubmission = {
        condition: input.condition,
        notes: input.notes ?? '',
        evidence: input.evidence,
        recordedAt: new Date(),
      };
      await voidExtension(rental);
      rental.status = 'return_submitted';
      await rental.save();
      await notifyUser({
        userId: rental.ownerId,
        category: 'rental',
        type: 'return_submitted',
        title: 'Return submitted',
        body: 'The renter submitted return condition evidence.',
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async confirmReturn(id, input, identity) {
    return mutateRental(id, identity, 'owner', async (rental, ensureOwned) => {
      if (rental.listingType !== 'physical' || rental.status !== 'return_submitted') {
        throw new AppError('Return cannot be confirmed', 409, 'INVALID_RENTAL_STATE');
      }
      const booking = await linkedBooking(rental);
      if (input.depositDeduction > booking.pricing.securityDeposit) {
        throw new AppError(
          'Deposit deduction exceeds the security deposit',
          400,
          'INVALID_DEDUCTION',
        );
      }
      rental.returnOutcome = {
        condition: input.condition,
        notes: input.notes ?? '',
        depositDeduction: input.depositDeduction,
        confirmedAt: new Date(),
      };
      const settlementEntries = await planPhysicalSettlement(booking, input.depositDeduction);
      const chainResult = await blockchainAdapter.complete(
        rental.blockchain?.contractAddress || rental.contractAddress,
        input.depositDeduction,
      );
      rental.blockchain = { ...rental.blockchain?.toObject?.(), ...chainResult };
      rental.transactionHash = chainResult.lastTransactionHash ?? rental.transactionHash;
      await ensureOwned();
      const completedRental = complete(rental, booking);
      await recordPhysicalSettlement(booking, input.depositDeduction, rental, ensureOwned, settlementEntries);
      return completedRental;
    });
  },

  async markServiceDelivered(id, identity) {
    return mutateRental(id, identity, 'owner', async (rental) => {
      if (rental.listingType !== 'service' || rental.status !== 'active') {
        throw new AppError('Service delivery cannot be marked', 409, 'INVALID_RENTAL_STATE');
      }
      rental.status = 'completion_pending';
      rental.serviceDeliveredAt = new Date();
      await rental.save();
      await notifyUser({
        userId: rental.renterId,
        category: 'rental',
        type: 'service_delivered',
        title: 'Service marked complete',
        body: 'The Owner marked the service as delivered. Please confirm completion.',
        entityType: 'rental',
        entityId: rental.publicId,
      });
      return rental;
    });
  },

  async confirmServiceCompletion(id, identity) {
    return mutateRental(id, identity, 'renter', async (rental, ensureOwned) => {
      if (rental.listingType !== 'service' || rental.status !== 'completion_pending') {
        throw new AppError('Service cannot be completed', 409, 'INVALID_RENTAL_STATE');
      }
      rental.serviceCompletedAt = new Date();
      const booking = await linkedBooking(rental);
      const completedRental = complete(rental, booking);
      await recordServiceSettlement(booking, rental, ensureOwned);
      return completedRental;
    });
  },
};
