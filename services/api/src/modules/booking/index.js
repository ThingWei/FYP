import { bookingController } from './booking.controller.js';
import { BookingModel } from './booking.model.js';
import { bookingRepository } from './booking.repository.js';
import { bookingRouter } from './booking.routes.js';
import { bookingService } from './booking.service.js';

export const bookingModule = {
  Model: BookingModel,
  repository: bookingRepository,
  service: bookingService,
  controller: bookingController,
  router: bookingRouter,
};
