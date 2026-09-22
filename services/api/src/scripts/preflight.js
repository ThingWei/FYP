import { env } from '../config/env.js';
import { runPreflight } from '../config/preflight.js';

const argumentsSet = new Set(process.argv.slice(2));
const checks = await runPreflight({
  config: env,
  requireProduction: argumentsSet.has('--require-production'),
  writeProbe: argumentsSet.has('--write-probe'),
});

for (const check of checks) {
  if (check.status === 'pass') {
    console.log(`[PASS] ${check.name}: ${JSON.stringify(check.details)}`);
  } else {
    console.error(`[FAIL] ${check.name}: ${check.error}`);
  }
}

const database = checks.find((check) => check.name === 'database');
if (database?.status === 'pass' && !database.details.transactionCapable) {
  console.warn('[WARN] database: standalone topology; multi-document transactions are unavailable');
}

if (checks.some((check) => check.status === 'fail')) process.exitCode = 1;
