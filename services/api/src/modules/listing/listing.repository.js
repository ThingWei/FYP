import mongoose from 'mongoose';
import { TRUST_POLICY_VERSION } from '../user/trustPolicy.js';
import { BookingModel } from '../booking/booking.model.js';
import { AvailabilityModel } from './availability.model.js';
import { ListingModel } from './listing.model.js';
import {
  blockingBookingCriteria,
  bookingDateOverlapCriteria,
} from './availabilityRules.js';

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
      sort.ownerTrustScore ? ListingModel.aggregate([
        { $match: criteria },
        { $set: { _trustOrder: { $let: { vars: { summary: { $cond: [{ $eq: ['$ownerTrustProfile.policyVersion', TRUST_POLICY_VERSION] }, '$ownerTrustProfile.recorded', '$ownerTrustProfile.marketplace'] } },
          in: { $cond: [{ $and: [{ $eq: ['$ownerTrustProfile.version', 'renthub-trust-v1'] }, { $eq: ['$$summary.status', 'established'] }] }, '$$summary.score', 50] } } } } },
        { $sort: { _trustOrder: -1, rating: -1, createdAt: -1, _id: -1 } },
        { $skip: (page - 1) * limit }, { $limit: limit }, { $unset: '_trustOrder' },
      ]).then(rows => rows.map(row => ListingModel.hydrate(row))) : ListingModel.find(criteria)
        // Equal prices/ratings/batch timestamps still need a unique page order.
        .sort({ ...sort, _id: sort._id ?? -1 })
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
        .sort({ updatedAt: -1, _id: -1 })
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
        .sort({ updatedAt: -1, _id: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      ListingModel.countDocuments(filter),
    ]);
    return [items, total];
  },

  findAvailability: (listingId) =>
    AvailabilityModel.findOne({ listingId }).lean(),

  findBookingUnavailableRanges: (listingId) =>
    BookingModel.find({
      listingId,
      ...blockingBookingCriteria(),
    })
      .select('publicId listingType status startDate endDate')
      .sort({ startDate: 1 })
      .lean(),

  async saveAvailability(listingId, ownerId, data) {
    const record =
      (await AvailabilityModel.findOne({ listingId })) ??
      new AvailabilityModel({ listingId, ownerId });
    record.set(data);
    await record.save();
    return record;
  },

  findUnavailableListingIds: async (start, end) => {
    const [manualRecords, bookingListingIds] = await Promise.all([
      AvailabilityModel.find({
        unavailableRanges: {
          $elemMatch: { start: { $lt: end }, end: { $gt: start } },
        },
      })
        .select('listingId')
        .lean(),
      BookingModel.distinct('listingId', {
        ...blockingBookingCriteria(),
        ...bookingDateOverlapCriteria(start, end),
      }),
    ]);
    return [...new Set([
      ...manualRecords.map((record) => record.listingId),
      ...bookingListingIds,
    ])];
  },
};
