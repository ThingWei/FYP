import { PRICE_SOURCES } from '../modules/listing/priceSources.registry.js';
import { collectSourceQuotes } from '../modules/listing/priceSync.service.js';
import { env } from '../config/env.js';

// Read-only onboarding diagnostic: no MongoDB connection, no insertion or enabling.
const id = process.argv[2];
if (id && !PRICE_SOURCES.some((source) => source.id === id)) throw new Error('Unknown source ID');
for (const source of PRICE_SOURCES.filter((entry) => !id || entry.id === id)) {
  if (source.requiresWrittenPermission && !env.priceSyncApprovedSources.includes(source.id)) {
    console.log(JSON.stringify({ sourceId: source.id, available: false,
      error: 'WRITTEN_PERMISSION_REQUIRED', enabled: false, databaseWrites: 0,
      reason: source.limitation, reusePermissionEstablished: false }));
    continue;
  }
  if (!source.adapter) {
    console.log(JSON.stringify({ sourceId: source.id, available: false,
      error: 'ADAPTER_PENDING', reason: source.limitation, enabled: false, databaseWrites: 0 }));
    continue;
  }
  try {
    const result = await collectSourceQuotes(source);
    console.log(JSON.stringify({ sourceId: source.id, accepted: result.rows.length,
      domains: [...new Set(result.rows.map((row) => row.subcategory))],
      skipped: result.skipped.length, skipReasons: [...new Set(result.skipped)], pages: result.pages,
      enabled: false, databaseWrites: 0, reusePermissionEstablished: false }));
  } catch (error) {
    console.log(JSON.stringify({ sourceId: source.id, available: false,
      error: error.message, enabled: false, databaseWrites: 0 }));
  }
}
