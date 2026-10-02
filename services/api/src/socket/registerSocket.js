import { createRemoteJWKSet, jwtVerify } from 'jose';
import { env } from '../config/env.js';
import {
  assertAccountAccess,
  identityFromPayload,
} from '../middleware/auth.js';
import { ThreadModel } from '../modules/communication/thread.model.js';
import { setSocketServer } from './eventBus.js';
import { localSessionService } from '../modules/user/localSession.service.js';

let jwks;

export function registerSocket(io) {
  setSocketServer(io);
  io.use(async (socket, next) => {
    try {
      if (env.authMode === 'mock') {
        const candidate = socket.handshake.auth?.userId;
        const authId =
          typeof candidate === 'string' && candidate.length <= 120
            ? candidate
            : 'u-dual';
        await assertAccountAccess({ authId });
        socket.data.userId = authId;
        return next();
      }
      const token = socket.handshake.auth?.token;
      if (!token) return next(new Error('Authentication required'));
      if (env.authMode === 'local') {
        const identity = await localSessionService.authenticateAccessToken(token);
        await assertAccountAccess(identity);
        socket.data.userId = identity.authId;
        socket.data.sessionId = identity.sessionId;
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
      const identity = identityFromPayload(payload);
      await assertAccountAccess(identity);
      socket.data.userId = identity.authId;
      return next();
    } catch {
      return next(new Error('Invalid access token'));
    }
  });
  io.on('connection', (socket) => {
    const userId = socket.data.userId;
    socket.join(`user:${userId}`);
    if (socket.data.sessionId) {
      socket.join(`session:${socket.data.sessionId}`);
    }
    socket.on('thread:join', async (threadId) => {
      if (
        typeof threadId !== 'string' ||
        !/^THR-[A-Z0-9-]+$/i.test(threadId)
      ) {
        return;
      }
      const thread = await ThreadModel.exists({
        publicId: threadId,
        participantIds: userId,
      });
      if (thread) socket.join(`thread:${threadId}`);
    });
  });
}

