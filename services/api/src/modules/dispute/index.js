import { createModule } from '../../core/moduleFactory.js';
export const disputeModule = createModule('Dispute', { rentalId: String, raisedBy: String, reason: String, evidence: [String], status: { type: String, default: 'open' }, resolution: String });

