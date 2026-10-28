import { createHash } from 'node:crypto';
import mongoose from 'mongoose';
import { bookingLocations, validateLocation } from '../../core/location.js';
import { env } from '../../config/env.js';
import { physicalRentalDate } from '../../core/calendarDate.js';
import { AppError } from '../../core/errors.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { ListingModel } from '../listing/listing.model.js';
import { pricingSnapshot } from '../listing/priceProvenance.js';
import { catalogItemType } from '../catalog/catalog.itemType.js';
import { RentalModel } from '../rental/rental.model.js';
import {
  ensureBookingThread,
  notifyUser,
} from '../communication/notification.service.js';
import { prepareVoidBookingPayment } from '../payment/payment.service.js';
import { UserModel } from '../user/user.model.js';
import { assertDrivingEligibility } from '../user/drivingEligibility.js';
import { PlatformSettingModel } from '../admin/platformSetting.model.js';
import {
  approvedDocumentTypes,
  assertMarketplaceIdentity,
  resolveKycRequirement,
} from '../user/kycRequirements.js';
import { BOOKING_STATUSES } from './booking.model.js';
import { bookingRepository } from './booking.repository.js';
import { agreementTerms } from './agreementTerms.js';
import { presentBooking } from '../../core/location.js';
import { withBookingRequestLock, withOperationLock } from './bookingRequestLock.js';
import { commitLifecycle, recoverListingOperations } from '../../operations/lifecycleJournal.js';

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

function canonicalLocation(value) {
  if (!value) return null;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, key === 'coordinates' ? { latitude: value[key].latitude, longitude: value[key].longitude } : value[key]]));
}
function requestFingerprint(input, dates) {
  const normalized = {
    listingId: input.listingId,
    startDate: dates.startDate.toISOString(),
    endDate: dates.endDate.toISOString(),
    fulfilmentMethod: input.fulfilmentMethod ?? null,
    serviceVenue: input.serviceVenue?.trim() || null,
    serviceLocation: canonicalLocation(input.serviceLocation),
    deliveryLocation: canonicalLocation(input.deliveryLocation),
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
  if (role && !user.roles.includes(role)) {
    throw new AppError(`${role} role is required`, 403, 'FORBIDDEN');
  }
  return user;
}

function bookingDates(listing, input) {
  const startDate = listing.listingType === 'physical'
    ? physicalRentalDate(input.startDate)
    : new Date(input.startDate);
  let endDate = listing.listingType === 'physical'
    ? physicalRentalDate(input.endDate)
    : new Date(input.endDate);
  if (listing.listingType === 'service') {
    endDate = new Date(
      startDate.getTime() + listing.serviceDetails.durationMinutes * 60 * 1000,
    );
  }
  return { startDate, endDate };
}

export async function expireCompetingPhysicalRequests(approvedBooking, ensureOwned = async () => {}) {
  if (approvedBooking.listingType !== 'physical') return [];
  const candidates = await bookingRepository.findCompetingPending({
    listingId: approvedBooking.listingId,
    startDate: approvedBooking.startDate,
    endDate: approvedBooking.endDate,
    excludeId: approvedBooking.publicId,
  });
  const expired = [];
  const expiredAt = new Date();
  const reason =
    'Automatically expired because another overlapping request was approved.';
  for (const candidate of candidates) {
    const claimed = candidate;
    claimed.status = 'expired';
    claimed.expiredAt = expiredAt;
    claimed.cancellationReason = reason;
    const voidedPayment = await prepareVoidBookingPayment(claimed);
    await commitLifecycle(`competing-expiry:${claimed._id}`, claimed.listingId, [...(voidedPayment ? [voidedPayment] : []), claimed], ensureOwned, { notifications: [{
      userId: claimed.renterId,
      category: 'booking',
      type: 'booking_dates_unavailable',
      title: 'Requested dates are no longer available',
      body: `${claimed.listingTitle} was confirmed for another renter on overlapping dates. Your authorization was released.`,
      entityType: 'booking',
      entityId: claimed.publicId,
      dedupeKey: `booking_dates_unavailable:${claimed.publicId}:${claimed.renterId}`,
    }] });
    expired.push(claimed);
  }
  return expired;
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

function pricing(listing, startDate, endDate, waiverSelected, fulfilmentMethod) {
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
  const deliveryFee = fulfilmentMethod === 'owner_delivery' ? money(listing.deliveryFee ?? 0) : 0;
  const damageWaiverFee =
    waiverSelected && listing.damageWaiverAvailable
      ? money(listing.damageWaiverFee)
      : 0;
  return {
    baseAmount,
    originalRentalDays: rentalDays,
    originalDailyRate: money(dailyPrice),
    securityDeposit: money(listing.securityDeposit),
    damageWaiverFee,
    platformFee: 0,
    deliveryFee,
    total: money(baseAmount + listing.securityDeposit + damageWaiverFee + deliveryFee),
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

async function createBooking(input, identity, ensureLockOwned) {
    const renter = await requireActiveUser(identity, 'renter');
    const listing = await ListingModel.findOne({
      publicId: input.listingId,
      status: 'active',
    });
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    const acceptedTerms = agreementTerms(input.agreementVersion);
    if (!acceptedTerms || acceptedTerms.listingType !== 'legacy' && acceptedTerms.listingType !== listing.listingType) {
      throw new AppError('Review the agreement for this booking type', 422, 'AGREEMENT_VERSION_INVALID');
    }
    if (listing.ownerId === renter.authId) {
      throw new AppError('You cannot book your own listing', 400, 'OWN_LISTING');
    }
    if (renter.blockedUserIds.includes(listing.ownerId)) {
      throw new AppError('This Owner is blocked', 409, 'OWNER_BLOCKED');
    }
    const platform =
      (await PlatformSettingModel.findOne({ key: 'platform' })) ??
      await PlatformSettingModel.create({ key: 'platform' });
    const requirement = resolveKycRequirement(platform, listing);
    const { startDate, endDate } = bookingDates(listing, input);
    assertDrivingEligibility(renter, listing, endDate);
    assertMarketplaceIdentity(renter, 'create_booking', listing.category);
    const approvedDocuments = approvedDocumentTypes(renter);
    const missingDocuments = requirement.requiredDocumentTypes.filter(
      (type) => !approvedDocuments.has(type),
    );
    if (missingDocuments.length) {
      throw new AppError(
        'Complete the required identity verification before booking this listing',
        403,
        'KYC_REQUIRED',
        {
          category: listing.category,
          requiredDocumentTypes: requirement.requiredDocumentTypes,
          missingDocumentTypes: missingDocuments,
        },
      );
    }
    const fingerprint = requestFingerprint(input, { startDate, endDate });
    const replay = await findIdempotentBooking(
      renter.authId,
      input.idempotencyKey,
      fingerprint,
    );
    if (replay) {
      if (replay.agreement?.version !== input.agreementVersion) throw new AppError('Agreement changed for this request', 409, 'IDEMPOTENCY_CONFLICT');
      return replay;
    }
    if (listing.listingType === 'physical') {
      const existing = await bookingRepository.findOwnPendingOverlap({
        renterId: renter.authId, listingId: listing.publicId, startDate, endDate,
      });
      if (existing) {
        throw new AppError('You already have a pending request for this item on overlapping dates.',
          409, 'DUPLICATE_PENDING_BOOKING', { bookingId: existing.publicId });
      }
    }
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
    const venueMode = listing.serviceDetails?.venueMode ?? 'flexible';
    const pickup = listing.coordinates && (listing.listingType === 'physical' || venueMode === 'owner_location') ? { ...(listing.locationDetails?.toObject?.() ?? {}), coordinates: listing.coordinates.toObject(), displayAddress: listing.locationDetails?.displayAddress ?? listing.location } : undefined;
    if (listing.listingType === 'physical') {
      if (input.serviceLocation) throw new AppError('Service venue is not applicable', 422, 'VALIDATION_ERROR');
      if (input.fulfilmentMethod === 'owner_delivery' && !input.deliveryLocation) throw new AppError('Confirm a delivery address pin', 422, 'LOCATION_PIN_REQUIRED');
      if (input.fulfilmentMethod !== 'owner_delivery' && input.deliveryLocation) throw new AppError('Delivery address is not applicable', 422, 'VALIDATION_ERROR');
    } else {
      if (input.deliveryLocation) throw new AppError('Delivery address is not applicable', 422, 'VALIDATION_ERROR');
      if (venueMode === 'online') { if (input.serviceLocation) throw new AppError('Online services do not need a map pin', 422, 'VALIDATION_ERROR'); }
      else if (venueMode === 'owner_location') { if (input.serviceLocation) throw new AppError('The service uses the owner location', 422, 'VALIDATION_ERROR'); }
      else if (!input.serviceLocation) throw new AppError('Confirm a service venue pin', 422, 'LOCATION_PIN_REQUIRED');
    }
    if (input.serviceLocation) validateLocation(input.serviceLocation);
    if (input.deliveryLocation) validateLocation(input.deliveryLocation);
    const waiverSelected =
      Boolean(input.damageWaiverSelected) && listing.damageWaiverAvailable;
    const ownerNameSnapshot = (await UserModel.findOne({ authId: listing.ownerId })
      .select('displayName'))?.displayName ?? '';
    let booking;
    await ensureLockOwned();
    try {
      booking = await withOperationLock('listing-decision', listing.publicId, async (ensureListingOwned) => {
        await recoverListingOperations(listing.publicId, ensureListingOwned);
        await assertAvailable(listing, startDate, endDate);
        await ensureLockOwned();
        await ensureListingOwned();
        return bookingRepository.create({
          publicId: publicId(listing.listingType, startDate),
          listingId: listing.publicId,
          listingTitle: listing.title,
          listingType: listing.listingType,
          sourceType: listing.sourceType ?? 'marketplace',
          category: listing.category,
          requiredLicenceClass: listing.requiredLicenceClass,
          renterId: renter.authId,
          renterName: renter.displayName,
          ownerId: listing.ownerId,
          ownerName: ownerNameSnapshot,
          idempotencyKey: input.idempotencyKey,
          idempotencyFingerprint: fingerprint,
          startDate,
          endDate,
          fulfilmentMethod: input.fulfilmentMethod,
          serviceVenueMode: listing.listingType === 'service' ? venueMode : undefined,
          serviceVenue: listing.listingType === 'service' ? venueMode === 'online' ? (input.serviceVenue || 'Online') : venueMode === 'owner_location' ? (pickup?.displayAddress ?? listing.location) : input.serviceLocation.displayAddress : undefined,
          serviceLocation: venueMode === 'online' ? undefined : input.serviceLocation,
          deliveryLocation: input.deliveryLocation,
          pickupLocationSnapshot: pickup,
          damageWaiverSelected: waiverSelected,
          renterNote: input.renterNote ?? '',
          agreement: {
            version: acceptedTerms.version,
            termsHash: acceptedTerms.termsHash,
            acceptedAt: new Date(),
          },
          pricing: pricing(listing, startDate, endDate, waiverSelected, input.fulfilmentMethod),
          ...(listing.listingType === 'physical' && { pricingEvidenceSnapshot: {
            ...pricingSnapshot(listing), productType: await catalogItemType(listing),
          } }),
          status: 'pending',
          expiresAt: new Date(
            Date.now() + env.pendingBookingExpiryMinutes * 60 * 1000,
          ),
        });
      });
    } catch (error) {
      if (error?.code !== 11000) throw error;
      const concurrentReplay = await findIdempotentBooking(
        renter.authId,
        input.idempotencyKey,
        fingerprint,
      );
      if (concurrentReplay) {
        if (concurrentReplay.agreement?.version !== input.agreementVersion) {
          throw new AppError('Idempotency key is already in use', 409, 'IDEMPOTENCY_CONFLICT');
        }
        return concurrentReplay;
      }
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
}

export const bookingService = {
  create(input, identity) {
    return withBookingRequestLock(identity.authId, input.listingId,
      (ensureOwned) => createBooking(input, identity, ensureOwned));
  },

  async locations(id, identity) {
    const booking = await bookingRepository.findParticipantBooking(id, identity);
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return bookingLocations(booking, identity);
  },

  async agreement(id, identity) {
    await requireActiveUser(identity);
    const booking = await bookingService.get(id, identity);
    const saved = agreementTerms(booking.agreement?.version);
    const valid = saved && saved.termsHash === booking.agreement?.termsHash;
    const rental = await RentalModel.findOne({ bookingId: booking.publicId });
    const blockchain = rental?.blockchain;
    const recordStatus = booking.listingType === 'service' ? 'booking_record'
      : !rental ? (booking.status === 'pending' ? 'awaiting_approval' : 'not_created')
      : blockchain?.status === 'confirmed' ? 'saved' : 'unavailable';
    return { booking: presentBooking(booking, identity),
      terms: valid ? { ...saved, title: booking.listingType === 'service' ? 'Service booking agreement' : 'Rental agreement' } : null,
      history: { renterAcceptedAt: booking.agreement?.acceptedAt ?? null,
        ownerApprovedAt: rental ? booking.decidedAt ?? null : null },
      record: { status: recordStatus, demonstrationNetwork: blockchain?.localPrototype === true,
        explanation: booking.listingType === 'physical' ? 'RentHub records rental amounts and status changes to support later review.' : 'RentHub keeps this service booking and its recorded acceptance for review.' } };
  },

  async get(id, identity) {
    const booking = await bookingRepository.findParticipantBooking(id, identity);
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return withOperationLock('listing-decision', booking.listingId, async (ensureOwned) => {
      await recoverListingOperations(booking.listingId, ensureOwned);
      return bookingRepository.findParticipantBooking(id, identity);
    });
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
    const context = await bookingRepository.findById(id);
    if (!context || context.ownerId !== identity.authId || context.renterId === identity.authId) {
      throw new AppError('Booking not found', 404, 'NOT_FOUND');
    }
    return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
      await recoverListingOperations(context.listingId, ensureOwned);
      await requireActiveUser(identity, 'owner');
      // Re-read after acquiring the listing-scoped lock: a competing decision may
      // have expired this pending request while we waited. Pending creation is
      // deliberately not covered by this lock and remains a soft hold.
      const booking = await bookingRepository.findById(id);
      if (!booking || booking.ownerId !== identity.authId || booking.renterId === identity.authId) {
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
      let newRental;
      let voidedPayment;
      if (input.status === 'approved') {
        if (booking.paymentStatus !== 'authorized' && booking.expiresAt && booking.expiresAt <= new Date()) {
          throw new AppError('This request has expired', 409, 'INVALID_BOOKING_STATE');
        }
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
        if (booking.category === 'Vehicles' || listing.category === 'Vehicles') {
          const renter = await UserModel.findOne({ authId: booking.renterId });
          if (!renter) throw new AppError('Renter not found', 404, 'NOT_FOUND');
          assertDrivingEligibility(renter, booking.category === 'Vehicles' ? booking : listing, booking.endDate);
        }
        await assertAvailable(
          listing,
          booking.startDate,
          booking.endDate,
          booking.publicId,
        );
        booking.status = 'approved';
        await ensureOwned();
        const agreement = booking.listingType === 'physical'
          ? await blockchainAdapter.createAgreement({
              rentalAmount: booking.pricing.baseAmount,
              depositAmount: booking.pricing.securityDeposit,
            })
          : undefined;
        await ensureOwned();
        newRental = new RentalModel({
          publicId: rentalId(booking.startDate),
          bookingId: booking.publicId,
          listingId: booking.listingId,
          listingType: booking.listingType,
          category: booking.category ?? listing.category,
          requiredLicenceClass: booking.category ? booking.requiredLicenceClass : listing.requiredLicenceClass,
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
        voidedPayment = await prepareVoidBookingPayment(booking);
      }
      booking.ownerDecisionReason = input.reason?.trim() ?? '';
      booking.decidedAt = new Date();
      await ensureOwned();
      await commitLifecycle(`booking-decision:${booking._id}`, booking.listingId, [...(newRental ? [newRental] : []), ...(voidedPayment ? [voidedPayment] : []), booking], ensureOwned,
        booking.status === 'approved' ? { approvedBooking: booking.publicId } : {});
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
    });
  },

  async cancel(id, reason, identity) {
    await requireActiveUser(identity, 'renter');
    const context = await bookingRepository.findById(id);
    if (!context || context.renterId !== identity.authId) {
      throw new AppError('Booking not found', 404, 'NOT_FOUND');
    }
    return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
      await recoverListingOperations(context.listingId, ensureOwned);
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
      await ensureOwned();
      const voidedPayment = await prepareVoidBookingPayment(booking);
      await ensureOwned();
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
      }
      await commitLifecycle(`booking-cancel:${booking._id}`, booking.listingId, [...(voidedPayment ? [voidedPayment] : []), ...(rental ? [rental] : []), booking], ensureOwned);
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
    });
  },
};
