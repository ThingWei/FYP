import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
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

function money(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
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

function pricing(listing, startDate, endDate, waiverSelected) {
  if (listing.listingType === 'service') {
    const baseAmount = money(listing.dailyPrice);
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
  const baseAmount = money(listing.dailyPrice * rentalDays);
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
    const booking = await bookingRepository.create({
      publicId: publicId(listing.listingType, startDate),
      listingId: listing.publicId,
      listingTitle: listing.title,
      listingType: listing.listingType,
      renterId: renter.authId,
      renterName: renter.displayName,
      ownerId: listing.ownerId,
      startDate,
      endDate,
      fulfilmentMethod: input.fulfilmentMethod,
      serviceVenue: input.serviceVenue,
      damageWaiverSelected: waiverSelected,
      renterNote: input.renterNote ?? '',
      pricing: pricing(listing, startDate, endDate, waiverSelected),
      status: 'pending',
    });
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
    await RentalModel.findOneAndUpdate(
      { bookingId: booking.publicId, status: 'scheduled' },
      { status: 'cancelled' },
    );
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
