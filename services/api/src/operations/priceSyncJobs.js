import { env } from '../config/env.js';
import { enabledPriceSourceIds, runPriceSourceSync } from '../modules/listing/priceSync.service.js';

let timer, running = false, stopped = false;
export async function runDuePriceSyncJobs() {
  if (running) return;
  running = true;
  try {
    for (const id of await enabledPriceSourceIds()) {
      if (stopped) break;
      try { await runPriceSourceSync(id); }
      catch { console.warn(`Rental-price sync for ${id} unavailable; check administrator source status.`); }
    }
  } finally { running = false; }
}
export function startPriceSyncScheduler() {
  if (!env.priceSyncJobsEnabled || timer) return;
  stopped = false;
  const run = () => runDuePriceSyncJobs().catch(() => console.warn('Rental-price scheduler unavailable; existing pricing remains usable.'));
  run(); // Acquires only overdue sources; no unconditional startup recollection.
  timer = setInterval(run, 60_000);
  timer.unref();
}
export function stopPriceSyncScheduler() {
  stopped = true;
  if (timer) clearInterval(timer);
  timer = undefined;
}
