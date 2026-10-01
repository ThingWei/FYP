import { createHash } from 'node:crypto';
import mongoose from 'mongoose';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { ListingModel } from '../listing/listing.model.js';
import { RentalModel } from '../rental/rental.model.js';
import {
  ensureBookingThread,
  notifyUser,
} from '../communication/notification.service.js';
import { voidBookingPayment } from '../payment/payment.service.js';
import { UserModel } from '../user/user.model.js';
import { BOOKING_STATUSES } from './booking.model.js';
import { bookingRepository } from './booking.repository.js';

const dayMs = 24 * 60 * 60 * 1000;
export const bookingAgreementVersion = 'renthub-booking-v1';
const bookingAgreementTerms = [
  'The item, rental dates, collection method, and charges shown are correct.',
  'The renter will take reasonable care of the item, record its condition, and return it on time.',
  'The Owner may approve or reject the request. Payment follows RentHub cancellation and dispute rules.',
  'After approval, RentHub creates a protected record that supports the rental and any future dispute review.',
].join('\n');
export const bookingAgreementTermsHash = createHash('sha256')
  .update(bookingAgreementTerms)
  .digest('hex');

function money(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function requestFingerprint(input) {
  const normalized = {
    listingId: input.listingId,
    startDate: new Date(input.startDate).toISOString(),
    endDate: new Date(input.endDate).toISOString(),
    fulfilmentMethod: input.fulfilmentMethod ?? null,
    serviceVenue: input.serviceVenue?.trim() || null,
    damageWaiverSelected: Boolean(input.damageWaiverSelected),
    renterNote: input.renterNote?.trim() ?? '',
  };
  return createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
}

async function findIdempotentBooking(renterId, key, fingerprint) {
  const booking = await bookingRepository.findByIdempotencyKey(renterId, key);
  if (!booking) return null;
  if (booking.idempotencyFingerprint !== fingerprint) {
    throw new AppError(
      'Idempotency key is already in use for another booking request',
      409,
      'IDEMPOTENCY_CONFLICT',
    );
  }
  return booking;
}

function publicId(type, start) {
  const prefix = type === 'service' ? 'SVC' : 'BKG';
  const suffix = new mongoose.Types.ObjectId().toString().slice(-8).toUpperCase();
  return `RH-${prefix}-${start.getUTCFullYear()}-${suffix}`;
}

function rentalId(start) {
  const suffix = new mongoose.Types.ObjectId().toString().slice(-8).toUpperCase();
  return `RH-RNT-${start.getUTCFullYear()}-${suffix}`;
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
  if (!user.roles.includes(role)) {
    throw new AppError(`${role} role is required`, 403, 'FORBIDDEN');
  }
  return user;
}

function bookingDates(listing, input) {
  const startDate = new Date(input.startDate);
  let endDate = new Date(input.endDate);
  if (listing.listingType === 'service') {
    endDate = new Date(
      startDate.getTime() + listing.serviceDetails.durationMinutes * 60 * 1000,
    );
  }
  return { startDate, endDate };
}

function effectiveDailyPrice(listing) {
  const promotion = listing.promotion;
  const now = new Date();
  if (
    promotion?.enabled &&
    promotion.startsAt <= now &&
    promotion.endsAt >= now
  ) {
    return money(listing.dailyPrice * (1 - promotion.discountPercent / 100));
  }
  return listing.dailyPrice;
}

function pricing(listing, startDate, endDate, waiverSelected) {
  const dailyPrice = effectiveDailyPrice(listing);
  if (listing.listingType === 'service') {
    const baseAmount = money(dailyPrice);
    const platformFee = money(baseAmount * 0.05);
    return {
      baseAmount,
      securityDeposit: 0,
      damageWaiverFee: 0,
      platformFee,
      total: money(baseAmount + platformFee),
      currency: 'MYR',
    };
  }
  const rentalDays = Math.floor((endDate - startDate) / dayMs) + 1;
  const baseAmount = money(dailyPrice * rentalDays);
  const damageWaiverFee =
    waiverSelected && listing.damageWaiverAvailable
      ? money(listing.damageWaiverFee)
      : 0;
  return {
    baseAmount,
    securityDeposit: money(listing.securityDeposit),
    damageWaiverFee,
    platformFee: 0,
    total: money(baseAmount + listing.securityDeposit + damageWaiverFee),
    currency: 'MYR',
  };
}

async function assertAvailable(listing, startDate, endDate, excludeId) {
  const exclusiveEnd =
    listing.listingType === 'physical'
      ? new Date(endDate.getTime() + dayMs)
      : endDate;
  const [blackout, conflict] = await Promise.all([
    bookingRepository.findBlackout(listing.publicId, startDate, exclusiveEnd),
    bookingRepository.findConflict({
      listingId: listing.publicId,
      startDate,
      endDate,
      excludeId,
    }),
  ]);
  if (blackout || conflict) {
    throw new AppError(
      'The listing is not available for the selected time',
      409,
      'AVAILABILITY_CONFLICT',
    );
  }
}

export const bookingService = {
  async create(input, identity) {
    const renter = await requireActiveUser(identity, 'renter');
    const fingerprint = requestFingerprint(input);
    const replay = await findIdempotentBooking(
      renter.authId,
      input.idempotencyKey,
      fingerprint,
    );
    if (replay) return replay;
    const listing = await ListingModel.findOne({
      publicId: input.listingId,
      status: 'active',
    });
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    if (listing.ownerId === renter.authId) {
      throw new AppError('You cannot book your own listing', 400, 'OWN_LISTING');
    }
    if (renter.blockedUserIds.includes(listing.ownerId)) {
      throw new AppError('This Owner is blocked', 409, 'OWNER_BLOCKED');
    }
    const { startDate, endDate } = bookingDates(listing, input);
    await assertAvailable(listing, startDate, endDate);
    if (
      listing.listingType === 'physical' &&
      !listing.fulfilmentMethods.includes(input.fulfilmentMethod)
    ) {
      throw new AppError(
        'Selected fulfilment method is unavailable',
        400,
        'INVALID_FULFILMENT',
      );
    }
    const waiverSelected =
      Boolean(input.damageWaiverSelected) && listing.damageWaiverAvailable;
    let booking;
    try {
      booking = await bookingRepository.create({
        publicId: publicId(listing.listingType, startDate),
        listingId: listing.publicId,
        listingTitle: listing.title,
        listingType: listing.listingType,
        renterId: renter.authId,
        renterName: renter.displayName,
        ownerId: listing.ownerId,
        idempotencyKey: input.idempotencyKey,
        idempotencyFingerprint: fingerprint,
        startDate,
        endDate,
        fulfilmentMethod: input.fulfilmentMethod,
        serviceVenue: input.serviceVenue,
        damageWaiverSelected: waiverSelected,
        renterNote: input.renterNote ?? '',
        agreement: {
          version: bookingAgreementVersion,
          termsHash: bookingAgreementTermsHash,
          acceptedAt: new Date(),
        },
        pricing: pricing(listing, startDate, endDate, waiverSelected),
        status: 'pending',
        expiresAt: new Date(
          Date.now() + env.pendingBookingExpiryMinutes * 60 * 1000,
        ),
      });
    } catch (error) {
      if (error?.code !== 11000) throw error;
      const concurrentReplay = await findIdempotentBooking(
        renter.authId,
        input.idempotencyKey,
        fingerprint,
      );
      if (concurrentReplay) return concurrentReplay;
      throw error;
    }
    await ensureBookingThread(booking);
    await notifyUser({
      userId: booking.ownerId,
      category: 'booking',
      type: 'booking_created',
      title: 'New booking request',
      body: `${booking.renterName} requested ${booking.listingTitle}.`,
      entityType: 'booking',
      entityId: booking.publicId,
    });
    return booking;
  },

  async get(id, identity) {
    const booking = await bookingRepository.findParticipantBooking(id, identity);
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return booking;
  },

  async listMine(identity, query) {
    await requireActiveUser(identity, 'renter');
    const { page, limit } = pages(query);
    const status = BOOKING_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await bookingRepository.listFor({
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
    const status = BOOKING_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await bookingRepository.listFor({
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
    const status = BOOKING_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await bookingRepository.listAdmin({
      page,
      limit,
      status,
    });
    return { items, meta: { page, limit, total } };
  },

  async decide(id, input, identity) {
    await requireActiveUser(identity, 'owner');
    const booking = await bookingRepository.findById(id);
    if (!booking || booking.ownerId !== identity.authId) {
      throw new AppError('Booking not found', 404, 'NOT_FOUND');
    }
    if (booking.status !== 'pending') {
      throw new AppError(
        'Only pending bookings can be decided',
        409,
        'INVALID_BOOKING_STATE',
      );
    }
    if (input.status === 'rejected' && !input.reason?.trim()) {
      throw new AppError('A rejection reason is required', 400, 'REASON_REQUIRED');
    }
    if (input.status === 'approved') {
      if (booking.paymentStatus !== 'authorized') {
        throw new AppError(
          'Payment authorization is required before approval',
          409,
          'PAYMENT_NOT_AUTHORIZED',
        );
      }
      const listing = await ListingModel.findOne({ publicId: booking.listingId });
      if (!listing || listing.status !== 'active') {
        throw new AppError('Listing is no longer active', 409, 'LISTING_INACTIVE');
      }
      await assertAvailable(
        listing,
        booking.startDate,
        booking.endDate,
        booking.publicId,
      );
      booking.status = 'approved';
      const agreement = booking.listingType === 'physical'
        ? await blockchainAdapter.createAgreement({
            rentalAmount: booking.pricing.baseAmount,
            depositAmount: booking.pricing.securityDeposit,
          })
        : undefined;
      await RentalModel.create({
        publicId: rentalId(booking.startDate),
        bookingId: booking.publicId,
        listingId: booking.listingId,
        listingType: booking.listingType,
        renterId: booking.renterId,
        ownerId: booking.ownerId,
        startDate: booking.startDate,
        endDate: booking.endDate,
        status: 'scheduled',
        ...(agreement && {
          contractAddress: agreement.contractAddress,
          transactionHash: agreement.deploymentTransactionHash,
          blockchain: agreement,
        }),
      });
    } else {
      booking.status = 'rejected';
    }
    booking.ownerDecisionReason = input.reason?.trim() ?? '';
    booking.decidedAt = new Date();
    await booking.save();
    await notifyUser({
      userId: booking.renterId,
      category: 'booking',
      type: `booking_${booking.status}`,
      title:
        booking.status === 'approved'
          ? 'Booking approved'
          : 'Booking request declined',
      body:
        booking.status === 'approved'
          ? `${booking.listingTitle} is confirmed by the Owner.`
          : `${booking.listingTitle} was declined by the Owner.`,
      entityType: 'booking',
      entityId: booking.publicId,
    });
    return booking;
  },

  async cancel(id, reason, identity) {
    await requireActiveUser(identity, 'renter');
    const booking = await bookingRepository.findById(id);
    if (!booking || booking.renterId !== identity.authId) {
      throw new AppError('Booking not found', 404, 'NOT_FOUND');
    }
    if (!['pending', 'approved'].includes(booking.status)) {
      throw new AppError(
        'This booking can no longer be cancelled',
        409,
        'INVALID_BOOKING_STATE',
      );
    }
    booking.status = 'cancelled';
    booking.cancellationReason = reason.trim();
    booking.cancelledAt = new Date();
    await voidBookingPayment(booking);
    await booking.save();
    const rental = await RentalModel.findOne({
      bookingId: booking.publicId,
      status: 'scheduled',
    });
    if (rental) {
      if (rental.listingType === 'physical') {
        const result = await blockchainAdapter.cancel(
          rental.blockchain?.contractAddress || rental.contractAddress,
        );
        rental.blockchain = { ...rental.blockchain?.toObject?.(), ...result };
        rental.transactionHash = result.lastTransactionHash ?? rental.transactionHash;
      }
      rental.status = 'cancelled';
      await rental.save();
    }
    await notifyUser({
      userId: booking.ownerId,
      category: 'booking',
      type: 'booking_cancelled',
      title: 'Booking cancelled',
      body: `${booking.renterName} cancelled ${booking.listingTitle}.`,
      entityType: 'booking',
      entityId: booking.publicId,
    });
    return booking;
  },
};
