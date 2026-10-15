import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAuth0, inspectDatabase, checkPush } from '../src/config/preflight.js';

test('push preflight distinguishes disabled, Android client config, wrong project and server credentials', async () => {
  assert.equal((await checkPush({ fcmMode: 'disabled' })).skipped, true);
  const config = { fcmMode: 'firebase', firebaseProjectId: 'test-project' };
  const fixture = { type: 'service_account', project_id: 'test-project', client_email: 'test@example.invalid', private_key: 'not-a-real-key' };
  const options = (row) => ({ credentialPath: 'fixture.json', read: async () => JSON.stringify(row),
    credential: () => ({ getAccessToken: async () => ({ access_token: 'NEVER-PRINT' }) }) });
  await assert.rejects(checkPush(config, options({ project_info: {} })), /not Android/);
  await assert.rejects(checkPush(config, options({ ...fixture, project_id: 'other' })), /same project/);
  const result = await checkPush(config, options(fixture));
  assert.deepEqual(result, { provider: 'firebase', credentialAuthenticated: true, deliveryTested: false });
  assert.ok(!JSON.stringify(result).includes('NEVER-PRINT'));
  await assert.rejects(checkPush(config, { ...options(fixture), credential: () => { throw new Error('PRIVATE-DATA'); } }),
    (error) => !error.message.includes('PRIVATE-DATA') && error.message.includes('authentication failed'));
});

const authConfig = {
  authMode: 'auth0',
  authIssuer: 'https://tenant.example/',
};

test('Auth0 preflight verifies discovery issuer and signing keys', async () => {
  const requests = [];
  const fakeFetch = async (url) => {
    requests.push(url.toString());
    if (requests.length === 1) {
      return {
        ok: true,
        json: async () => ({
          issuer: authConfig.authIssuer,
          jwks_uri: 'https://tenant.example/.well-known/jwks.json',
        }),
      };
    }
    return { ok: true, json: async () => ({ keys: [{ kid: 'key-1' }] }) };
  };

  const result = await checkAuth0(authConfig, fakeFetch);
  assert.equal(result.provider, 'auth0');
  assert.equal(result.signingKeys, 1);
  assert.equal(requests.length, 2);
});

test('Auth0 preflight rejects a mismatched discovery issuer', async () => {
  await assert.rejects(
    checkAuth0(authConfig, async () => ({
      ok: true,
      json: async () => ({
        issuer: 'https://different.example/',
        jwks_uri: 'https://different.example/jwks.json',
      }),
    })),
    /issuer does not match/,
  );
});

test('database preflight reports transaction-capable topology', async () => {
  const commands = [];
  const connection = {
    db: {
      databaseName: 'renthub-e2e',
      command: async (command) => {
        commands.push(command);
        return command.hello ? { setName: 'atlas-replica' } : { ok: 1 };
      },
    },
  };
  const result = await inspectDatabase(connection);
  assert.equal(result.transactionCapable, true);
  assert.equal(result.topology, 'replica-set:atlas-replica');
  assert.deepEqual(commands, [{ ping: 1 }, { hello: 1 }]);
});
