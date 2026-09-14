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
  listThreads: (userId, page, limit) =>
    Promise.all([
      ThreadModel.find({ participantIds: userId })
        .sort({ lastMessageAt: -1, createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      ThreadModel.countDocuments({ participantIds: userId }),
    ]),
  createMessage: (data) => MessageModel.create(data),
  findMessage: (messageId) => MessageModel.findOne({ publicId: messageId }),
  updateThreadPreview: (threadId, message) =>
    ThreadModel.findOneAndUpdate(
      { publicId: threadId },
      {
        $set: {
          lastMessageText: message.text,
          lastMessageSenderId: message.senderId,
          lastMessageAt: message.createdAt,
        },
      },
      { new: true },
    ),
  async listMessages(threadId, page, limit) {
    const [items, total] = await Promise.all([
      MessageModel.find({ threadId })
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      MessageModel.countDocuments({ threadId }),
    ]);
    return [items.reverse(), total];
  },
  countUnread: (threadId, userId) =>
    MessageModel.countDocuments({ threadId, recipientId: userId, readAt: null }),
  markThreadRead: (threadId, userId, readAt) =>
    MessageModel.updateMany(
      { threadId, recipientId: userId, readAt: null },
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
  createNotification: (data) => NotificationModel.create(data),
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
