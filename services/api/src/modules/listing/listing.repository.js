import mongoose from 'mongoose';
import { AvailabilityModel } from './availability.model.js';
import { ListingModel } from './listing.model.js';

function identifiers(id) {
  const values = [{ publicId: id }];
  if (mongoose.isValidObjectId(id)) values.push({ _id: id });
  return values;
}

export const listingRepository = {
  create: (data) => ListingModel.create(data),

  findById: (id) => ListingModel.findOne({ $or: identifiers(id) }),

  findPublicById: (id) =>
    ListingModel.findOne({ $or: identifiers(id), status: 'active' }),

  findOwnedById: (id, ownerId) =>
    ListingModel.findOne({ $or: identifiers(id), ownerId }),

  async listPublic({ page, limit, filter, unavailableIds, sort }) {
    const criteria = { status: 'active', ...filter };
    if (unavailableIds?.length) criteria.publicId = { $nin: unavailableIds };
    const [items, total] = await Promise.all([
      ListingModel.find(criteria)
        .sort(sort)
        .skip((page - 1) * limit)
        .limit(limit),
      ListingModel.countDocuments(criteria),
    ]);
    return [items, total];
  },

  async listOwned({ ownerId, page, limit, status }) {
    const filter = { ownerId, ...(status && { status }) };
    const [items, total] = await Promise.all([
      ListingModel.find(filter)
        .sort({ updatedAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      ListingModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  async listAdmin({ page, limit, status }) {
    const filter = { ...(status && { status }) };
    const [items, total] = await Promise.all([
      ListingModel.find(filter)
        .sort({ updatedAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      ListingModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  findAvailability: (listingId) =>
    AvailabilityModel.findOne({ listingId }).lean(),

  async saveAvailability(listingId, ownerId, data) {
    const record =
      (await AvailabilityModel.findOne({ listingId })) ??
      new AvailabilityModel({ listingId, ownerId });
    record.set(data);
    await record.save();
    return record;
  },

  findUnavailableListingIds: async (start, end) => {
    const records = await AvailabilityModel.find({
      unavailableRanges: {
        $elemMatch: { start: { $lt: end }, end: { $gt: start } },
      },
    })
      .select('listingId')
      .lean();
    return records.map((record) => record.listingId);
  },
};
