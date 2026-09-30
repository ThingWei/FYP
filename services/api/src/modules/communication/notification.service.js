import mongoose from 'mongoose';
import { emitNotification } from '../../socket/eventBus.js';
import { communicationRepository } from './communication.repository.js';
import { pushDelivery } from '../../integrations/pushDelivery.js';

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
