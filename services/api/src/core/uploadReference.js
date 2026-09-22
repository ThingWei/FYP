import { env } from '../config/env.js';

const storedReference = /^upload:\/\/UPL-[A-Z0-9]+$/i;
const publicContentPath = /^\/api\/v1\/uploads\/public\/UPL-[A-Z0-9]+\/content$/i;
const developmentPlaceholder = /^local:\/\/[a-z\d/_-]+\.(?:jpg|jpeg|png|webp|pdf)$/i;
const legacyEvidencePlaceholder = /^evidence:\/\/[a-z\d/_-]+$/i;

export function isUploadReference(value, { publicOnly = false } = {}) {
  if (typeof value !== 'string' || value.length > 500) return false;
  if (publicOnly && publicContentPath.test(value)) return true;
  if (!publicOnly && storedReference.test(value)) return true;
  return env.nodeEnv !== 'production' &&
    (developmentPlaceholder.test(value) || legacyEvidencePlaceholder.test(value));
}
