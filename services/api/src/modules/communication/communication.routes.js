import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { communicationController } from './communication.controller.js';
import {
  bookingThreadValidation,
  markReadValidation,
  notificationIdValidation,
  notificationsValidation,
  paginationValidation,
  reportMessageValidation,
  reportsValidation,
  resolveReportValidation,
  sendMessageValidation,
  threadMessagesValidation,
} from './communication.validation.js';

export const communicationRouter = Router();

communicationRouter.use(authenticate);

communicationRouter.get(
  '/threads',
  paginationValidation,
  validate,
  communicationController.listThreads,
);
communicationRouter.post(
  '/threads/from-booking/:bookingId',
  bookingThreadValidation,
  validate,
  communicationController.fromBooking,
);
communicationRouter.get(
  '/threads/:threadId/messages',
  threadMessagesValidation,
  validate,
  communicationController.listMessages,
);
communicationRouter.post(
  '/threads/:threadId/messages',
  sendMessageValidation,
  validate,
  communicationController.sendMessage,
);
communicationRouter.post(
  '/threads/:threadId/read',
  markReadValidation,
  validate,
  communicationController.markRead,
);
communicationRouter.post(
  '/:messageId/report',
  reportMessageValidation,
  validate,
  communicationController.reportMessage,
);
communicationRouter.get(
  '/reports',
  authorize('admin'),
  reportsValidation,
  validate,
  communicationController.listReports,
);
communicationRouter.patch(
  '/reports/:reportId',
  authorize('admin'),
  resolveReportValidation,
  validate,
  communicationController.resolveReport,
);
communicationRouter.get(
  '/notifications',
  notificationsValidation,
  validate,
  communicationController.listNotifications,
);
communicationRouter.post(
  '/notifications/read-all',
  communicationController.readAllNotifications,
);
communicationRouter.delete(
  '/notifications',
  communicationController.clearNotifications,
);
communicationRouter.post(
  '/notifications/:notificationId/read',
  notificationIdValidation,
  validate,
  communicationController.readNotification,
);
communicationRouter.delete(
  '/notifications/:notificationId',
  notificationIdValidation,
  validate,
  communicationController.deleteNotification,
);
