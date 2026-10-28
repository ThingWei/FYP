import { referencePeriodMatches } from './priceProductDomains.js';

export const RATE_BASES = ['daily_rate', 'fixed_period', 'duration_band', 'unknown'];
// Read-only compatibility for the installed v1 parsers. These specific parsers
// read /day, Daily or /24 Hours units. Never infer units from price or model name.
const LEGACY_DAILY_PARSERS = new Set(['rentism', 'itpa', 'cilt', 'alquiler', 'ecocana', 'pc-rent', 'jomrent']);

export function validRateBasis(row) {
  if (row.rateBasis == null || row.rateBasis === '') return true;
  if (!RATE_BASES.includes(row.rateBasis)) return false;
  const days = row.rentalDurationDays, min = row.durationMinDays ?? days, max = row.durationMaxDays ?? days;
  if (row.rateBasis === 'daily_rate') return days === 1 && min === 1 && max === 1;
  if (row.rateBasis === 'fixed_period') return min === days && max === days;
  return true;
}

export function referenceRateBasis(row) {
  if (row.rateBasis) return validRateBasis(row) ? row.rateBasis : 'unknown';
  if (row.collectionMethod === 'automatic' && row.parserVersion === '1' &&
      LEGACY_DAILY_PARSERS.has(row.sourceId) && row.validationStatus === 'accepted' && row.validatedAt &&
      row.rentalDurationDays === 1 && (row.durationMinDays ?? 1) === 1 && (row.durationMaxDays ?? 1) === 1) {
    return 'daily_rate';
  }
  return 'unknown';
}

export function referencePeriodEligibility(row, days) {
  const rateBasis = referenceRateBasis(row);
  if (!validRateBasis(row) || !Number.isInteger(days) || days < 1 || days > 365) {
    return { eligible: false, baseline: false, rateBasis };
  }
  if (referencePeriodMatches(row, days)) return { eligible: true, baseline: false, rateBasis };
  // This supplies an estimated daily-price baseline, never a verified longer-hire
  // tariff or a discount. Fixed packages and completed averages cannot use it.
  const baseline = days > 1 && rateBasis === 'daily_rate';
  return { eligible: baseline, baseline, rateBasis };
}
