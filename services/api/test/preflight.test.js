import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAuth0, inspectDatabase } from '../src/config/preflight.js';

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
