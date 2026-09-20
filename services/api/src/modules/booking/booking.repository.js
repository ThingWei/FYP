import mongoose from 'mongoose';
import { AvailabilityModel } from '../listing/availability.model.js';
import { BookingModel } from './booking.model.js';

function identifiers(id) {
  const values = [{ publicId: id }];
  if (mongoose.isValidObjectId(id)) values.push({ _id: id });
  return values;
}

export const bookingRepository = {
  create: (data) => BookingModel.create(data),
  findByIdempotencyKey: (renterId, idempotencyKey) =>
    BookingModel.findOne({ renterId, idempotencyKey }).select(
      '+idempotencyKey +idempotencyFingerprint',
    ),
  findById: (id) => BookingModel.findOne({ $or: identifiers(id) }),
  findParticipantBooking: (id, identity) =>
    BookingModel.findOne({
      $or: identifiers(id),
      $and: [
        {
          $or: [
            { renterId: identity.authId },
            { ownerId: identity.authId },
            ...(identity.roles.includes('admin') ? [{}] : []),
          ],
        },
      ],
    }),

  async listFor({ field, identityId, page, limit, status }) {
    const filter = { [field]: identityId, ...(status && { status }) };
    const [items, total] = await Promise.all([
      BookingModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      BookingModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  async listAdmin({ page, limit, status }) {
    const filter = { ...(status && { status }) };
    const [items, total] = await Promise.all([
      BookingModel.find(filter)
        .sort({ updatedAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      BookingModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  findConflict: ({ listingId, startDate, endDate, excludeId }) =>
    BookingModel.findOne({
      listingId,
      status: { $in: ['approved', 'active'] },
      startDate: { $lte: endDate },
      endDate: { $gte: startDate },
      ...(excludeId && { publicId: { $ne: excludeId } }),
    }).lean(),

  findBlackout: (listingId, startDate, exclusiveEnd) =>
    AvailabilityModel.findOne({
      listingId,
      unavailableRanges: {
        $elemMatch: {
          start: { $lt: exclusiveEnd },
          end: { $gt: startDate },
        },
      },
    }).lean(),
};
