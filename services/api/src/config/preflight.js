import mongoose from 'mongoose';
import { connectDatabase, disconnectDatabase } from './database.js';
import { env, validateEnv } from './env.js';
import { storageAdapter } from '../integrations/storageAdapter.js';

function normalizedIssuer(value) {
  return value.endsWith('/') ? value : `${value}/`;
}

export async function checkAuth0(config = env, fetchImpl = fetch) {
  if (config.authMode !== 'auth0') {
    return { provider: 'mock', skipped: true };
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
  checks.push(
    await result('storage', () => storageAdapter.verify({ writeProbe })),
  );
  await disconnectDatabase();
  return checks;
}
