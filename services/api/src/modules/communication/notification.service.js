import mongoose from 'mongoose';
import { emitNotification } from '../../socket/eventBus.js';
import { communicationRepository } from './communication.repository.js';
import { pushDelivery } from '../../integrations/pushDelivery.js';
import { UserModel } from '../user/user.model.js';

export async function notifyCaseAdmins(dispute, { type, title, body, dedupeKey, excludeId }) {
  try {
    const users = await UserModel.find({ roles: 'admin', accountStatus: 'active', ...(excludeId && { authId: { $ne: excludeId } }) }).select('authId').lean();
    await Promise.allSettled(users.map(user => notifyUser({ userId: user.authId, category: 'dispute', type, title, body,
      entityType: 'dispute', entityId: dispute.publicId, dedupeKey: `${dedupeKey}:${user.authId}` })));
  } catch { /* A saved case transition must not fail because notification delivery failed. */ }
}

function publicId(prefix) {
  const suffix = new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase();
  return `${prefix}-${suffix}`;
}

export async function ensureBookingThread(booking) {
  return communicationRepository.ensureThread(booking, publicId('THR'));
}

export async function notifyUser({
  userId,
  category,
  type,
  title,
  body,
  entityType,
  entityId,
  dedupeKey,
}) {
  const { notification, created } =
    await communicationRepository.createNotification({
      publicId: publicId('NTF'),
      userId,
      category,
      type,
      title,
      body,
      entityType,
      entityId,
      dedupeKey,
    });
  if (created) {
    emitNotification(notification.toJSON());
    await pushDelivery.send(notification);
  }
  return notification;
}
