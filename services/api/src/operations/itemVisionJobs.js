import { env } from '../config/env.js';
import { runItemVisionJob, reconcileItemVisionJobs } from '../modules/listing/itemVision.service.js';
let timer, running = false;
export function startItemVisionJobs() {
  if (timer || !env.geminiItemReviewEnabled) return;
  const run = async () => {
    if (running) return;
    running = true;
    try { await reconcileItemVisionJobs(); await runItemVisionJob(); }
    catch { console.warn('Item photo review is temporarily unavailable.'); }
    finally { running = false; }
  };
  run(); timer = setInterval(run, 10000); timer.unref();
}
export function stopItemVisionJobs() { if (timer) clearInterval(timer); timer = undefined; }
