import { env } from '../config/env.js';
import { runItemVisionJob, reconcileItemVisionJobs } from '../modules/listing/itemVision.service.js';
let timer, trigger, wakeRequested = false, running = false;
export function startItemVisionJobs() {
  if (timer || !env.geminiItemReviewEnabled) return;
  const run = async (reconcile = true) => {
    if (running) { if (!reconcile) wakeRequested = true; return; }
    running = true;
    try { if (reconcile) await reconcileItemVisionJobs(); await runItemVisionJob(); }
    catch { console.warn('Item photo review is temporarily unavailable.'); }
    finally { running = false; if (wakeRequested && trigger) { wakeRequested = false; setImmediate(trigger); } }
  };
  trigger = () => { void run(false); };
  run(); timer = setInterval(run, 10000); timer.unref();
}
export function stopItemVisionJobs() { if (timer) clearInterval(timer); timer = undefined; trigger = undefined; wakeRequested = false; }

export function wakeItemVisionJobs() { if (trigger) setImmediate(trigger); }
