import { env } from '../../config/env.js';

// Bounded expanding result windows, not an unrestricted catalogue download.
export const MAX_CATALOG_RESULTS = 120;
export const CATALOG_LOOKAHEAD_LIMIT = MAX_CATALOG_RESULTS + 1;

export function catalogResultLimit(input = {}) {
  const value = Number(input.limit ?? env.catalogMaxResults);
  return Number.isSafeInteger(value) && value > 0
    ? Math.min(value, CATALOG_LOOKAHEAD_LIMIT) : env.catalogMaxResults;
}
