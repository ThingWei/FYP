import { ClaimModel } from './claim.model.js';
import { DisputeModel } from './dispute.model.js';

function paging(page, limit) {
  return { skip: (page - 1) * limit, limit };
}

async function list(Model, filter, page, limit) {
  const range = paging(page, limit);
  return Promise.all([
    Model.find(filter).sort({ updatedAt: -1 }).skip(range.skip).limit(range.limit),
    Model.countDocuments(filter),
  ]);
}

export const disputeRepository = {
  create: (data) => DisputeModel.create(data),
  findById: (id) => DisputeModel.findOne({ publicId: id }),
  findByRental: (rentalId) => DisputeModel.findOne({ rentalId }),
  listParticipant(userId, page, limit) {
    return list(
      DisputeModel,
      { $or: [{ raisedById: userId }, { respondentId: userId }] },
      page,
      limit,
    );
  },
  listAdmin(status, page, limit) {
    return list(DisputeModel, status ? { status } : {}, page, limit);
  },
  createClaim: (data) => ClaimModel.create(data),
  findClaimById: (id) => ClaimModel.findOne({ publicId: id }),
  findClaimByRental: (rentalId) => ClaimModel.findOne({ rentalId }),
  listParticipantClaims(userId, page, limit) {
    return list(
      ClaimModel,
      { $or: [{ ownerId: userId }, { renterId: userId }] },
      page,
      limit,
    );
  },
  listAdminClaims(status, page, limit) {
    return list(ClaimModel, status ? { status } : {}, page, limit);
  },
};
