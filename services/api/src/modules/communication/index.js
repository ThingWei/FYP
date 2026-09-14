import { communicationRouter } from './communication.routes.js';
import { communicationService } from './communication.service.js';
import { MessageModel } from './message.model.js';
import { MessageReportModel } from './messageReport.model.js';
import { NotificationModel } from './notification.model.js';
import { ThreadModel } from './thread.model.js';

export const communicationModule = {
  router: communicationRouter,
  service: communicationService,
  MessageModel,
  MessageReportModel,
  NotificationModel,
  ThreadModel,
};

