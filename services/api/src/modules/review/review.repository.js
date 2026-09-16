import { ReviewModel } from './review.model.js';

function pages({ page, limit }) {
  return {
    skip: (page - 1) * limit,
    limit,
  };
}

export const reviewRepository = {
  create: (data) => ReviewModel.create(data),
  findById: (id) => ReviewModel.findOne({ publicId: id }),
  findByRentalAndAuthor: (rentalId, authorId) =>
    ReviewModel.findOne({ rentalId, authorId }),
  listForListing({ listingId, page, limit }) {
    const query = { listingId, subjectRole: 'owner', status: 'published' };
    const paging = pages({ page, limit });
    return Promise.all([
      ReviewModel.find(query)
        .sort({ createdAt: -1 })
        .skip(paging.skip)
        .limit(paging.limit),
      ReviewModel.countDocuments(query),
    ]);
  },
  listForUser({ field, userId, page, limit }) {
    const query = { [field]: userId };
    const paging = pages({ page, limit });
    return Promise.all([
      ReviewModel.find(query)
        .sort({ createdAt: -1 })
        .skip(paging.skip)
        .limit(paging.limit),
      ReviewModel.countDocuments(query),
    ]);
  },
  listAdmin({ page, limit, status, flagged }) {
    const query = {
      ...(status && { status }),
      ...(flagged && { 'flag.flaggedAt': { $exists: true } }),
    };
    const paging = pages({ page, limit });
    return Promise.all([
      ReviewModel.find(query)
        .sort({ createdAt: -1 })
        .skip(paging.skip)
        .limit(paging.limit),
      ReviewModel.countDocuments(query),
    ]);
  },
  summary(subjectId) {
    return ReviewModel.aggregate([
      { $match: { subjectId, status: 'published' } },
      {
        $group: {
          _id: '$subjectId',
          averageRating: { $avg: '$overallRating' },
          reviewCount: { $sum: 1 },
        },
      },
    ]);
  },
};
