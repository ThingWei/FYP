import { createModule } from '../../core/moduleFactory.js';
export const communicationModule = createModule('Message', { threadId: String, senderId: String, recipientId: String, text: String, readAt: Date });

