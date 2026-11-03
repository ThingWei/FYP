// Storage-only setup for a second laptop; never prints server credentials.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

const keys = ['STORAGE_MODE', 'SUPABASE_URL', 'SUPABASE_SECRET_KEY', 'SUPABASE_STORAGE_BUCKET'];
const guidance = {
  unsupported_node_runtime: 'Install Node.js 24 LTS (or supported Node.js 22+), reopen PowerShell, verify node -v, then rerun. No settings were saved.',
  missing_transfer_file: 'Copy/extract the whole private storage-transfer folder, including storage.env, into services/api/.data/.',
  missing_api_env: 'The services/api/.env file is missing. Restore your private API environment before applying storage settings.',
  run_from_services_api: 'Open PowerShell in the RentHub services/api folder and rerun.',
  bucket_auth_failed: 'Use the original Supabase project server secret, not a browser/publishable key. Keep it private.',
  bucket_not_found: 'Check that the Supabase project and bucket name match the original laptop.',
  bucket_network_failed: 'Check internet, DNS and HTTPS access to your Supabase project, then rerun. Do not disable TLS verification.',
  bucket_timeout: 'The read-only bucket check timed out. Check the connection and retry.',
};

export function assertStorageRuntime({ nodeVersion = process.versions.node,
  webSocket = globalThis.WebSocket, fetchImpl = globalThis.fetch } = {}) {
  if (Number(nodeVersion.split('.')[0]) < 22 || typeof webSocket !== 'function' || typeof fetchImpl !== 'function') {
    throw new Error('unsupported_node_runtime');
  }
}

export function storageFailureReason(error, phase) {
  const safeCodes = ['incomplete_storage_settings', 'invalid_storage_project', 'invalid_bucket_name',
    'duplicate_storage_setting', 'unrelated_setting_changed', 'storage_setting_roundtrip_failed',
    'bucket_access_failed', 'invalid_arguments', ...Object.keys(guidance)];
  if (safeCodes.includes(error.message)) return error.message;
  if (error.code === 'ENOENT') {
    if (phase === 'read_transfer') return 'missing_transfer_file';
    if (phase === 'read_environment') return 'missing_api_env';
    if (phase === 'working_directory') return 'run_from_services_api';
  }
  const causes = [error, error.cause, error.originalError, error.originalError?.cause].filter(Boolean);
  if (causes.some(item => item.name === 'TimeoutError' || item.name === 'AbortError'
    || ['ETIMEDOUT', 'UND_ERR_CONNECT_TIMEOUT'].includes(item.code))) return 'bucket_timeout';
  if (causes.some(item => ['ENOTFOUND', 'EAI_AGAIN', 'ECONNREFUSED', 'ECONNRESET',
    'ENETUNREACH', 'CERT_HAS_EXPIRED', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE'].includes(item.code)
    || item.message === 'fetch failed')) return 'bucket_network_failed';
  return phase === 'bucket_access' ? 'bucket_access_failed' : 'setup_or_network_check_failed';
}

export function validateStorageSettings(settings) {
  if (keys.some(key => typeof settings[key] !== 'string' || !settings[key].trim()
    || /[\r\n]/.test(settings[key])) || settings.STORAGE_MODE !== 'supabase') {
    throw new Error('incomplete_storage_settings');
  }
  let url;
  try { url = new URL(settings.SUPABASE_URL); } catch { throw new Error('invalid_storage_project'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
    throw new Error('invalid_storage_project');
  }
  if (!/^[A-Za-z0-9._-]+$/.test(settings.SUPABASE_STORAGE_BUCKET)) throw new Error('invalid_bucket_name');
}

export function applyStorageSettings(original, settings) {
  validateStorageSettings(settings);
  let updated = original;
  const newline = original.includes('\r\n') ? '\r\n' : '\n';
  for (const key of keys) {
    const pattern = new RegExp(`^[ \\t]*(?:export[ \\t]+)?${key}[ \\t]*=[^\\r\\n]*`, 'gm');
    const matches = updated.match(pattern) ?? [];
    if (matches.length > 1) throw new Error('duplicate_storage_setting');
    const line = `${key}=${JSON.stringify(settings[key])}`;
    updated = matches.length ? updated.replace(pattern, () => line)
      : `${updated}${updated.endsWith('\n') || !updated ? '' : newline}${line}${newline}`;
  }
  const before = dotenv.parse(original), after = dotenv.parse(updated);
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (!keys.includes(key) && before[key] !== after[key]) throw new Error('unrelated_setting_changed');
  }
  if (keys.some(key => after[key] !== settings[key])) throw new Error('storage_setting_roundtrip_failed');
  return updated;
}

export async function checkStorageSettings(settings) {
  assertStorageRuntime();
  validateStorageSettings(settings);
  const client = createClient(settings.SUPABASE_URL, settings.SUPABASE_SECRET_KEY, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { fetch: (url, options = {}) => fetch(url, { ...options, signal: AbortSignal.timeout(15000) }) },
  });
  const result = await client.storage.getBucket(settings.SUPABASE_STORAGE_BUCKET);
  if (result.error || !result.data) {
    const status = Number(result.error?.statusCode ?? result.error?.status);
    if ([401, 403].includes(status)) throw new Error('bucket_auth_failed');
    if (status === 404) throw new Error('bucket_not_found');
    const reason = storageFailureReason(result.error ?? new Error(), 'bucket_access');
    throw new Error(reason);
  }
}

async function main() {
  let saved = false;
  let phase = 'arguments';
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => !['--apply', '--check'].includes(arg)) || args.length > 1) throw new Error('invalid_arguments');
    phase = 'runtime';
    assertStorageRuntime();
    const apiRoot = process.cwd();
    phase = 'working_directory';
    const packageInfo = JSON.parse(await readFile(join(apiRoot, 'package.json')));
    if (packageInfo.name !== 'renthub-api') throw new Error('run_from_services_api');
    const envPath = join(apiRoot, '.env');
    phase = 'read_environment';
    const original = await readFile(envPath, 'utf8');
    phase = 'read_transfer';
    const proposed = args.includes('--apply')
      ? dotenv.parse(await readFile(join(apiRoot, '.data/storage-transfer/storage.env')))
      : dotenv.parse(original);
    phase = 'validate_settings';
    const updated = applyStorageSettings(original, proposed);
    phase = 'bucket_access';
    await checkStorageSettings(proposed); // Read-only; fail before replacing settings.
    if (args.includes('--apply')) {
      phase = 'save_settings';
      const backupDir = join(apiRoot, '.data/backups');
      await mkdir(backupDir, { recursive: true });
      await writeFile(join(backupDir, `before-shared-storage-${Date.now()}.env`), original, { flag: 'wx', mode: 0o600 });
      await writeFile(envPath, updated);
      saved = true;
    }
    const inheritedOverrides = keys.filter(key => process.env[key] !== undefined && process.env[key] !== proposed[key]);
    console.log(JSON.stringify({ status: 'passed', bucketAccessible: true, storageSettingsSaved: saved,
      databaseAndOtherSettingsPreserved: true, inheritedOverrides,
      nextStep: saved ? 'Restart the API. If inheritedOverrides is nonempty, use a fresh terminal with the correct environment.' : 'Bucket access works from this laptop.' }));
  } catch (error) {
    const reason = storageFailureReason(error, phase);
    console.log(JSON.stringify({ status: 'failed', storageSettingsSaved: saved, phase,
      nodeVersion: process.versions.node, reason,
      guidance: guidance[reason] ?? 'Run from services/api; check the private setup file and internet connection. Do not share secrets.' }));
    process.exitCode = 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
