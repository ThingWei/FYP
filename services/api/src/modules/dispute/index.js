import { ClaimModel } from './claim.model.js';
import { disputeRepository } from './dispute.repository.js';
import { disputeRouter } from './dispute.routes.js';
import { disputeService } from './dispute.service.js';
import { DisputeModel } from './dispute.model.js';

export const disputeModule = {
  router: disputeRouter,
  service: disputeService,
  repository: disputeRepository,
  DisputeModel,
  ClaimModel,
};

