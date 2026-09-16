import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from './loyalty.model.js';
import { loyaltyRepository } from './loyalty.repository.js';
import { loyaltyRouter } from './loyalty.routes.js';
import { loyaltyService } from './loyalty.service.js';

export const loyaltyModule = {
  router: loyaltyRouter,
  service: loyaltyService,
  repository: loyaltyRepository,
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
};

