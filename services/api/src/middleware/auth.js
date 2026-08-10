import { createRemoteJWKSet, jwtVerify } from 'jose';
import { env } from '../config/env.js';
import { AppError } from '../core/errors.js';

export async function authenticate(req, _res, next) {
  try {
    if (env.authMode === 'mock') {
      req.user = { id: req.header('x-user-id') ?? '000000000000000000000001', roles: (req.header('x-user-roles') ?? 'renter,owner').split(',') };
      return next();
    }
    const token = req.header('authorization')?.replace(/^Bearer /, '');
    if (!token) throw new AppError('Authentication required', 401, 'UNAUTHENTICATED');
    const jwks = createRemoteJWKSet(new URL(`${env.authIssuer}.well-known/jwks.json`));
    const { payload } = await jwtVerify(token, jwks, { issuer: env.authIssuer, audience: env.authAudience });
    req.user = { id: payload.sub, roles: payload['https://renthub/roles'] ?? [] };
    next();
  } catch (error) { next(error instanceof AppError ? error : new AppError('Invalid access token', 401, 'UNAUTHENTICATED')); }
}
export const authorize = (...roles) => (req, _res, next) => req.user?.roles?.some((r) => roles.includes(r)) ? next() : next(new AppError('Insufficient permission', 403, 'FORBIDDEN'));

