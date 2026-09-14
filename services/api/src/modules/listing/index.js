import { AvailabilityModel } from './availability.model.js';
import { listingController } from './listing.controller.js';
import { ListingModel } from './listing.model.js';
import { listingRepository } from './listing.repository.js';
import { listingRouter } from './listing.routes.js';
import { listingService } from './listing.service.js';

export const listingModule = {
  Model: ListingModel,
  AvailabilityModel,
  repository: listingRepository,
  service: listingService,
  controller: listingController,
  router: listingRouter,
};
