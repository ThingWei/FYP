import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { createClient } from '@supabase/supabase-js';
import { env } from '../config/env.js';

let firebaseBucket;
let supabaseClient;

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

function supabase() {
  if (supabaseClient) return supabaseClient;
  supabaseClient = createClient(env.supabaseUrl, env.supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
  return supabaseClient;
}

function supabaseBucket() {
  return supabase().storage.from(env.supabaseStorageBucket);
}

function assertSupabaseResult(result, action) {
  if (result.error) {
    const status = result.error.statusCode ?? result.error.status;
    const suffix = status ? ` (HTTP ${status})` : '';
    throw new Error(`Supabase Storage ${action} failed${suffix}: ${result.error.message}`);
  }
  return result.data;
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
    if (env.storageMode === 'supabase') {
      const result = await supabaseBucket().upload(storagePath, buffer, {
        cacheControl: isPublic ? '31536000' : '0',
        contentType,
        upsert: false,
      });
      assertSupabaseResult(result, 'upload');
      return { provider: 'supabase', storagePath };
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
    if (env.storageMode === 'supabase') {
      const data = assertSupabaseResult(
        await supabaseBucket().download(storagePath),
        'download',
      );
      return Buffer.from(await data.arrayBuffer());
    }
    return readFile(localPath(storagePath));
  },

  async delete(storagePath) {
    if (env.storageMode === 'firebase') {
      await bucket().file(storagePath).delete({ ignoreNotFound: true });
      return;
    }
    if (env.storageMode === 'supabase') {
      assertSupabaseResult(
        await supabaseBucket().remove([storagePath]),
        'delete',
      );
      return;
    }
    await unlink(localPath(storagePath)).catch((error) => {
      if (error.code !== 'ENOENT') throw error;
    });
  },

  async verify({ writeProbe = false } = {}) {
    if (env.storageMode === 'firebase') {
      const activeBucket = bucket();
      await activeBucket.getMetadata();
      if (writeProbe) {
        const probePath = `private/readiness/${randomUUID()}.txt`;
        const file = activeBucket.file(probePath);
        try {
          await file.save(Buffer.from('RentHub storage readiness probe'), {
            resumable: false,
            metadata: {
              contentType: 'text/plain',
              cacheControl: 'private,no-store',
            },
          });
        } finally {
          await file.delete({ ignoreNotFound: true });
        }
      }
      return {
        provider: 'firebase',
        bucket: env.firebaseStorageBucket,
        writeProbe,
      };
    }
    if (env.storageMode === 'supabase') {
      assertSupabaseResult(
        await supabase().storage.getBucket(env.supabaseStorageBucket),
        'bucket verification',
      );
      if (writeProbe) {
        const probePath = `private/readiness/${randomUUID()}.png`;
        let uploaded = false;
        try {
          assertSupabaseResult(
            await supabaseBucket().upload(
              probePath,
              Buffer.from(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                'base64',
              ),
              {
                cacheControl: '0',
                contentType: 'image/png',
                upsert: false,
              },
            ),
            'write probe',
          );
          uploaded = true;
        } finally {
          if (uploaded) {
            assertSupabaseResult(
              await supabaseBucket().remove([probePath]),
              'write probe cleanup',
            );
          }
        }
      }
      return {
        provider: 'supabase',
        bucket: env.supabaseStorageBucket,
        writeProbe,
      };
    }

    const root = path.resolve(env.uploadDirectory);
    await mkdir(root, { recursive: true });
    if (writeProbe) {
      const probePath = localPath(`private/readiness/${randomUUID()}.txt`);
      await mkdir(path.dirname(probePath), { recursive: true });
      try {
        await writeFile(probePath, 'RentHub storage readiness probe', {
          flag: 'wx',
        });
      } finally {
        await unlink(probePath).catch((error) => {
          if (error.code !== 'ENOENT') throw error;
        });
      }
    }
    return { provider: 'local', directory: root, writeProbe };
  },
};
