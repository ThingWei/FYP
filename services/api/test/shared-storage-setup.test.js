import test from 'node:test';
import assert from 'node:assert/strict';
import dotenv from 'dotenv';
import { applyStorageSettings, validateStorageSettings, assertStorageRuntime, storageFailureReason,
  checkStorageSettings } from '../src/scripts/setupSharedStorage.js';

const settings = { STORAGE_MODE: 'supabase', SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SECRET_KEY: 'fake-test-secret-only', SUPABASE_STORAGE_BUCKET: 'renthub-files' };

test('storage setup changes only four fields, preserving Atlas, authentication and comments', () => {
  const original = '# Local setup\r\nMONGODB_URI="mongodb+srv://fake.invalid/renthub"\r\nAUTH_MODE=auth0\r\nLOCAL_JWT_SECRET=unchanged-test\r\nSTORAGE_MODE=local\r\n';
  const result = applyStorageSettings(original, settings);
  assert.equal(result.startsWith('# Local setup\r\n'), true);
  const values = dotenv.parse(result);
  assert.equal(values.MONGODB_URI, 'mongodb+srv://fake.invalid/renthub');
  assert.equal(values.AUTH_MODE, 'auth0');
  assert.equal(values.LOCAL_JWT_SECRET, 'unchanged-test');
  for (const [key, value] of Object.entries(settings)) assert.equal(values[key], value);
  assert.equal(applyStorageSettings(result, settings), result, 'reapplying must not duplicate fields');
});

test('storage setup refuses missing, duplicate and malformed settings without exposing credentials', () => {
  for (const invalid of [{ ...settings, SUPABASE_SECRET_KEY: '' }, { ...settings, STORAGE_MODE: 'local' },
    { ...settings, SUPABASE_URL: 'http://example.test' }, { ...settings, SUPABASE_SECRET_KEY: 'line\nbreak' },
    { ...settings, SUPABASE_STORAGE_BUCKET: '../other' }]) {
    assert.throws(() => validateStorageSettings(invalid), error => !error.message.includes('fake-test-secret'));
  }
  assert.throws(() => applyStorageSettings('STORAGE_MODE=local\nSTORAGE_MODE=supabase\n', settings), /duplicate_storage_setting/);
});

test('export-style assignments, Unicode and literal dollar signs round-trip without altering other values', () => {
  const original = 'export STORAGE_MODE=local\nDISPLAY_NAME="测试"\nUNCHANGED="a$b"';
  const result = applyStorageSettings(original, { ...settings, SUPABASE_SECRET_KEY: 'fake$test#key' });
  assert.equal(dotenv.parse(result).DISPLAY_NAME, '测试');
  assert.equal(dotenv.parse(result).UNCHANGED, 'a$b');
  assert.equal(dotenv.parse(result).SUPABASE_SECRET_KEY, 'fake$test#key');
});

test('Node 20 and missing native WebSocket are diagnosed before a network check', () => {
  const fakeRuntime = { nodeVersion: '20.18.0', webSocket: function () {}, fetchImpl: async () => {} };
  assert.throws(() => assertStorageRuntime(fakeRuntime), /unsupported_node_runtime/);
  assert.throws(() => assertStorageRuntime({ ...fakeRuntime, nodeVersion: '24.19.0', webSocket: null }), /unsupported_node_runtime/);
  assert.doesNotThrow(() => assertStorageRuntime({ ...fakeRuntime, nodeVersion: '22.22.0' }));
});

test('missing files, network and timeout failures have safe, specific guidance codes', () => {
  assert.equal(storageFailureReason({ code: 'ENOENT' }, 'read_transfer'), 'missing_transfer_file');
  assert.equal(storageFailureReason({ code: 'ENOENT' }, 'read_environment'), 'missing_api_env');
  assert.equal(storageFailureReason({ cause: { code: 'ENOTFOUND' } }, 'bucket_access'), 'bucket_network_failed');
  assert.equal(storageFailureReason({ originalError: { cause: { code: 'ECONNRESET' } } }, 'bucket_access'), 'bucket_network_failed');
  assert.equal(storageFailureReason({ name: 'TimeoutError' }, 'bucket_access'), 'bucket_timeout');
  assert.equal(storageFailureReason({ message: 'sensitive-key-or-url' }, 'bucket_access'), 'bucket_access_failed');
  assert.equal(storageFailureReason({ message: 'sensitive-key-or-url' }, 'save_settings'), 'setup_or_network_check_failed');
});

test('bucket response distinguishes a wrong server key from a missing bucket without a write', async () => {
  const originalFetch = globalThis.fetch;
  try {
    for (const [status, expected] of [[401, 'bucket_auth_failed'], [403, 'bucket_auth_failed'], [404, 'bucket_not_found']]) {
      globalThis.fetch = async () => new Response(JSON.stringify({ statusCode: String(status),
        error: 'Error', message: 'private response text not for diagnostics' }),
      { status, headers: { 'content-type': 'application/json' } });
      await assert.rejects(() => checkStorageSettings(settings), error => error.message === expected);
    }
  } finally { globalThis.fetch = originalFetch; }
});
