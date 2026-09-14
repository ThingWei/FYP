import { matchedData } from 'express-validator';
import { asyncHandler } from '../../core/asyncHandler.js';
import { created, ok } from '../../core/respond.js';
import { communicationService } from './communication.service.js';

export const communicationController = {
  fromBooking: asyncHandler(async (req, res) =>
    ok(
      res,
      await communicationService.fromBooking(req.params.bookingId, req.user),
    ),
  ),
  listThreads: asyncHandler(async (req, res) => {
    const result = await communicationService.listThreads(req.user, req.query);
    return ok(res, result.items, result.meta);
  }),
  listMessages: asyncHandler(async (req, res) => {
    const result = await communicationService.listMessages(
      req.params.threadId,
      req.user,
      req.query,
    );
    return ok(res, result.items, result.meta);
  }),
  sendMessage: asyncHandler(async (req, res) =>
    created(
      res,
      await communicationService.sendMessage(
        req.params.threadId,
        matchedData(req, { locations: ['body'] }).text,
        req.user,
      ),
    ),
  ),
  markRead: asyncHandler(async (req, res) =>
    ok(
      res,
      await communicationService.markRead(req.params.threadId, req.user),
    ),
  ),
  reportMessage: asyncHandler(async (req, res) =>
    created(
      res,
      await communicationService.reportMessage(
        req.params.messageId,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  listReports: asyncHandler(async (req, res) => {
    const result = await communicationService.listReports(req.query);
    return ok(res, result.items, result.meta);
  }),
  resolveReport: asyncHandler(async (req, res) =>
    ok(
      res,
      await communicationService.resolveReport(
        req.params.reportId,
        matchedData(req, { locations: ['body'] }),
        req.user,
      ),
    ),
  ),
  listNotifications: asyncHandler(async (req, res) => {
    const result = await communicationService.listNotifications(
      req.user,
      req.query,
    );
    return ok(res, result.items, result.meta);
  }),
  readNotification: asyncHandler(async (req, res) =>
    ok(
      res,
      await communicationService.readNotification(
        req.params.notificationId,
        req.user,
      ),
    ),
  ),
  readAllNotifications: asyncHandler(async (req, res) =>
    ok(res, await communicationService.readAllNotifications(req.user)),
  ),
  deleteNotification: asyncHandler(async (req, res) =>
    ok(
      res,
      await communicationService.deleteNotification(
        req.params.notificationId,
        req.user,
      ),
    ),
  ),
  clearNotifications: asyncHandler(async (req, res) =>
    ok(res, await communicationService.clearNotifications(req.user)),
  ),
};
