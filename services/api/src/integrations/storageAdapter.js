import { createHash } from 'node:crypto';
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { env } from '../config/env.js';

let firebaseBucket;

function bucket() {
  if (firebaseBucket) return firebaseBucket;
  const app = getApps()[0] ?? initializeApp({
    credential: applicationDefault(),
    storageBucket: env.firebaseStorageBucket,
  });
  firebaseBucket = getStorage(app).bucket(env.firebaseStorageBucket);
  return firebaseBucket;
}

function localPath(storagePath) {
  const root = path.resolve(env.uploadDirectory);
  const resolved = path.resolve(root, storagePath);
  if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) {
    throw new Error('Invalid storage path');
  }
  return resolved;
}

export const storageAdapter = {
  checksum(buffer) {
    return createHash('sha256').update(buffer).digest('hex');
  },

  async upload({ storagePath, buffer, contentType, isPublic }) {
    if (env.storageMode === 'firebase') {
      await bucket().file(storagePath).save(buffer, {
        resumable: false,
        metadata: {
          contentType,
          cacheControl: isPublic ? 'public,max-age=31536000,immutable' : 'private,no-store',
        },
      });
      return { provider: 'firebase', storagePath };
    }
    const target = localPath(storagePath);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, buffer, { flag: 'wx' });
    return { provider: 'local', storagePath };
  },

  async download(storagePath) {
    if (env.storageMode === 'firebase') {
      const [buffer] = await bucket().file(storagePath).download();
      return buffer;
    }
    return readFile(localPath(storagePath));
  },

  async delete(storagePath) {
    if (env.storageMode === 'firebase') {
      await bucket().file(storagePath).delete({ ignoreNotFound: true });
      return;
    }
    await unlink(localPath(storagePath)).catch((error) => {
      if (error.code !== 'ENOENT') throw error;
    });
  },
};
