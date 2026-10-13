import { bindingKeyId, currentFingerprint, FINGERPRINT_SHAPE, APPROVED_MYKAD } from './identityBinding.js';
import { IDENTITY_BINDING_INDEX } from './user.model.js';
import { hasApprovedMykad } from './drivingEligibility.js';

function approved(user) {
  return hasApprovedMykad(user);
}
export async function auditIdentityBindings(collection, config, { limit = 1000, apply = false, reviewed = false } = {}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 10000) throw new Error('Limit must be a whole number from 1 to 10000');
  if (apply && !reviewed) throw new Error('Apply requires an explicit acknowledgment that the legacy candidates were reviewed');
  const rows = await collection.find({ $or: [APPROVED_MYKAD, { verifiedIdentityFingerprint: { $type: 'string' } }] },
    { projection: { 'verification.status': 1, 'verification.documentType': 1,
      'verification.documents.status': 1, 'verification.documents.documentType': 1,
      identityMatchFingerprint: 1, verifiedIdentityFingerprint: 1 } })
    .sort({ _id: 1 }).limit(limit + 1).toArray();
  const truncated = rows.length > limit;
  const inspected = rows.slice(0, limit);
  const counts = { inspectedAccounts: inspected.length, approvedAccounts: 0, alreadyBound: 0,
    usableUnbound: 0, missingFingerprints: 0, incompatibleKeyFingerprints: 0,
    conflictingStoredFingerprints: 0, duplicateGroups: 0, duplicateAccounts: 0,
    applied: 0, concurrentConflicts: 0, changedOrAlreadyBound: 0 };
  const groups = new Map();
  for (const row of inspected) {
    if (approved(row)) counts.approvedAccounts++;
    if (row.verifiedIdentityFingerprint) counts.alreadyBound++;
    const fingerprint = row.verifiedIdentityFingerprint ?? row.identityMatchFingerprint;
    if (row.verifiedIdentityFingerprint && row.identityMatchFingerprint &&
        row.verifiedIdentityFingerprint !== row.identityMatchFingerprint) counts.conflictingStoredFingerprints++;
    if (!FINGERPRINT_SHAPE.test(fingerprint ?? '')) counts.missingFingerprints++;
    else {
      if (!currentFingerprint(fingerprint, config)) counts.incompatibleKeyFingerprints++;
      if (!groups.has(fingerprint)) groups.set(fingerprint, []);
      groups.get(fingerprint).push(row);
    }
  }
  const candidates = [];
  for (const [fingerprint, owners] of groups) {
    if (owners.length > 1) { counts.duplicateGroups++; counts.duplicateAccounts += owners.length; continue; }
    const row = owners[0];
    if (approved(row) && !row.verifiedIdentityFingerprint && currentFingerprint(fingerprint, config)) {
      candidates.push(row); counts.usableUnbound++;
    }
  }
  const report = { dryRun: !apply, keyConfigured: Boolean(bindingKeyId(config)),
    truncated, limit, counts, limitations: [
      'Missing legacy fingerprints cannot be reconstructed from masked identifiers.',
      'No approval was revoked; duplicate groups are quarantined, never assigned a winner.',
      'Counts refer only to the bounded inspected set if truncated.',
    ] };
  if (!apply) return report;
  if (!report.keyConfigured) throw new Error('Configure the existing stable KYC_IDENTITY_MATCH_SECRET before applying bindings');
  if (truncated) throw new Error('Audit is truncated; inspect the complete bounded candidate set before applying');
  if (counts.incompatibleKeyFingerprints || counts.conflictingStoredFingerprints) {
    throw new Error('Existing fingerprints require a reviewed key/conflict migration; no bindings were written');
  }
  const indexes = await collection.listIndexes().toArray();
  if (!indexes.some(index => index.name === IDENTITY_BINDING_INDEX && index.unique === true &&
      index.key?.verifiedIdentityFingerprint === 1 && Object.keys(index.key).length === 1 &&
      index.partialFilterExpression?.verifiedIdentityFingerprint?.$type === 'string')) {
    throw new Error('The unique identity-binding index is missing; no bindings were written');
  }
  for (const row of candidates) {
    const fingerprint = row.identityMatchFingerprint;
    const otherOwner = await collection.findOne({ _id: { $ne: row._id }, $or: [
      { verifiedIdentityFingerprint: fingerprint },
      { $and: [APPROVED_MYKAD, { identityMatchFingerprint: fingerprint }] },
    ] }, { projection: { _id: 1 } });
    if (otherOwner) { counts.concurrentConflicts++; continue; }
    try {
      const result = await collection.updateOne({ _id: row._id, identityMatchFingerprint: fingerprint,
        verifiedIdentityFingerprint: { $exists: false }, ...APPROVED_MYKAD },
        { $set: { verifiedIdentityFingerprint: fingerprint } });
      if (result.modifiedCount) counts.applied++;
      else counts.changedOrAlreadyBound++;
    } catch (error) {
      if (error.code === 11000) counts.concurrentConflicts++;
      else throw new Error('Legacy binding write failed; rerun the read-only audit before retrying');
    }
  }
  return report; // Aggregate counts only: no fingerprint, account ID, name or email.
}

