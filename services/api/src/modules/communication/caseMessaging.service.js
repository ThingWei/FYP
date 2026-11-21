import { AppError } from '../../core/errors.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { DisputeMessageModel } from '../dispute/disputeMessage.model.js';
import { caseViewer } from '../dispute/disputeChat.service.js';
import { UserModel } from '../user/user.model.js';
import { NotificationModel } from './notification.model.js';

// Case threads adapt the existing immutable evidence store into Messaging.
// Ordinary two-party booking threads and their permissions stay independent.
export const caseMessaging = {
  async list(identity, query = {}) {
    const user = await UserModel.findOne({ authId: identity.authId }).select('roles accountStatus');
    if (!user || user.accountStatus !== 'active') throw new AppError('Account access unavailable', 403, 'ACCOUNT_RESTRICTED');
    const admin = identity.roles?.includes('admin') && user.roles.includes('admin');
    const page = Math.max(Number(query.page) || 1, 1), limit = Math.min(Number(query.limit) || 20, 100);
    const filter = admin ? {} : { $or: [{ raisedById: identity.authId }, { respondentId: identity.authId }] };
    const [result] = await DisputeModel.aggregate([
      { $match: filter },
      { $lookup: { from: DisputeMessageModel.collection.name, let: { caseId: '$publicId' }, pipeline: [
        { $match: { $expr: { $eq: ['$disputeId', '$$caseId'] } } }, { $sort: { createdAt: -1, _id: -1 } }, { $limit: 1 },
        { $project: { text: 1, createdAt: 1, evidence: 1 } },
      ], as: 'latest' } },
      { $lookup: { from: NotificationModel.collection.name, let: { caseId: '$publicId' }, pipeline: [
        { $match: { userId: identity.authId, type: 'dispute_message', readAt: null, $expr: { $eq: ['$entityId', '$$caseId'] } } },
        { $count: 'count' },
      ], as: 'unread' } },
      { $set: { lastMessageAt: { $max: ['$updatedAt', { $first: '$latest.createdAt' }] } } },
      { $sort: { lastMessageAt: -1, publicId: -1 } },
      { $facet: { items: [{ $skip: (page - 1) * limit }, { $limit: limit }, { $project: {
        _id: 0, id: '$publicId', kind: { $literal: 'case' }, listingTitle: 1, status: 1,
        participants: ['$raisedByName', '$respondentName'], lastMessageAt: 1,
        lastMessageText: { $ifNull: [{ $first: '$latest.text' }, '$summary'] },
        unreadCount: { $ifNull: [{ $first: '$unread.count' }, 0] },
      } }], total: [{ $count: 'count' }] } },
    ]);
    return { items: result?.items ?? [], meta: { page, limit, total: result?.total[0]?.count ?? 0 } };
  },
  async read(id, identity, readThroughAt) {
    await caseViewer(id, identity);
    const at = new Date(Math.min(new Date(readThroughAt).getTime(), Date.now()));
    if (!Number.isFinite(+at)) throw new AppError('Refresh the conversation first', 422, 'VALIDATION_ERROR');
    await NotificationModel.updateMany({ userId: identity.authId, entityType: 'dispute', entityId: id,
      type: 'dispute_message', readAt: null, createdAt: { $lte: at } }, { $set: { readAt: new Date() } });
    return { read: true };
  },
};
