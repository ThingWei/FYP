import { createModule } from '../../core/moduleFactory.js';
export const adminModule = createModule('AdminAudit', { actorId: String, action: String, targetType: String, targetId: String, metadata: Object });

