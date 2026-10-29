import { MessageModel } from './message.model.js';
import { MessageReportModel } from './messageReport.model.js';
import { NotificationModel } from './notification.model.js';
import { ThreadModel } from './thread.model.js';

export const communicationRepository = {
  ensureThread: (booking, publicId) =>
    ThreadModel.findOneAndUpdate(
      { bookingId: booking.publicId },
      {
        $setOnInsert: {
          publicId,
          bookingId: booking.publicId,
          listingId: booking.listingId,
          listingTitle: booking.listingTitle,
          listingType: booking.listingType,
          renterId: booking.renterId,
          ownerId: booking.ownerId,
          participantIds: [booking.renterId, booking.ownerId],
        },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ),
  findThread: (threadId, userId) =>
    ThreadModel.findOne({ publicId: threadId, participantIds: userId }),
  findThreadByBooking: (bookingId, userId) =>
    ThreadModel.findOne({ bookingId, participantIds: userId }),
  async listThreads(userId, page, limit) {
    const [result] = await ThreadModel.aggregate([
      { $match: { participantIds: userId } },
      { $sort: { createdAt: 1, _id: 1 } },
      { $set: { peer: { $arrayElemAt: [{ $filter: { input: '$participantIds', as: 'p', cond: { $ne: ['$$p', userId] } } }, 0] } } },
      { $group: { _id: '$peer', thread: { $first: '$$ROOT' }, threadIds: { $push: '$publicId' }, bookingCount: { $sum: 1 }, lastCreated: { $max: '$createdAt' } } },
      { $lookup: { from: MessageModel.collection.name, let: { ids: '$threadIds' }, pipeline: [
        { $match: { $expr: { $in: ['$threadId', '$$ids'] }, deletedFor: { $ne: userId } } },
        { $sort: { createdAt: -1, _id: -1 } }, { $limit: 1 },
        { $project: { text: 1, recalledAt: 1, location: 1, attachment: 1, createdAt: 1, senderId: 1 } },
      ], as: 'latest' } },
      { $lookup: { from: MessageModel.collection.name, let: { ids: '$threadIds' }, pipeline: [
        { $match: { $expr: { $in: ['$threadId', '$$ids'] }, recipientId: userId, readAt: null, recalledAt: null, deletedFor: { $ne: userId } } }, { $count: 'n' },
      ], as: 'unread' } },
      { $set: { latest: { $arrayElemAt: ['$latest', 0] } } },
      { $set: { sortAt: { $ifNull: ['$latest.createdAt', '$lastCreated'] } } },
      { $sort: { sortAt: -1, _id: 1 } },
      { $facet: { items: [{ $skip: (page - 1) * limit }, { $limit: limit }], count: [{ $count: 'n' }] } },
    ]);
    return [(result?.items ?? []).map(row => ({ ...ThreadModel.hydrate(row.thread).toJSON(),
      threadIds: row.threadIds, bookingCount: row.bookingCount,
      lastMessageText: row.latest ? row.latest.recalledAt ? 'Message recalled' : row.latest.text || (row.latest.location ? 'Shared a location' : '[Image]') : '',
      lastMessageAt: row.latest?.createdAt, unreadCount: row.unread[0]?.n ?? 0,
    })), result?.count[0]?.n ?? 0];
  },
  relatedThreadIds: async thread => (await ThreadModel.find({
    participantIds: { $all: thread.participantIds, $size: 2 },
  }).select('publicId').lean()).map(row => row.publicId),
  createMessage: (data) => MessageModel.create(data),
  findMessage: (messageId) => MessageModel.findOne({ publicId: messageId }),
  updateThreadPreview: (threadId, message) =>
    ThreadModel.findOneAndUpdate(
      { publicId: threadId, $or: [{lastMessageAt:{$lte:message.createdAt}}, {lastMessageAt:{$exists:false}}] },
      {
        $set: {
          lastMessageText: message.recalledAt ? 'Message recalled' : message.text || (message.location ? 'Shared a location' : '[Image]'),
          lastMessageSenderId: message.senderId,
          lastMessageAt: message.createdAt,
        },
      },
      { new: true },
    ),
  async listMessages(threadIds, page, limit, userId, before) {
    const filter = { threadId: { $in: threadIds }, deletedFor: { $ne: userId } };
    if (before) filter.$or = [{ createdAt: { $lt: before.createdAt } }, { createdAt: before.createdAt, _id: { $lt: before._id } }];
    const [items, total] = await Promise.all([
      MessageModel.find(filter)
        .sort({ createdAt: -1, _id: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      MessageModel.countDocuments(filter),
    ]);
    return [items.reverse(), total];
  },
  countUnread: (threadId, userId) =>
    MessageModel.countDocuments({ threadId, recipientId: userId, readAt: null }),
  markThreadRead: (threadIds, userId, readAt) =>
    MessageModel.updateMany(
      { threadId: { $in: threadIds }, recipientId: userId, readAt: null, deletedFor: { $ne: userId }, recalledAt: null },
      { $set: { readAt } },
    ),
  findReport: (messageId, reporterId) =>
    MessageReportModel.findOne({ messageId, reporterId }),
  createReport: (data) => MessageReportModel.create(data),
  listReports: (filter, page, limit) =>
    Promise.all([
      MessageReportModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      MessageReportModel.countDocuments(filter),
    ]),
  findReportById: (reportId) =>
    MessageReportModel.findOne({ publicId: reportId }),
  async createNotification(data) {
    try {
      return {
        notification: await NotificationModel.create(data),
        created: true,
      };
    } catch (error) {
      if (error?.code !== 11000 || !data.dedupeKey) throw error;
      return {
        notification: await NotificationModel.findOne({
          dedupeKey: data.dedupeKey,
        }),
        created: false,
      };
    }
  },
  listNotifications: (filter, page, limit) =>
    Promise.all([
      NotificationModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      NotificationModel.countDocuments(filter),
      NotificationModel.countDocuments({ userId: filter.userId, readAt: null }),
    ]),
  findNotification: (notificationId, userId) =>
    NotificationModel.findOne({ publicId: notificationId, userId }),
  markAllNotificationsRead: (userId, readAt) =>
    NotificationModel.updateMany(
      { userId, readAt: null },
      { $set: { readAt } },
    ),
  deleteNotification: (notificationId, userId) =>
    NotificationModel.deleteOne({ publicId: notificationId, userId }),
  clearNotifications: (userId) => NotificationModel.deleteMany({ userId }),
};
