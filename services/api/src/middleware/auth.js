import { createRemoteJWKSet, jwtVerify } from 'jose';
import { env } from '../config/env.js';
import { AppError } from '../core/errors.js';

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

export async function authenticate(req, _res, next) {
  try {
    if (env.authMode === 'mock') {
      req.user = mockIdentity(req);
      return next();
    }
    const token = req.header('authorization')?.replace(/^Bearer /, '');
    if (!token) throw new AppError('Authentication required', 401, 'UNAUTHENTICATED');
    const issuer = env.authIssuer.endsWith('/')
      ? env.authIssuer
      : `${env.authIssuer}/`;
    jwks ??= createRemoteJWKSet(new URL('.well-known/jwks.json', issuer));
    const { payload } = await jwtVerify(token, jwks, {
      issuer,
      audience: env.authAudience,
    });
    req.user = identityFromPayload(payload);
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

