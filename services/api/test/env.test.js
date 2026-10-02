import test from 'node:test';
import assert from 'node:assert/strict';
import { validateEnv } from '../src/config/env.js';

const valid = {
  port: 3000,
  mongoUri: 'mongodb://localhost:27017/renthub',
  authMode: 'mock',
};

test('accepts valid mock-auth environment configuration', () => {
  assert.equal(validateEnv(valid), valid);
});

test('requires Auth0 settings when Auth0 mode is enabled', () => {
  assert.throws(
    () => validateEnv({ ...valid, authMode: 'auth0' }),
    /AUTH0_ISSUER_BASE_URL is required/,
  );
});

test('requires a strong signing secret for local authentication', () => {
  assert.throws(
    () => validateEnv({ ...valid, authMode: 'local', localJwtSecret: 'short' }),
    /LOCAL_JWT_SECRET must contain at least 32 characters/,
  );
  const local = {
    ...valid,
    authMode: 'local',
    localJwtSecret: 'a-local-jwt-secret-with-32-characters',
  };
  assert.equal(validateEnv(local), local);
});

test('rejects mock authentication in production', () => {
  assert.throws(
    () => validateEnv({ ...valid, nodeEnv: 'production' }),
    /AUTH_MODE=mock is not allowed in production/,
  );
});

test('requires Supabase server settings in Supabase storage mode', () => {
  assert.throws(
    () => validateEnv({ ...valid, storageMode: 'supabase' }),
    /SUPABASE_URL is required/,
  );

  const supabase = {
    ...valid,
    storageMode: 'supabase',
    supabaseUrl: 'https://project-ref.supabase.co',
    supabaseSecretKey: 'server-only-secret',
    supabaseStorageBucket: 'renthub-files',
  };
  assert.equal(validateEnv(supabase), supabase);
});

test('accepts Supabase as production storage', () => {
  const production = {
    ...valid,
    nodeEnv: 'production',
    authMode: 'local',
    localJwtSecret: 'a-production-jwt-secret-with-32-characters',
    storageMode: 'supabase',
    supabaseUrl: 'https://project-ref.supabase.co',
    supabaseSecretKey: 'server-only-secret',
    supabaseStorageBucket: 'renthub-files',
  };
  assert.equal(validateEnv(production), production);
});

test('rejects an OpenStreetMap request interval below one second', () => {
  assert.throws(
    () =>
      validateEnv({
        ...valid,
        mapsMode: 'openstreetmap',
        openStreetMapNominatimUrl: 'https://nominatim.openstreetmap.org',
        openStreetMapUserAgent: 'RentHub/1.0',
        openStreetMapMinIntervalMs: 500,
      }),
    /OPENSTREETMAP_MIN_INTERVAL_MS must be an integer of at least 1000/,
  );
});
