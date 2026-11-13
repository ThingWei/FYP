import mongoose from 'mongoose';
import { RentalModel } from './rental.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { overdueCandidateFilter } from './overduePolicy.js';

function overdueStages(filter) {
  return [{ $match: { $and: [filter, overdueCandidateFilter()] } },
    { $lookup: { from: BookingModel.collection.name, localField: 'bookingId', foreignField: 'publicId', as: 'closedBooking',
      pipeline: [{ $match: { status: { $in: ['completed', 'cancelled', 'expired'] } } }, { $project: { _id: 1 } }] } },
    { $match: { closedBooking: { $size: 0 } } }, { $unset: 'closedBooking' }];
}

function identifiers(id) {
  const values = [{ publicId: id }, { bookingId: id }];
  if (mongoose.isValidObjectId(id)) values.push({ _id: id });
  return values;
}

export const rentalRepository = {
  async countOverdue(ownerId) {
    const [row] = await RentalModel.aggregate([...overdueStages({ ownerId }), { $count: 'count' }]);
    return row?.count ?? 0;
  },
  listExpiredExtensions: (now) => RentalModel.find({ 'extension.status': 'pending', 'extension.expiresAt': { $lte: now } }).limit(100),
  findById: (id) => RentalModel.findOne({ $or: identifiers(id) }),

  findParticipantRental: (id, identity) =>
    RentalModel.findOne({
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

  async listFor({ field, identityId, page, limit, status, bookingIds, attention }) {
    const filter = { [field]: identityId, ...(status && { status }), ...(bookingIds && { bookingId: { $in: bookingIds } }) };
    if (attention === 'overdue') {
      const [result] = await RentalModel.aggregate([...overdueStages(filter), { $facet: {
        items: [{ $sort: { endDate: 1, _id: 1 } }, { $skip: (page - 1) * limit }, { $limit: limit }],
        total: [{ $count: 'count' }],
      } }]);
      return [result.items.map(row => RentalModel.hydrate(row)), result.total[0]?.count ?? 0];
    }
    const [items, total] = await Promise.all([
      RentalModel.find(filter)
        .sort({ updatedAt: -1, _id: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      RentalModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  async listAdmin({ page, limit, status }) {
    const filter = { ...(status && { status }) };
    const [items, total] = await Promise.all([
      RentalModel.find(filter)
        .sort({ updatedAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      RentalModel.countDocuments(filter),
    ]);
    return [items, total];
  },
};
