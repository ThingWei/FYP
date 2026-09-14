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

test('rejects mock authentication in production', () => {
  assert.throws(
    () => validateEnv({ ...valid, nodeEnv: 'production' }),
    /AUTH_MODE=mock is not allowed in production/,
  );
});
