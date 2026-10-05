import { AppError } from '../../core/errors.js';

export const MARKETPLACE_ROLES = Object.freeze(['renter', 'owner']);
export const ADMIN_ROLES = Object.freeze(['admin']);
export const KNOWN_ROLES = Object.freeze([...MARKETPLACE_ROLES, ...ADMIN_ROLES]);

const uniqueKnownRoles = (roles) => [
  ...new Set(
    (Array.isArray(roles) ? roles : [])
      .map((role) => String(role).trim().toLowerCase())
      .filter((role) => KNOWN_ROLES.includes(role)),
  ),
];

export function classifyStoredRoles(roles, activeRole) {
  const normalized = uniqueKnownRoles(roles);
  const rawCount = Array.isArray(roles) ? roles.length : 0;
  const hasUnknown = rawCount !== normalized.length;
  const hasAdmin = normalized.includes('admin');
  const publicRoles = normalized.filter((role) => MARKETPLACE_ROLES.includes(role));

  if (hasAdmin && publicRoles.length) {
    return { category: 'mixed_admin', roles: normalized, activeRole };
  }
  if (hasUnknown || normalized.length === 0) {
    return { category: 'invalid', roles: normalized, activeRole };
  }
  if (hasAdmin) {
    return activeRole === 'admin'
      ? { category: 'admin', roles: ['admin'], activeRole: 'admin' }
      : { category: 'invalid', roles: normalized, activeRole };
  }
  if (!MARKETPLACE_ROLES.includes(activeRole)) {
    return { category: 'invalid', roles: normalized, activeRole };
  }
  if (publicRoles.length === 1) {
    if (activeRole !== publicRoles[0]) {
      return { category: 'invalid', roles: normalized, activeRole };
    }
    return {
      category: `legacy_${publicRoles[0]}`,
      roles: [...MARKETPLACE_ROLES],
      activeRole,
    };
  }
  return {
    category:
      normalized[0] === MARKETPLACE_ROLES[0] &&
      normalized[1] === MARKETPLACE_ROLES[1]
        ? 'marketplace'
        : 'marketplace_reordered',
    roles: [...MARKETPLACE_ROLES],
    activeRole,
  };
}

export function normalizeStoredUserRoles(roles, activeRole) {
  const result = classifyStoredRoles(roles, activeRole);
  if (['mixed_admin', 'invalid'].includes(result.category)) {
    throw new AppError(
      'This account has an invalid role configuration. Contact support.',
      403,
      'ROLE_CONFIGURATION_INVALID',
    );
  }
  return { roles: result.roles, activeRole: result.activeRole };
}

export function normalizeTrustedIdentityRoles(roles) {
  const normalized = uniqueKnownRoles(roles);
  const hasAdmin = normalized.includes('admin');
  const hasMarketplace = normalized.some((role) =>
    MARKETPLACE_ROLES.includes(role),
  );
  if (hasAdmin && hasMarketplace) {
    console.warn(
      JSON.stringify({
        type: 'security',
        event: 'contradictory_role_claims',
        roles: normalized,
      }),
    );
    throw new AppError(
      'The access token contains contradictory role claims.',
      403,
      'CONTRADICTORY_ROLE_CLAIMS',
    );
  }
  return hasAdmin ? ['admin'] : [...MARKETPLACE_ROLES];
}

export const isMarketplaceRole = (role) => MARKETPLACE_ROLES.includes(role);
