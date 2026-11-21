import { Router } from 'express';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { communicationController } from './communication.controller.js';
import { pushDelivery } from '../../integrations/pushDelivery.js';
import { asyncHandler } from '../../core/asyncHandler.js';
import { ok, created } from '../../core/respond.js';
import { matchedData, body, param } from 'express-validator';
import { caseMessaging } from './caseMessaging.service.js';
import { disputeChat } from '../dispute/disputeChat.service.js';
import { caseMessagesValidation, caseMessageSendValidation } from '../dispute/dispute.validation.js';
import {
  bookingThreadValidation,
  deviceIdValidation,
  deviceRegistrationValidation,
  markReadValidation,
  notificationIdValidation,
  notificationsValidation,
  paginationValidation,
  reportMessageValidation,
  reportsValidation,
  resolveReportValidation,
  sendMessageValidation,
  threadMessagesValidation,
  changeMessageValidation,
} from './communication.validation.js';

export const communicationRouter = Router();

communicationRouter.use(authenticate);
communicationRouter.get('/cases', paginationValidation, validate, asyncHandler(async (req, res) => {
  const result = await caseMessaging.list(req.user, req.query); return ok(res, result.items, result.meta);
}));
communicationRouter.get('/cases/:id/messages', caseMessagesValidation, validate, asyncHandler(async (req, res) => {
  const result = await disputeChat.list(req.params.id, req.query, req.user); return ok(res, result.items, result.meta);
}));
communicationRouter.post('/cases/:id/messages', caseMessageSendValidation, validate, asyncHandler(async (req, res) =>
  created(res, await disputeChat.send(req.params.id, matchedData(req, { locations: ['body'] }), req.user))));
communicationRouter.post('/cases/:id/read', [param('id').matches(/^RH-DSP-[A-Z0-9]+$/), body('readThroughAt').isISO8601()], validate,
  asyncHandler(async (req, res) => ok(res, await caseMessaging.read(req.params.id, req.user, req.body.readThroughAt))));
communicationRouter.get('/threads/:threadId/participant', markReadValidation, validate, communicationController.participantProfile);
communicationRouter.patch('/:messageId', changeMessageValidation, validate, communicationController.changeMessage);
communicationRouter.get('/notifications/:notificationId/target', notificationIdValidation, validate, communicationController.notificationTarget);
communicationRouter.get('/push/status', (_req, res) => {
  const status = pushDelivery.status();
  res.json({ success: true, data: { ...status, enabled: status.provider === 'firebase' } });
});

communicationRouter.get(
  '/threads',
  paginationValidation,
  validate,
  communicationController.listThreads,
);
communicationRouter.get(
  '/push/devices',
  communicationController.listPushDevices,
);
communicationRouter.post(
  '/push/devices',
  deviceRegistrationValidation,
  validate,
  communicationController.registerPushDevice,
);
communicationRouter.delete(
  '/push/devices/:deviceId',
  deviceIdValidation,
  validate,
  communicationController.removePushDevice,
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
