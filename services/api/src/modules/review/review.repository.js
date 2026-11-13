import { ReviewModel } from './review.model.js';

function pages({ page, limit }) {
  return {
    skip: (page - 1) * limit,
    limit,
  };
}

export const reviewRepository = {
  listPublishedSubject({ userId, role, page, limit }) {
    const filter = { subjectId: userId, status: 'published', authorId: { $ne: userId },
      ...(role && role !== 'overall' && { subjectRole: role }) };
    return Promise.all([
      ReviewModel.find(filter).select('-_id publicId authorName authorRole subjectRole listingTitle listingType overallRating communicationRating conditionRating valueRating text createdAt editedAt')
        .sort({ createdAt: -1, _id: -1 }).skip((page - 1) * limit).limit(limit).lean(),
      ReviewModel.countDocuments(filter),
    ]);
  },
  create: (data) => ReviewModel.create(data),
  findById: (id) => ReviewModel.findOne({ publicId: id }),
  findByRentalAndAuthor: (rentalId, authorId) =>
    ReviewModel.findOne({ rentalId, authorId }),
  listForListing({ listingId, page, limit }) {
    const query = { listingId, subjectRole: 'owner', status: 'published' };
    const paging = pages({ page, limit });
    return Promise.all([
      ReviewModel.find(query)
        .sort({ createdAt: -1, _id: -1 })
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
        .sort({ createdAt: -1, _id: -1 })
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
        .sort({ createdAt: -1, _id: -1 })
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
