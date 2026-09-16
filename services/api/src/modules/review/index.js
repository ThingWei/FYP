import { ReviewModel } from './review.model.js';
import { reviewRepository } from './review.repository.js';
import { reviewRouter } from './review.routes.js';
import { reviewService } from './review.service.js';

export const reviewModule = {
  router: reviewRouter,
  service: reviewService,
  repository: reviewRepository,
  ReviewModel,
};
