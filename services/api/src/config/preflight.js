import mongoose from 'mongoose';
import { readFile } from 'node:fs/promises';
import { applicationDefault } from 'firebase-admin/app';
import { connectDatabase, disconnectDatabase } from './database.js';
import { env, validateEnv } from './env.js';
import { storageAdapter } from '../integrations/storageAdapter.js';
import { assertBindingReady } from '../modules/user/identityBinding.js';

function normalizedIssuer(value) {
  return value.endsWith('/') ? value : `${value}/`;
}

// Never return credentials, tokens, file paths or SDK errors to the console.
export async function checkPush(config = env, {
  credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS,
  read = readFile,
  credential = applicationDefault,
} = {}) {
  if (config.fcmMode !== 'firebase') return { provider: 'disabled', skipped: true };
  if (!config.firebaseProjectId || config.firebaseProjectId === 'your-project-id') {
    throw new Error('Set FIREBASE_PROJECT_ID to the Android Firebase project ID');
  }
  if (credentialPath) {
    let account;
    try { account = JSON.parse(await read(credentialPath, 'utf8')); }
    catch { throw new Error('Firebase Admin credential file cannot be read as JSON'); }
    if (account.type !== 'service_account' || !account.client_email || !account.private_key) {
      throw new Error('Use a Firebase Admin service-account JSON, not Android google-services.json');
    }
    if (account.project_id !== config.firebaseProjectId) {
      throw new Error('Firebase Admin credentials and FIREBASE_PROJECT_ID must use the same project');
    }
  }
  try { await credential().getAccessToken(); }
  catch { throw new Error('Firebase Admin authentication failed. Configure GOOGLE_APPLICATION_CREDENTIALS with a valid service-account file, then restart the API'); }
  return { provider: 'firebase', credentialAuthenticated: true, deliveryTested: false };
}

export async function checkAuth0(config = env, fetchImpl = fetch) {
  if (!['auth0', 'hybrid'].includes(config.authMode)) {
    return { provider: config.authMode, skipped: true };
  }
  const issuer = normalizedIssuer(config.authIssuer);
  const discoveryUrl = new URL('.well-known/openid-configuration', issuer);
  const discoveryResponse = await fetchImpl(discoveryUrl, {
    signal: AbortSignal.timeout(10_000),
  });
  if (!discoveryResponse.ok) {
    throw new Error(`Auth0 discovery returned HTTP ${discoveryResponse.status}`);
  }
  const discovery = await discoveryResponse.json();
  if (normalizedIssuer(discovery.issuer ?? '') !== issuer) {
    throw new Error('Auth0 discovery issuer does not match AUTH0_ISSUER_BASE_URL');
  }
  if (!discovery.jwks_uri) throw new Error('Auth0 discovery did not include jwks_uri');
  const keysResponse = await fetchImpl(discovery.jwks_uri, {
    signal: AbortSignal.timeout(10_000),
  });
  if (!keysResponse.ok) {
    throw new Error(`Auth0 JWKS returned HTTP ${keysResponse.status}`);
  }
  const keys = await keysResponse.json();
  if (!Array.isArray(keys.keys) || keys.keys.length === 0) {
    throw new Error('Auth0 JWKS does not contain signing keys');
  }
  return { provider: 'auth0', issuer, signingKeys: keys.keys.length };
}

export async function inspectDatabase(connection = mongoose.connection) {
  const database = connection.db;
  await database.command({ ping: 1 });
  const hello = await database.command({ hello: 1 });
  const transactionCapable = Boolean(
    hello.setName || hello.msg === 'isdbgrid',
  );
  return {
    provider: hello.msg === 'isdbgrid' ? 'mongodb-router' : 'mongodb',
    database: database.databaseName,
    topology: hello.setName
      ? `replica-set:${hello.setName}`
      : hello.msg === 'isdbgrid'
        ? 'sharded'
        : 'standalone',
    transactionCapable,
  };
}

async function result(name, operation) {
  try {
    return { name, status: 'pass', details: await operation() };
  } catch (error) {
    return { name, status: 'fail', error: error.message };
  }
}

export async function runPreflight({
  config = env,
  requireProduction = false,
  writeProbe = false,
} = {}) {
  const checks = [];
  checks.push(
    await result('configuration', async () => {
      validateEnv(config);
      if (requireProduction && config.nodeEnv !== 'production') {
        throw new Error('NODE_ENV=production is required for this preflight');
      }
      return {
        environment: config.nodeEnv,
        auth: config.authMode,
        storage: config.storageMode,
        corsOrigins: config.corsOrigins?.length ?? 0,
      };
    }),
  );
  if (checks[0].status === 'fail') return checks;

  checks.push(
    await result('database', async () => {
      await connectDatabase(config.mongoUri);
      return inspectDatabase();
    }),
  );
  checks.push(await result('authentication', () => checkAuth0(config)));
  checks.push(await result('push_notifications', () => checkPush(config)));
  if (checks.find(check => check.name === 'database')?.status === 'pass') {
    checks.push(await result('mykad_identity_binding', () => assertBindingReady(config)));
  }
  checks.push(
    await result('storage', () => storageAdapter.verify({ writeProbe })),
  );
  await disconnectDatabase();
  return checks;
}
