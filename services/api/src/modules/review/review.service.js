import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { BookingModel } from '../booking/booking.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { RentalModel } from '../rental/rental.model.js';
import { UserModel } from '../user/user.model.js';
import { REVIEW_STATUSES } from './review.model.js';
import { reviewRepository } from './review.repository.js';

const editWindowMs = 24 * 60 * 60 * 1000;

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

function reviewId() {
  return `RH-REV-${new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase()}`;
}

async function activeUser(identity) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  return user;
}

function withEditState(review, identity) {
  const value = review.toJSON ? review.toJSON() : review;
  value.canEdit =
    value.authorId === identity?.authId &&
    Date.now() - new Date(value.createdAt).getTime() <= editWindowMs;
  value.editableUntil = new Date(
    new Date(value.createdAt).getTime() + editWindowMs,
  );
  return value;
}

export const reviewService = {
  async create(input, identity) {
    const author = await activeUser(identity);
    const rental = await RentalModel.findOne({ publicId: input.rentalId });
    if (!rental) throw new AppError('Rental not found', 404, 'NOT_FOUND');
    if (rental.status !== 'completed') {
      throw new AppError(
        'Reviews are available only after completion',
        409,
        'REVIEW_NOT_AVAILABLE',
      );
    }
    const authorRole =
      rental.renterId === identity.authId
        ? 'renter'
        : rental.ownerId === identity.authId
          ? 'owner'
          : null;
    if (!authorRole) throw new AppError('Rental not found', 404, 'NOT_FOUND');
    if (await reviewRepository.findByRentalAndAuthor(rental.publicId, identity.authId)) {
      throw new AppError(
        'You already reviewed this rental',
        409,
        'REVIEW_ALREADY_EXISTS',
      );
    }
    const booking = await BookingModel.findOne({ publicId: rental.bookingId });
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    const subjectId = authorRole === 'renter' ? rental.ownerId : rental.renterId;
    const subject = await UserModel.findOne({ authId: subjectId });
    if (!subject) throw new AppError('Review subject not found', 404, 'NOT_FOUND');
    const review = await reviewRepository.create({
      publicId: reviewId(),
      rentalId: rental.publicId,
      bookingId: rental.bookingId,
      listingId: rental.listingId,
      listingTitle: booking.listingTitle,
      listingType: rental.listingType,
      authorId: identity.authId,
      authorName: author.displayName,
      authorRole,
      subjectId,
      subjectName: subject.displayName,
      subjectRole: authorRole === 'renter' ? 'owner' : 'renter',
      overallRating: input.overallRating,
      conditionRating: input.conditionRating,
      communicationRating: input.communicationRating,
      valueRating: input.valueRating,
      text: input.text,
    });
    await notifyUser({
      userId: subjectId,
      category: 'review',
      type: 'review_received',
      title: 'New review received',
      body: `${author.displayName} left a ${review.overallRating}-star review.`,
      entityType: 'review',
      entityId: review.publicId,
    });
    return withEditState(review, identity);
  },

  async edit(id, input, identity) {
    const review = await reviewRepository.findById(id);
    if (!review || review.authorId !== identity.authId) {
      throw new AppError('Review not found', 404, 'NOT_FOUND');
    }
    if (Date.now() - review.createdAt.getTime() > editWindowMs) {
      throw new AppError(
        'The 24-hour review editing window has ended',
        409,
        'EDIT_WINDOW_ENDED',
      );
    }
    review.set({
      overallRating: input.overallRating,
      conditionRating: input.conditionRating,
      communicationRating: input.communicationRating,
      valueRating: input.valueRating,
      text: input.text,
      editedAt: new Date(),
    });
    await review.save();
    return withEditState(review, identity);
  },

  async listListing(listingId, query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await reviewRepository.listForListing({
      listingId,
      page,
      limit,
    });
    return { items, meta: { page, limit, total } };
  },

  async listMine(identity, query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await reviewRepository.listForUser({
      field: 'authorId',
      userId: identity.authId,
      page,
      limit,
    });
    return {
      items: items.map((item) => withEditState(item, identity)),
      meta: { page, limit, total },
    };
  },

  async listReceived(identity, query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await reviewRepository.listForUser({
      field: 'subjectId',
      userId: identity.authId,
      page,
      limit,
    });
    return { items, meta: { page, limit, total } };
  },

  async flag(id, input, identity) {
    const review = await reviewRepository.findById(id);
    if (!review || review.subjectId !== identity.authId) {
      throw new AppError('Review not found', 404, 'NOT_FOUND');
    }
    review.flag = {
      reason: input.reason,
      flaggedBy: identity.authId,
      flaggedAt: new Date(),
    };
    await review.save();
    return review;
  },

  async listAdmin(query) {
    const { page, limit } = pageOptions(query);
    const status = REVIEW_STATUSES.includes(query.status) ? query.status : undefined;
    const [items, total] = await reviewRepository.listAdmin({
      page,
      limit,
      status,
      flagged: query.flagged === 'true',
    });
    return { items, meta: { page, limit, total } };
  },

  async moderate(id, input, identity) {
    const review = await reviewRepository.findById(id);
    if (!review) throw new AppError('Review not found', 404, 'NOT_FOUND');
    if (input.status === 'hidden' && !input.reason?.trim()) {
      throw new AppError('A moderation reason is required', 400, 'REASON_REQUIRED');
    }
    review.status = input.status;
    review.moderation = {
      reason: input.reason ?? '',
      moderatedBy: identity.authId,
      moderatedAt: new Date(),
    };
    await review.save();
    await notifyUser({
      userId: review.authorId,
      category: 'review',
      type: 'review_moderated',
      title: input.status === 'hidden' ? 'Review hidden' : 'Review restored',
      body: input.reason || 'An administrator updated your review.',
      entityType: 'review',
      entityId: review.publicId,
    });
    return review;
  },

  async summary(subjectId) {
    const [summary] = await reviewRepository.summary(subjectId);
    return {
      subjectId,
      averageRating: summary ? Math.round(summary.averageRating * 10) / 10 : 0,
      reviewCount: summary?.reviewCount ?? 0,
    };
  },
};
