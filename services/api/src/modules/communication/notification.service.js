import mongoose from 'mongoose';
import { emitNotification } from '../../socket/eventBus.js';
import { communicationRepository } from './communication.repository.js';

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
  const notification = await communicationRepository.createNotification({
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
  emitNotification(notification.toJSON());
  return notification;
}
