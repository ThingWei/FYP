import {
  applicationDefault,
  getApps,
  initializeApp,
} from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { env } from '../config/env.js';
import { DeviceRegistrationModel } from '../modules/communication/deviceRegistration.model.js';
import { UserModel } from '../modules/user/user.model.js';

const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

function messaging() {
  const app =
    getApps()[0] ??
    initializeApp({
      credential: applicationDefault(),
      projectId: env.firebaseProjectId,
    });
  return getMessaging(app);
}

function chunks(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function dataPayload(notification) {
  return {
    notificationId: notification.publicId,
    category: notification.category,
    type: notification.type,
    entityType: notification.entityType,
    entityId: notification.entityId,
  };
}

async function recordBatch(registrations, response) {
  const deliveredIds = [];
  const invalidIds = [];
  const failures = [];
  response.responses.forEach((item, index) => {
    const registration = registrations[index];
    if (item.success) {
      deliveredIds.push(registration._id);
      return;
    }
    const code = item.error?.code ?? 'messaging/unknown-error';
    if (INVALID_TOKEN_CODES.has(code)) invalidIds.push(registration._id);
    else failures.push({ id: registration._id, error: item.error?.message ?? code });
  });
  const now = new Date();
  await Promise.all([
    deliveredIds.length
      ? DeviceRegistrationModel.updateMany(
          { _id: { $in: deliveredIds } },
          {
            $set: {
              lastDeliveredAt: now,
              lastError: '',
              failureCount: 0,
            },
          },
        )
      : undefined,
    invalidIds.length
      ? DeviceRegistrationModel.deleteMany({ _id: { $in: invalidIds } })
      : undefined,
    ...failures.map(({ id, error }) =>
      DeviceRegistrationModel.updateOne(
        { _id: id },
        {
          $set: { lastFailureAt: now, lastError: error.slice(0, 500) },
          $inc: { failureCount: 1 },
        },
      ),
    ),
  ]);
  return {
    delivered: deliveredIds.length,
    failed: failures.length,
    removed: invalidIds.length,
  };
}

export const pushDelivery = {
  status() {
    return {
      status: env.fcmMode === 'firebase' ? 'configured' : 'disabled',
      provider: env.fcmMode,
    };
  },

  async send(notification) {
    if (env.fcmMode !== 'firebase') {
      return { status: 'disabled', delivered: 0, failed: 0, removed: 0 };
    }
    let registrations = [];
    try {
      const user = await UserModel.findOne({
        authId: notification.userId,
        accountStatus: 'active',
      })
        .select('settings.pushNotifications')
        .lean();
      if (!user?.settings?.pushNotifications) {
        return { status: 'suppressed', delivered: 0, failed: 0, removed: 0 };
      }
      registrations = await DeviceRegistrationModel.find({
        userId: notification.userId,
        enabled: true,
      }).select('+token');
      if (!registrations.length) {
        return { status: 'no_devices', delivered: 0, failed: 0, removed: 0 };
      }
      const total = { delivered: 0, failed: 0, removed: 0 };
      for (const batch of chunks(registrations, 500)) {
        const response = await messaging().sendEachForMulticast({
          tokens: batch.map((item) => item.token),
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: dataPayload(notification),
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default' } } },
          webpush: env.webAppUrl
            ? { fcmOptions: { link: env.webAppUrl } }
            : undefined,
        });
        const result = await recordBatch(batch, response);
        total.delivered += result.delivered;
        total.failed += result.failed;
        total.removed += result.removed;
      }
      return { status: total.failed ? 'partial' : 'sent', ...total };
    } catch (error) {
      if (registrations.length) {
        await DeviceRegistrationModel.updateMany(
          { _id: { $in: registrations.map((item) => item._id) } },
          {
            $set: {
              lastFailureAt: new Date(),
              lastError: error.message.slice(0, 500),
            },
            $inc: { failureCount: 1 },
          },
        ).catch(() => undefined);
      }
      console.error('FCM delivery failed', {
        notificationId: notification.publicId,
        message: error.message,
      });
      return {
        status: 'failed',
        delivered: 0,
        failed: 1,
        removed: 0,
        error: error.message,
      };
    }
  },
};
