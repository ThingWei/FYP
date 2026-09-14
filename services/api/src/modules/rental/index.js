import { rentalController } from './rental.controller.js';
import { RentalModel } from './rental.model.js';
import { rentalRepository } from './rental.repository.js';
import { rentalRouter } from './rental.routes.js';
import { rentalService } from './rental.service.js';

export const rentalModule = {
  Model: RentalModel,
  repository: rentalRepository,
  service: rentalService,
  controller: rentalController,
  router: rentalRouter,
};
