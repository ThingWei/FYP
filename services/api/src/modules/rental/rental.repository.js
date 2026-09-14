import mongoose from 'mongoose';
import { RentalModel } from './rental.model.js';

function identifiers(id) {
  const values = [{ publicId: id }, { bookingId: id }];
  if (mongoose.isValidObjectId(id)) values.push({ _id: id });
  return values;
}

export const rentalRepository = {
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

  async listFor({ field, identityId, page, limit, status }) {
    const filter = { [field]: identityId, ...(status && { status }) };
    const [items, total] = await Promise.all([
      RentalModel.find(filter)
        .sort({ updatedAt: -1 })
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
