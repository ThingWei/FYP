import { createModule } from '../../core/moduleFactory.js';
export const userModule = createModule('User', { authId: { type: String, index: true }, email: { type: String, lowercase: true }, displayName: String, roles: [String], trustScore: { type: Number, default: 0 }, verificationTier: { type: String, default: 'unverified' } });

