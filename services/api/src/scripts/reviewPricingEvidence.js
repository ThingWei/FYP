// Explicit read-only audit + frozen evaluation. Never collects, fits or deploys.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { access, readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { main as audit } from './auditPricingRealWorld.js';

const apiRoot = fileURLToPath(new URL('../..', import.meta.url));
const aiRoot = path.resolve(apiRoot, '../ai');
const execute = promisify(execFile);
export function parseReviewOptions(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (!['--run-id', '--cutoff'].includes(key) || options[key] !== undefined) throw new Error('Use --run-id ID [--cutoff ISO_TIME]');
    const value = args[++i];
    if (!value || value.startsWith('-')) throw new Error('Missing option value');
    options[key] = value;
  }
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(options['--run-id'] ?? '') || /\s/.test(options['--run-id'])) throw new Error('Choose a safe new run ID');
  if (options['--cutoff'] && (!/^\d{4}-\d{2}-\d{2}(?:T.*)?$/.test(options['--cutoff']) ||
      !Number.isFinite(+new Date(options['--cutoff'])) ||
      new Date(options['--cutoff'].slice(0, 10) + 'T00:00:00Z').toISOString().slice(0, 10) !== options['--cutoff'].slice(0, 10))) throw new Error('Invalid cutoff');
  return { runId: options['--run-id'], cutoff: options['--cutoff'] };
}

async function assertAbsent(target) {
  try { await access(target); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
  throw new Error('Run output already exists; choose a new run ID');
}

export async function reviewEvidence(options, dependencies = {}) {
  parseReviewOptions(['--run-id', options.runId, ...(options.cutoff ? ['--cutoff', options.cutoff] : [])]);
  // Roots/dependencies are injectable only by local tests, never CLI arguments.
  const api = dependencies.apiRoot ?? apiRoot, ai = dependencies.aiRoot ?? aiRoot;
  const destination = path.join(api, '.data/evidence', options.runId);
  const reportPath = path.join(ai, '.data/evaluation', options.runId + '.json');
  await assertAbsent(destination);
  await assertAbsent(reportPath);
  const python = path.join(ai, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
  await access(python); // Fail before any audit output when the local environment is missing.
  await (dependencies.audit ?? audit)(['--output', destination]);
  await (dependencies.execute ?? execute)(python, ['-m', 'app.training.evaluate_pricing',
    '--real-export', path.join(destination, 'observations.json'), '--mode', 'deployed', '--report', reportPath,
    ...(options.cutoff ? ['--cutoff', options.cutoff] : [])],
  { cwd: ai, timeout: 120000, maxBuffer: 2_097_152, windowsHide: true });
  const report = JSON.parse(await readFile(reportPath, 'utf8'));
  if (report.modelMode !== 'deployed' || report.artifactWritten !== false || report.candidate !== null ||
      report.artifactUnchanged !== true) throw new Error('Frozen evaluation contract was not satisfied');
  return { databaseWrites: 0, modelDeployed: false, status: report.status,
    evidenceReadiness: report.evidenceReadiness, predictionCoverage: report.predictionCoverage };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  Promise.resolve().then(() => reviewEvidence(parseReviewOptions(process.argv.slice(2)))).then((result) => console.log(JSON.stringify(result)))
    .catch(() => { console.error('Pricing evidence review failed; check arguments, local environment and NEW output paths. No collection, training or deployment requested.'); process.exitCode = 1; });
}
