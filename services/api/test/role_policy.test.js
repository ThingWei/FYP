import test from 'node:test';
import assert from 'node:assert/strict';
import {
  classifyStoredRoles,
  normalizeTrustedIdentityRoles,
} from '../src/modules/user/rolePolicy.js';
import { UserModel } from '../src/modules/user/user.model.js';

test('normalizes every public identity to both marketplace roles', () => {
  for (const roles of [[], ['renter'], ['owner'], ['owner', 'renter']]) {
    assert.deepEqual(normalizeTrustedIdentityRoles(roles), ['renter', 'owner']);
  }
  assert.deepEqual(normalizeTrustedIdentityRoles(['admin']), ['admin']);
});

test('rejects contradictory administrator and marketplace claims', () => {
  assert.throws(
    () => normalizeTrustedIdentityRoles(['admin', 'renter']),
    (error) => error.code === 'CONTRADICTORY_ROLE_CLAIMS',
  );
});

test('classifies role migration inputs deterministically and idempotently', () => {
  assert.equal(classifyStoredRoles(['renter'], 'renter').category, 'legacy_renter');
  assert.equal(classifyStoredRoles(['owner'], 'owner').category, 'legacy_owner');
  const reordered = classifyStoredRoles(['owner', 'renter'], 'owner');
  assert.equal(reordered.category, 'marketplace_reordered');
  assert.deepEqual(reordered.roles, ['renter', 'owner']);
  assert.equal(
    classifyStoredRoles(reordered.roles, reordered.activeRole).category,
    'marketplace',
  );
  assert.equal(classifyStoredRoles(['admin'], 'admin').category, 'admin');
  assert.equal(
    classifyStoredRoles(['admin', 'owner'], 'admin').category,
    'mixed_admin',
  );
  assert.equal(classifyStoredRoles([], 'renter').category, 'invalid');
  assert.equal(
    classifyStoredRoles(['renter'], 'owner').category,
    'invalid',
  );
});

test('user schema accepts only dual marketplace or administrator role sets', () => {
  const common = {
    authId: 'schema-role-test',
    email: 'schema-role-test@renthub.my',
    displayName: 'Schema Role',
  };
  assert.equal(
    new UserModel({
      ...common,
      roles: ['renter', 'owner'],
      activeRole: 'owner',
    }).validateSync(),
    undefined,
  );
  assert.equal(
    new UserModel({
      ...common,
      roles: ['admin'],
      activeRole: 'admin',
    }).validateSync(),
    undefined,
  );
  assert.ok(
    new UserModel({
      ...common,
      roles: ['admin', 'renter'],
      activeRole: 'admin',
    }).validateSync(),
  );
});
