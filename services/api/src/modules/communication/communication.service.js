import mongoose from 'mongoose';
import {createHash} from 'node:crypto';
import { notificationTarget } from './notificationTarget.js';
import { AppError } from '../../core/errors.js';
import { emitNewMessage, emitReadReceipt, emitMessageChange } from '../../socket/eventBus.js';
import { MessageModel } from './message.model.js';
import { ThreadModel } from './thread.model.js';
import { availableTrustProfile } from '../user/trust.service.js';
import { BookingModel } from '../booking/booking.model.js';
import { UserModel } from '../user/user.model.js';
import { communicationRepository } from './communication.repository.js';
import { ensureBookingThread, notifyUser } from './notification.service.js';
import { DeviceRegistrationModel } from './deviceRegistration.model.js';
import { uploadService } from '../upload/upload.service.js';

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
  async participantProfile(threadId, identity) {
    const thread = await participantThread(threadId, identity);
    const peerId = thread.participantIds.find(id => id !== identity.authId);
    const [viewer, peer] = await Promise.all([UserModel.findOne({ authId: identity.authId }), UserModel.findOne({ authId: peerId })]);
    if (!peer || peer.accountStatus !== 'active' || viewer.blockedUserIds.includes(peerId) || peer.blockedUserIds.includes(identity.authId)) throw new AppError('This profile is not available', 404, 'NOT_FOUND');
    return { id: peer.authId, displayName: peer.displayName, avatarUrl: peer.avatarUrl,
      verified: peer.verification?.status === 'approved', roles: peer.roles,
      joinedAt: peer.createdAt, trustProfile: await availableTrustProfile(peer.authId) };
  },
  async notificationTarget(id, identity) {
    await requireActiveUser(identity);
    return notificationTarget(id, identity);
  },
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
    const thread = await ensureBookingThread(booking);
    const peerId = thread.participantIds.find(id => id !== identity.authId);
    const peer = await UserModel.findOne({ authId: peerId }).select('displayName').lean();
    return { ...thread.toJSON(), otherParticipant: { id: peerId, displayName: peer?.displayName ?? 'RentHub user' } };
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
          ...thread,
          otherParticipant: {
            id: otherId,
            displayName: other?.displayName ?? 'RentHub user',
            trustScore: other?.trustProfile?.version === 'renthub-trust-v1' && other.trustProfile.overall?.marketplace?.status === 'established'
              ? other.trustProfile.overall.marketplace.score : 50,
            verified: other?.verification?.status === 'approved',
          },
        };
      }),
    );
    return { items, meta: { page, limit, total } };
  },

  async listMessages(threadId, identity, query) {
    const thread = await participantThread(threadId, identity);
    const threadIds = await communicationRepository.relatedThreadIds(thread);
    const { page, limit } = pages(query);
    const before = query.before ? await MessageModel.findOne({ publicId: query.before, threadId: { $in: threadIds }, deletedFor: { $ne: identity.authId } }).select('_id createdAt').lean() : null;
    if (query.before && !before) throw new AppError('Message page is no longer available. Refresh the conversation.', 409, 'MESSAGE_PAGE_CHANGED');
    const [items, total] = await communicationRepository.listMessages(
      threadIds,
      page,
      limit,
      identity.authId,
      before,
    );
    return { items, meta: { page, limit, total, hasMore: total > (page - 1) * limit + items.length, nextBefore: items[0]?.publicId ?? null } };
  },

  async sendMessage(threadId, input, identity) {
    const sender = await requireActiveUser(identity);
    let thread = await communicationRepository.findThread(
      threadId,
      sender.authId,
    );
    if (!thread) throw new AppError('Conversation not found', 404, 'NOT_FOUND');
    if (thread.status !== 'open') {
      thread = await ThreadModel.findOne({participantIds:{$all:thread.participantIds,$size:2},status:'open'}).sort({createdAt:-1,_id:-1});
      if(!thread)throw new AppError('Conversation is closed', 409, 'THREAD_CLOSED');
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
    let attachment;
    if (input.attachmentRef) {
      const asset = await uploadService.getOwnedReference(
        identity,
        input.attachmentRef,
        'message_image',
      );
      const uploaded = asset.toJSON();
      attachment = {
        kind: 'image',
        reference: uploaded.reference,
        contentUrl: uploaded.contentUrl,
        contentType: uploaded.contentType,
        filename: uploaded.originalName,
        size: uploaded.size,
      };
    }
    const fingerprint=createHash('sha256').update(JSON.stringify([recipientId,input.text?.trim()??'',input.attachmentRef??null,input.location?[input.location.latitude,input.location.longitude,input.location.label.trim()]:null])).digest('hex');
    const replay=async()=>{
      const previous=await MessageModel.findOne({senderId:sender.authId,clientMessageId:input.clientMessageId}).select('+sendFingerprint');
      if(!previous || previous.sendFingerprint!==fingerprint || previous.deletedFor.includes(sender.authId))throw new AppError('This message attempt changed. Start a new message.',409,'MESSAGE_SEND_CONFLICT');
      emitMessageChange(previous.toJSON(),thread.participantIds);
      return previous;
    };
    if(input.clientMessageId && await MessageModel.exists({senderId:sender.authId,clientMessageId:input.clientMessageId}))return replay();
    let message;
    try { message = await communicationRepository.createMessage({
      publicId: publicId('MSG'),
      threadId: thread.publicId,
      senderId: sender.authId,
      recipientId,
      text: input.text?.trim() ?? '',
      ...(attachment && { attachment }),
      ...(input.location && { location: input.location }),
      ...(input.clientMessageId && {clientMessageId:input.clientMessageId,sendFingerprint:fingerprint}),
    }); } catch(error){if(error?.code===11000 && input.clientMessageId)return replay();throw error;}
    await communicationRepository.updateThreadPreview(thread.publicId, message);
    await notifyUser({
      userId: recipientId,
      category: 'message',
      type: 'message_new',
      title: `New message from ${sender.displayName}`,
      body: message.text
        ? message.text.length > 200
          ? `${message.text.slice(0, 197)}...`
          : message.text
        : message.location ? 'Shared a location' : 'Sent an image',
      entityType: 'thread',
      entityId: thread.publicId,
    });
    emitNewMessage(message.toJSON(), thread.participantIds);
    return message;
  },

  async markRead(threadId, identity) {
    const thread = await participantThread(threadId, identity);
    const readAt = new Date();
    const result = await communicationRepository.markThreadRead(
      await communicationRepository.relatedThreadIds(thread),
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

  async changeMessage(messageId, input, identity) {
    await requireActiveUser(identity);
    const message = await MessageModel.findOne({ publicId: messageId, deletedFor: { $ne: identity.authId } });
    if (!message) throw new AppError('Message not found', 404, 'NOT_FOUND');
    const thread = await participantThread(message.threadId, identity);
    if (input.action === 'delete') {
      await MessageModel.updateOne({ _id: message._id }, { $addToSet: { deletedFor: identity.authId } });
      emitMessageChange({ ...message.toJSON(), deletedForMe: true }, [identity.authId]);
      return { publicId: message.publicId, deletedForMe: true };
    }
    if (message.senderId !== identity.authId) throw new AppError('Only your own messages can be changed', 403, 'FORBIDDEN');
    if (message.recalledAt && input.action === 'recall') return message;
    if (message.recalledAt || Date.now() - +message.createdAt > 15 * 60_000) throw new AppError('Messages can be edited or recalled for 15 minutes after sending', 409, 'MESSAGE_ACTION_EXPIRED');
    if (input.action === 'edit' && !message.text) throw new AppError('This message has no text to edit', 422, 'MESSAGE_NOT_EDITABLE');
    if (input.action === 'edit') {
      const accounts = await UserModel.find({ authId: { $in: thread.participantIds } });
      if (accounts.some(user => user.accountStatus !== 'active' || user.blockedUserIds.some(id => thread.participantIds.includes(id)))) throw new AppError('Messaging is unavailable between these accounts', 403, 'COMMUNICATION_BLOCKED');
    }
    const revision = message.revision ?? 0;
    if (input.expectedRevision !== revision) throw new AppError('This message changed. Refresh and try again.', 409, 'MESSAGE_CHANGED');
    const snapshot = { text: message.text, attachment: message.attachment?.toObject(), location: message.location?.toObject(), recordedAt: new Date() };
    const updated = await MessageModel.findOneAndUpdate({ _id: message._id, recalledAt: null,
      ...(revision === 0 ? { $or: [{ revision: 0 }, { revision: { $exists: false } }] } : { revision }) }, {
      $set: { ...(revision === 0 && { originalContent: snapshot }), ...(input.action === 'recall'
        ? { recalledAt: new Date(), text: '' } : { text: input.text, editedAt: new Date() }) },
      ...(input.action === 'recall' && { $unset: { attachment: 1, location: 1 } }),
      $inc: { revision: 1 }, $push: { editHistory: { $each: [snapshot], $slice: -20 } },
    }, { new: true, runValidators: true });
    if (!updated) throw new AppError('This message changed. Refresh and try again.', 409, 'MESSAGE_CHANGED');
    await communicationRepository.updateThreadPreview(thread.publicId, updated);
    emitMessageChange(updated.toJSON(), thread.participantIds);
    return updated;
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
      messageText: message.text || '[Image]',
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
