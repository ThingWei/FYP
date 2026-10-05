import { AppError } from '../../core/errors.js';
import { physicalRentalDate } from '../../core/calendarDate.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { BookingModel } from '../booking/booking.model.js';
import { AvailabilityModel } from '../listing/availability.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { uploadService } from '../upload/upload.service.js';
import {
  captureBookingPayment,
  recordPhysicalSettlement,
  recordServiceSettlement,
} from '../payment/payment.service.js';
import { UserModel } from '../user/user.model.js';
import { awardRentalCompletion } from '../loyalty/loyalty.service.js';
import { RENTAL_STATUSES } from './rental.model.js';
import { rentalRepository } from './rental.repository.js';

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
      status: { $in: ['approved', 'active'] },
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

async function complete(rental, booking) {
  rental.status = 'completed';
  booking.status = 'completed';
  booking.completedAt = new Date();
  await Promise.all([rental.save(), booking.save()]);
  return rental;
}

async function runPostCompletionTasks(tasks, rentalId) {
  const results = await Promise.allSettled(tasks);
  for (const result of results) {
    if (result.status === 'rejected') {
      console.error('Post-completion task failed', {
        rentalId,
        message: result.reason?.message,
      });
    }
  }
}

export const rentalService = {
  async get(id, identity) {
    const rental = await rentalRepository.findParticipantRental(id, identity);
    if (!rental) throw new AppError('Rental not found', 404, 'NOT_FOUND');
    return rental;
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
    const rental = await ownedRental(id, identity, 'owner');
    await uploadService.assertOwnedReferences(identity, input.evidence, ['handover_evidence']);
    if (rental.listingType !== 'physical' || rental.status !== 'scheduled') {
      throw new AppError('Handover is unavailable', 409, 'INVALID_RENTAL_STATE');
    }
    rental.handover = {
      condition: input.condition,
      notes: input.notes ?? '',
      evidence: input.evidence,
      recordedAt: new Date(),
    };
    rental.status = 'active';
    const booking = await linkedBooking(rental);
    await captureBookingPayment(booking);
    booking.status = 'active';
    booking.activatedAt = new Date();
    await Promise.all([rental.save(), booking.save()]);
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
  },

  async startService(id, identity) {
    const rental = await ownedRental(id, identity, 'owner');
    if (rental.listingType !== 'service' || rental.status !== 'scheduled') {
      throw new AppError('Service cannot be started', 409, 'INVALID_RENTAL_STATE');
    }
    rental.status = 'active';
    const booking = await linkedBooking(rental);
    await captureBookingPayment(booking);
    booking.status = 'active';
    booking.activatedAt = new Date();
    await Promise.all([rental.save(), booking.save()]);
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
  },

  async requestExtension(id, input, identity) {
    const rental = await ownedRental(id, identity, 'renter');
    if (
      rental.listingType !== 'physical' ||
      !['active', 'overdue'].includes(rental.status)
    ) {
      throw new AppError('Extension is unavailable', 409, 'INVALID_RENTAL_STATE');
    }
    if (rental.extension.status === 'pending') {
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
    rental.extension = {
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
  },

  async decideExtension(id, input, identity) {
    const rental = await ownedRental(id, identity, 'owner');
    if (rental.extension.status !== 'pending') {
      throw new AppError('No extension is pending', 409, 'INVALID_RENTAL_STATE');
    }
    if (input.status === 'rejected' && !input.reason?.trim()) {
      throw new AppError('A rejection reason is required', 400, 'REASON_REQUIRED');
    }
    if (input.status === 'approved') {
      await assertExtensionAvailable(rental, rental.extension.requestedEndDate);
      rental.endDate = rental.extension.requestedEndDate;
      const booking = await linkedBooking(rental);
      booking.endDate = rental.endDate;
      await booking.save();
      if (rental.status === 'overdue' && rental.endDate > new Date()) {
        rental.status = 'active';
      }
    }
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
  },

  async submitReturn(id, input, identity) {
    const rental = await ownedRental(id, identity, 'renter');
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
  },

  async confirmReturn(id, input, identity) {
    const rental = await ownedRental(id, identity, 'owner');
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
    const chainResult = await blockchainAdapter.complete(
      rental.blockchain?.contractAddress || rental.contractAddress,
      input.depositDeduction,
    );
    rental.blockchain = { ...rental.blockchain?.toObject?.(), ...chainResult };
    rental.transactionHash = chainResult.lastTransactionHash ?? rental.transactionHash;
    await recordPhysicalSettlement(booking, input.depositDeduction);
    const completedRental = await complete(rental, booking);
    await runPostCompletionTasks(
      [
        notifyUser({
          userId: rental.renterId,
          category: 'rental',
          type: 'rental_completed',
          title: 'Rental completed',
          body: `${booking.listingTitle} return was confirmed.`,
          entityType: 'rental',
          entityId: rental.publicId,
          dedupeKey: `rental:${rental.publicId}:completed`,
        }),
        awardRentalCompletion(completedRental, booking),
      ],
      rental.publicId,
    );
    return completedRental;
  },

  async markServiceDelivered(id, identity) {
    const rental = await ownedRental(id, identity, 'owner');
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
  },

  async confirmServiceCompletion(id, identity) {
    const rental = await ownedRental(id, identity, 'renter');
    if (rental.listingType !== 'service' || rental.status !== 'completion_pending') {
      throw new AppError('Service cannot be completed', 409, 'INVALID_RENTAL_STATE');
    }
    rental.serviceCompletedAt = new Date();
    const booking = await linkedBooking(rental);
    await recordServiceSettlement(booking);
    const completedRental = await complete(rental, booking);
    await runPostCompletionTasks(
      [
        notifyUser({
          userId: rental.ownerId,
          category: 'rental',
          type: 'service_completed',
          title: 'Service completion confirmed',
          body: `${booking.listingTitle} was confirmed complete by the renter.`,
          entityType: 'rental',
          entityId: rental.publicId,
          dedupeKey: `rental:${rental.publicId}:service-completed`,
        }),
        awardRentalCompletion(completedRental, booking),
      ],
      rental.publicId,
    );
    return completedRental;
  },
};
