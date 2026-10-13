import { createHash, createHmac } from 'node:crypto';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { UserModel, IDENTITY_BINDING_INDEX } from './user.model.js';

export const APPROVED_MYKAD = { $or: [
  { 'verification.documents': { $elemMatch: { documentType: 'mykad', status: 'approved' } } },
  { 'verification.status': 'approved', 'verification.documentType': 'mykad',
    'verification.documents': { $not: { $elemMatch: { documentType: 'mykad' } } } },
] };
export const FINGERPRINT_SHAPE = /^[a-f0-9]{12}:[a-f0-9]{64}$/;
export function bindingKeyId(config = env) {
  const secret = config.kycIdentityMatchSecret;
  if (typeof secret !== 'string' || secret.length < 32) return null;
  return createHash('sha256').update(secret).digest('hex').slice(0, 12);
}
export function fingerprintForNumber(number, valid, config = env) {
  const digits = String(number ?? '').replace(/[ \t-]/g, '');
  const key = bindingKeyId(config);
  if (!key || !/^\d{12}$/.test(digits) || valid !== true) return null;
  return key + ':' + createHmac('sha256', config.kycIdentityMatchSecret)
    .update('renthub-mykad:' + digits).digest('hex');
}
export function currentFingerprint(value, config = env) {
  const key = bindingKeyId(config);
  return Boolean(key && typeof value === 'string' && FINGERPRINT_SHAPE.test(value) && value.startsWith(key + ':'));
}
export function duplicateIdentityError() {
  return new AppError('This MyKad is already linked to another account. Use your existing account or contact support.',
    409, 'MYKAD_ALREADY_LINKED');
}
export async function assertBindingReady(config = env) {
  const key = bindingKeyId(config);
  if (!key) throw new AppError('MyKad account linking is unavailable. An administrator must configure the identity matching key.',
    503, 'IDENTITY_BINDING_NOT_CONFIGURED');
  let indexes;
  try { indexes = await UserModel.collection.listIndexes().toArray(); }
  catch { throw new AppError('MyKad account linking is unavailable. The required database index must be installed.',
    503, 'IDENTITY_BINDING_INDEX_MISSING'); }
  if (!indexes.some(index => index.name === IDENTITY_BINDING_INDEX && index.unique === true &&
      index.key?.verifiedIdentityFingerprint === 1 && Object.keys(index.key).length === 1 &&
      index.partialFilterExpression?.verifiedIdentityFingerprint?.$type === 'string')) {
    throw new AppError('MyKad account linking is unavailable. The required database index must be installed.',
      503, 'IDENTITY_BINDING_INDEX_MISSING');
  }
  // Changing the key must never silently create a separate namespace of identities.
  const incompatible = await UserModel.exists({ $or: [
    { verifiedIdentityFingerprint: { $type: 'string', $not: new RegExp('^' + key + ':[a-f0-9]{64}$') } },
    { $and: [APPROVED_MYKAD,
      { identityMatchFingerprint: { $regex: FINGERPRINT_SHAPE, $not: new RegExp('^' + key + ':') } }] },
  ] });
  if (incompatible) throw new AppError('MyKad account linking needs a reviewed key migration. Do not replace the existing identity matching key.',
    503, 'IDENTITY_BINDING_KEY_MISMATCH');
  return { keyConfigured: true, uniqueIndexReady: true };
}
export async function assertIdentityNotLinked(fingerprint, userId) {
  if (!currentFingerprint(fingerprint)) {
    throw new AppError('Resubmit MyKad to establish a current identity match.', 409, 'IDENTITY_BINDING_ATTEMPT_INVALID');
  }
  const owner = await UserModel.exists({ _id: { $ne: userId }, $or: [
    { verifiedIdentityFingerprint: fingerprint },
    { $and: [APPROVED_MYKAD, { identityMatchFingerprint: fingerprint }] },
  ] });
  if (owner) throw duplicateIdentityError();
}
export async function approveMykadAtomically(user, attempt) {
  await assertBindingReady();
  const latest = user.verification.documents.find(document => document.documentType === 'mykad');
  if (latest?.latestAttemptId !== attempt.attemptId) {
    throw new AppError('This attempt was replaced. Review the latest MyKad submission.', 409, 'STALE_VERIFICATION_ATTEMPT');
  }
  await assertIdentityNotLinked(attempt.identityFingerprint, user._id);
  if (user.verifiedIdentityFingerprint && user.verifiedIdentityFingerprint !== attempt.identityFingerprint) {
    throw new AppError('This account already has an identity binding. Contact support.', 409, 'IDENTITY_BINDING_CHANGE_FORBIDDEN');
  }
  const set = {
    verifiedIdentityFingerprint: attempt.identityFingerprint,
    'verification.history.$[attempt].status': 'approved',
    'verification.history.$[attempt].reviewReason': attempt.reviewReason,
    'verification.history.$[attempt].reviewedAt': attempt.reviewedAt,
    'verification.history.$[attempt].reviewedBy': attempt.reviewedBy,
    'verification.documents.$[document].status': 'approved',
    'verification.documents.$[document].reviewedAt': latest.reviewedAt,
    'verification.documents.$[document].reviewedBy': latest.reviewedBy,
    'verification.documents.$[document].reason': latest.reason,
    'verification.status': user.verification.status,
    'verification.tier': user.verification.tier,
    'verification.documentType': 'mykad',
    'verification.documentRefs': user.verification.documentRefs,
    'verification.ocrResult': user.verification.ocrResult,
    'verification.reason': user.verification.reason,
    'verification.reviewedAt': user.verification.reviewedAt,
    'verification.reviewedBy': user.verification.reviewedBy,
  };
  try {
    const updated = await UserModel.findOneAndUpdate({
      _id: user._id,
      'verification.documents': { $elemMatch: { documentType: 'mykad',
        latestAttemptId: attempt.attemptId, status: 'pending' } },
      'verification.history': { $elemMatch: { attemptId: attempt.attemptId,
        status: 'pending', identityFingerprint: attempt.identityFingerprint } },
      $or: [{ verifiedIdentityFingerprint: { $exists: false } },
            { verifiedIdentityFingerprint: attempt.identityFingerprint }],
    }, { $set: set }, { new: true, runValidators: true, arrayFilters: [
      { 'attempt.attemptId': attempt.attemptId }, { 'document.documentType': 'mykad' },
    ] });
    if (!updated) throw new AppError('This attempt changed. Refresh and review the latest submission.',
      409, 'STALE_VERIFICATION_ATTEMPT');
    return updated;
  } catch (error) {
    if (error.code === 11000 && error.keyPattern?.verifiedIdentityFingerprint) throw duplicateIdentityError();
    throw error;
  }
}

