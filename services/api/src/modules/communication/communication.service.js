import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { emitNewMessage, emitReadReceipt } from '../../socket/eventBus.js';
import { BookingModel } from '../booking/booking.model.js';
import { UserModel } from '../user/user.model.js';
import { communicationRepository } from './communication.repository.js';
import { ensureBookingThread, notifyUser } from './notification.service.js';
import { DeviceRegistrationModel } from './deviceRegistration.model.js';

function publicId(prefix) {
  const suffix = new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase();
  return `${prefix}-${suffix}`;
}

function pages(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

async function requireActiveUser(identity) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) {
    throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  return user;
}

async function participantThread(threadId, identity) {
  await requireActiveUser(identity);
  const thread = await communicationRepository.findThread(
    threadId,
    identity.authId,
  );
  if (!thread) throw new AppError('Conversation not found', 404, 'NOT_FOUND');
  return thread;
}

export const communicationService = {
  async listPushDevices(identity) {
    await requireActiveUser(identity);
    return DeviceRegistrationModel.find({ userId: identity.authId }).sort({
      lastSeenAt: -1,
    });
  },

  async registerPushDevice(identity, input) {
    await requireActiveUser(identity);
    await DeviceRegistrationModel.deleteMany({
      token: input.token,
      $or: [
        { userId: { $ne: identity.authId } },
        { deviceId: { $ne: input.deviceId } },
      ],
    });
    return DeviceRegistrationModel.findOneAndUpdate(
      { userId: identity.authId, deviceId: input.deviceId },
      {
        $set: {
          token: input.token,
          platform: input.platform,
          deviceName: input.deviceName ?? '',
          enabled: true,
          lastSeenAt: new Date(),
          lastError: '',
          failureCount: 0,
        },
      },
      { upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true },
    );
  },

  async removePushDevice(identity, deviceId) {
    await requireActiveUser(identity);
    const result = await DeviceRegistrationModel.deleteOne({
      userId: identity.authId,
      deviceId,
    });
    return { deviceId, removed: Boolean(result.deletedCount) };
  },
  async fromBooking(bookingId, identity) {
    await requireActiveUser(identity);
    const booking = await BookingModel.findOne({
      publicId: bookingId,
      $or: [{ renterId: identity.authId }, { ownerId: identity.authId }],
    });
    if (!booking) throw new AppError('Booking not found', 404, 'NOT_FOUND');
    return ensureBookingThread(booking);
  },

  async listThreads(identity, query) {
    await requireActiveUser(identity);
    const { page, limit } = pages(query);
    const [threads, total] = await communicationRepository.listThreads(
      identity.authId,
      page,
      limit,
    );
    const otherIds = threads.map((thread) =>
      thread.participantIds.find((id) => id !== identity.authId),
    );
    const users = await UserModel.find({ authId: { $in: otherIds } }).lean();
    const userMap = new Map(users.map((user) => [user.authId, user]));
    const items = await Promise.all(
      threads.map(async (thread) => {
        const otherId = thread.participantIds.find(
          (id) => id !== identity.authId,
        );
        const other = userMap.get(otherId);
        return {
          ...thread.toJSON(),
          unreadCount: await communicationRepository.countUnread(
            thread.publicId,
            identity.authId,
          ),
          otherParticipant: {
            id: otherId,
            displayName: other?.displayName ?? 'RentHub user',
            trustScore: other?.trustScore ?? 0,
            verified: other?.verification?.status === 'approved',
          },
        };
      }),
    );
    return { items, meta: { page, limit, total } };
  },

  async listMessages(threadId, identity, query) {
    await participantThread(threadId, identity);
    const { page, limit } = pages(query);
    const [items, total] = await communicationRepository.listMessages(
      threadId,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async sendMessage(threadId, text, identity) {
    const sender = await requireActiveUser(identity);
    const thread = await communicationRepository.findThread(
      threadId,
      sender.authId,
    );
    if (!thread) throw new AppError('Conversation not found', 404, 'NOT_FOUND');
    if (thread.status !== 'open') {
      throw new AppError('Conversation is closed', 409, 'THREAD_CLOSED');
    }
    const recipientId = thread.participantIds.find((id) => id !== sender.authId);
    const recipient = await UserModel.findOne({ authId: recipientId });
    if (!recipient || recipient.accountStatus !== 'active') {
      throw new AppError('Recipient is unavailable', 409, 'RECIPIENT_UNAVAILABLE');
    }
    if (
      sender.blockedUserIds.includes(recipientId) ||
      recipient.blockedUserIds.includes(sender.authId)
    ) {
      throw new AppError(
        'Messaging is unavailable between these accounts',
        403,
        'COMMUNICATION_BLOCKED',
      );
    }
    const message = await communicationRepository.createMessage({
      publicId: publicId('MSG'),
      threadId: thread.publicId,
      senderId: sender.authId,
      recipientId,
      text,
    });
    await communicationRepository.updateThreadPreview(thread.publicId, message);
    await notifyUser({
      userId: recipientId,
      category: 'message',
      type: 'message_new',
      title: `New message from ${sender.displayName}`,
      body:
        message.text.length > 200
          ? `${message.text.slice(0, 197)}...`
          : message.text,
      entityType: 'thread',
      entityId: thread.publicId,
    });
    emitNewMessage(message.toJSON(), thread.participantIds);
    return message;
  },

  async markRead(threadId, identity) {
    await participantThread(threadId, identity);
    const readAt = new Date();
    const result = await communicationRepository.markThreadRead(
      threadId,
      identity.authId,
      readAt,
    );
    const receipt = {
      threadId,
      readerId: identity.authId,
      readAt,
      updatedCount: result.modifiedCount,
    };
    emitReadReceipt(receipt);
    return receipt;
  },

  async reportMessage(messageId, input, identity) {
    await requireActiveUser(identity);
    const message = await communicationRepository.findMessage(messageId);
    if (!message) throw new AppError('Message not found', 404, 'NOT_FOUND');
    const thread = await communicationRepository.findThread(
      message.threadId,
      identity.authId,
    );
    if (!thread) throw new AppError('Message not found', 404, 'NOT_FOUND');
    if (message.senderId === identity.authId) {
      throw new AppError('You cannot report your own message', 400, 'OWN_MESSAGE');
    }
    const existing = await communicationRepository.findReport(
      message.publicId,
      identity.authId,
    );
    if (existing) return existing;
    return communicationRepository.createReport({
      publicId: publicId('RPT-MSG'),
      messageId: message.publicId,
      threadId: thread.publicId,
      reporterId: identity.authId,
      reportedUserId: message.senderId,
      messageText: message.text,
      reason: input.reason,
      details: input.details ?? '',
    });
  },

  async listReports(query) {
    const { page, limit } = pages(query);
    const filter = {};
    if (['open', 'resolved', 'dismissed'].includes(query.status)) {
      filter.status = query.status;
    }
    const [items, total] = await communicationRepository.listReports(
      filter,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async resolveReport(reportId, input, identity) {
    const report = await communicationRepository.findReportById(reportId);
    if (!report) throw new AppError('Report not found', 404, 'NOT_FOUND');
    if (report.status !== 'open') {
      throw new AppError('Report was already reviewed', 409, 'REPORT_REVIEWED');
    }
    report.status = input.status;
    report.resolution = input.resolution;
    report.reviewedBy = identity.authId;
    report.reviewedAt = new Date();
    await report.save();
    return report;
  },

  async listNotifications(identity, query) {
    await requireActiveUser(identity);
    const { page, limit } = pages(query);
    const filter = { userId: identity.authId };
    if (query.category) filter.category = query.category;
    if (query.read === 'true') filter.readAt = { $ne: null };
    if (query.read === 'false') filter.readAt = null;
    const [items, total, unread] =
      await communicationRepository.listNotifications(filter, page, limit);
    return { items, meta: { page, limit, total, unread } };
  },

  async readNotification(notificationId, identity) {
    await requireActiveUser(identity);
    const notification = await communicationRepository.findNotification(
      notificationId,
      identity.authId,
    );
    if (!notification) {
      throw new AppError('Notification not found', 404, 'NOT_FOUND');
    }
    notification.readAt ??= new Date();
    await notification.save();
    return notification;
  },

  async readAllNotifications(identity) {
    await requireActiveUser(identity);
    const result = await communicationRepository.markAllNotificationsRead(
      identity.authId,
      new Date(),
    );
    return { updatedCount: result.modifiedCount };
  },

  async deleteNotification(notificationId, identity) {
    await requireActiveUser(identity);
    const result = await communicationRepository.deleteNotification(
      notificationId,
      identity.authId,
    );
    if (!result.deletedCount) {
      throw new AppError('Notification not found', 404, 'NOT_FOUND');
    }
    return { id: notificationId, removed: true };
  },

  async clearNotifications(identity) {
    await requireActiveUser(identity);
    const result = await communicationRepository.clearNotifications(
      identity.authId,
    );
    return { removedCount: result.deletedCount };
  },
};
