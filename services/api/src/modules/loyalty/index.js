import { createModule } from '../../core/moduleFactory.js';
export const loyaltyModule = createModule('RewardLedger', { userId: String, type: String, points: Number, referralCode: String });

