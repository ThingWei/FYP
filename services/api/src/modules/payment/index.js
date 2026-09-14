import { paymentController } from './payment.controller.js';
import { PaymentModel } from './payment.model.js';
import { paymentRepository } from './payment.repository.js';
import { paymentRouter } from './payment.routes.js';
import { paymentService } from './payment.service.js';

export const paymentModule = {
  Model: PaymentModel,
  repository: paymentRepository,
  service: paymentService,
  controller: paymentController,
  router: paymentRouter,
};
