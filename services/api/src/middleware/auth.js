import { createRemoteJWKSet, jwtVerify } from 'jose';
import { env } from '../config/env.js';
import { AppError } from '../core/errors.js';
import { UserModel } from '../modules/user/user.model.js';
import { localSessionService } from '../modules/user/localSession.service.js';

let jwks;

export function rolesFromClaim(value) {
  const candidates = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.split(/[ ,]+/)
      : [];
  return [...new Set(candidates.map((role) => role.trim()).filter(Boolean))];
}

export function identityFromPayload(payload) {
  if (typeof payload.sub !== 'string' || !payload.sub) {
    throw new AppError('Invalid access token subject', 401, 'UNAUTHENTICATED');
  }
  return {
    id: payload.sub,
    authId: payload.sub,
    email:
      typeof payload[env.authEmailClaim] === 'string'
        ? payload[env.authEmailClaim]
        : undefined,
    displayName:
      typeof payload[env.authNameClaim] === 'string'
        ? payload[env.authNameClaim]
        : undefined,
    roles: rolesFromClaim(payload[env.authRolesClaim]),
    issuedAt:
      typeof payload.iat === 'number' ? new Date(payload.iat * 1000) : undefined,
  };
}

function mockIdentity(req) {
  const authId = req.header('x-user-id') ?? 'u-dual';
  return {
    id: authId,
    authId,
    email: req.header('x-user-email') ?? 'demo@renthub.my',
    displayName: req.header('x-user-name') ?? 'Nur Izzati',
    roles: (req.header('x-user-roles') ?? 'renter,owner')
      .split(',')
      .map((role) => role.trim())
      .filter(Boolean),
  };
}

export async function assertAccountAccess(identity) {
  const user = await UserModel.findOne({ authId: identity.authId })
    .select('accountStatus accessRevokedAt')
    .lean();
  // A profile does not exist until the first /users/session call.
  if (!user) return;
  if (user.accountStatus !== 'active') {
    throw new AppError(
      `Account is ${user.accountStatus}`,
      403,
      'ACCOUNT_RESTRICTED',
    );
  }
  if (
    identity.issuedAt &&
    user.accessRevokedAt &&
    // JWT iat has one-second precision. Allow a genuinely new token minted in
    // the revocation second instead of trapping an immediate re-login.
    identity.issuedAt.getTime() + 1000 <= user.accessRevokedAt.getTime()
  ) {
    throw new AppError(
      'This session has been revoked. Sign in again.',
      401,
      'SESSION_REVOKED',
    );
  }
}

export async function authenticate(req, _res, next) {
  try {
    if (env.authMode === 'mock') {
      req.user = mockIdentity(req);
      await assertAccountAccess(req.user);
      return next();
    }
    const token = req.header('authorization')?.replace(/^Bearer /, '');
    if (!token) throw new AppError('Authentication required', 401, 'UNAUTHENTICATED');
    if (env.authMode === 'local') {
      req.user = await localSessionService.authenticateAccessToken(token);
      await assertAccountAccess(req.user);
      return next();
    }
    const issuer = env.authIssuer.endsWith('/')
      ? env.authIssuer
      : `${env.authIssuer}/`;
    jwks ??= createRemoteJWKSet(new URL('.well-known/jwks.json', issuer));
    const { payload } = await jwtVerify(token, jwks, {
      issuer,
      audience: env.authAudience,
    });
    req.user = identityFromPayload(payload);
    await assertAccountAccess(req.user);
    next();
  } catch (error) {
    next(
      error instanceof AppError
        ? error
        : new AppError('Invalid access token', 401, 'UNAUTHENTICATED'),
    );
  }
}

export const authorize = (...roles) => (req, _res, next) =>
  req.user?.roles?.some((role) => roles.includes(role))
    ? next()
    : next(new AppError('Insufficient permission', 403, 'FORBIDDEN'));

