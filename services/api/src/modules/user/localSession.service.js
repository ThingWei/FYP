import {
  createHash,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { AppError } from '../../core/errors.js';
import { env } from '../../config/env.js';
import { UserModel } from './user.model.js';
import { LocalSessionModel } from './localSession.model.js';

const issuer = 'renthub-local';
const audience = 'renthub-app';

function secretKey() {
  return new TextEncoder().encode(env.localJwtSecret);
}

function refreshHash(token) {
  return createHash('sha256').update(token).digest();
}

function refreshToken(publicId, secret = randomBytes(32).toString('base64url')) {
  return `${publicId}.${secret}`;
}

function parseRefreshToken(token) {
  if (typeof token !== 'string') return null;
  const separator = token.indexOf('.');
  if (separator < 1 || separator === token.length - 1) return null;
  return { publicId: token.slice(0, separator), token };
}

function refreshMatches(token, storedHex) {
  const actual = refreshHash(token);
  const expected = Buffer.from(storedHex, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function invalidSession() {
  return new AppError(
    'Your session is invalid or has expired. Sign in again.',
    401,
    'INVALID_SESSION',
  );
}

function metadataValues(metadata = {}) {
  return {
    userAgent: String(metadata.userAgent ?? '').slice(0, 500),
    ip: String(metadata.ip ?? '').slice(0, 120),
  };
}

async function accessToken(user, sessionId) {
  const expiresAt = new Date(
    Date.now() + env.localAccessTokenMinutes * 60 * 1000,
  );
  const token = await new SignJWT({
    sid: sessionId,
    email: user.email,
    name: user.displayName,
    roles: user.roles,
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(user.authId)
    .setIssuer(issuer)
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(secretKey());
  return { token, expiresAt };
}

async function response(user, session, token) {
  const access = await accessToken(user, session.publicId);
  return {
    user,
    session: {
      accessToken: access.token,
      refreshToken: token,
      accessTokenExpiresAt: access.expiresAt,
      refreshTokenExpiresAt: session.expiresAt,
    },
  };
}

export const localSessionService = {
  async create(user, metadata) {
    const publicId = randomUUID();
    const token = refreshToken(publicId);
    const values = metadataValues(metadata);
    const session = await LocalSessionModel.create({
      publicId,
      userId: user._id,
      refreshTokenHash: refreshHash(token).toString('hex'),
      expiresAt: new Date(
        Date.now() + env.localRefreshTokenDays * 24 * 60 * 60 * 1000,
      ),
      userAgent: values.userAgent,
      createdIp: values.ip,
      lastIp: values.ip,
      lastUsedAt: new Date(),
    });
    return response(user, session, token);
  },

  async refresh(token, metadata) {
    const parsed = parseRefreshToken(token);
    if (!parsed) throw invalidSession();
    const session = await LocalSessionModel.findOne({
      publicId: parsed.publicId,
      revokedAt: null,
      expiresAt: { $gt: new Date() },
    }).select('+refreshTokenHash');
    if (!session) throw invalidSession();
    if (!refreshMatches(parsed.token, session.refreshTokenHash)) {
      session.revokedAt = new Date();
      await session.save();
      throw invalidSession();
    }
    const user = await UserModel.findById(session.userId);
    if (!user || user.accountStatus !== 'active') {
      session.revokedAt = new Date();
      await session.save();
      throw invalidSession();
    }
    const values = metadataValues(metadata);
    const nextToken = refreshToken(session.publicId);
    session.refreshTokenHash = refreshHash(nextToken).toString('hex');
    session.expiresAt = new Date(
      Date.now() + env.localRefreshTokenDays * 24 * 60 * 60 * 1000,
    );
    session.lastUsedAt = new Date();
    session.lastIp = values.ip;
    if (values.userAgent) session.userAgent = values.userAgent;
    await session.save();
    return response(user, session, nextToken);
  },

  async authenticateAccessToken(token) {
    let payload;
    try {
      ({ payload } = await jwtVerify(token, secretKey(), {
        algorithms: ['HS256'],
        issuer,
        audience,
      }));
    } catch {
      throw invalidSession();
    }
    if (typeof payload.sub !== 'string' || typeof payload.sid !== 'string') {
      throw invalidSession();
    }
    const session = await LocalSessionModel.findOne({
      publicId: payload.sid,
      revokedAt: null,
      expiresAt: { $gt: new Date() },
    }).lean();
    if (!session) throw invalidSession();
    const user = await UserModel.findOne({
      _id: session.userId,
      authId: payload.sub,
    }).lean();
    if (!user) throw invalidSession();
    return {
      id: user.authId,
      authId: user.authId,
      email: user.email,
      displayName: user.displayName,
      roles: user.roles,
      issuedAt:
        typeof payload.iat === 'number'
          ? new Date(payload.iat * 1000)
          : undefined,
      sessionId: session.publicId,
      localSessionUserId: session.userId,
    };
  },

  revoke(sessionId) {
    if (!sessionId) return Promise.resolve();
    return LocalSessionModel.updateOne(
      { publicId: sessionId, revokedAt: null },
      { revokedAt: new Date() },
    );
  },

  revokeAllForUser(userId) {
    return LocalSessionModel.updateMany(
      { userId, revokedAt: null },
      { revokedAt: new Date() },
    );
  },
};
