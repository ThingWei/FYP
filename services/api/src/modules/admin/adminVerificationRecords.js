export const VERIFICATION_RECORD_STATUSES = ['pending', 'approved', 'rejected', 'resubmission_required'];
const documentTypes = ['mykad', 'driving_licence', 'passport']; // Passport is historical only.
const submitted = value => VERIFICATION_RECORD_STATUSES.includes(value?.status);
const hasStatus = path => ({ $ne: [{ $ifNull: [`${path}.status`, null] }, null] });

function snapshotExpression(type) {
  const lastOf = field => ({ $arrayElemAt: [{ $filter: { input: { $ifNull: [field, []] }, as: 'document', cond: { $eq: ['$$document.documentType', type] } } }, -1] });
  return { $let: { vars: { saved: lastOf('$verification.documents'), previous: lastOf('$verification.history') }, in: {
    $switch: { branches: [
      ...(type === 'driving_licence' ? [{ case: hasStatus('$drivingEligibility'), then: '$drivingEligibility' }] : []),
      { case: hasStatus('$$saved'), then: '$$saved' },
      { case: { $and: [{ $eq: ['$verification.documentType', type] }, hasStatus('$verification')] }, then: '$verification' },
    ], default: { $ifNull: ['$$previous', {}] } },
  } } };
}

// Match current document states before pagination. An old rejected/pending attempt
// must not override a subsequently reviewed submission of the same document type.
export function verificationRecordsFilter({ status = 'all', documentType = 'all' } = {}) {
  const statuses = status === 'all' ? VERIFICATION_RECORD_STATUSES : [status];
  const types = documentType === 'all' ? documentTypes : [documentType];
  return { $or: [...types.map(type => ({ $expr: {
    $in: [{ $let: { vars: { record: snapshotExpression(type) }, in: '$$record.status' } }, statuses],
  } })), ...(status === 'all' ? [{ 'verification.history': { $elemMatch: { documentType: { $in: types } } } }] : [])] };
}

export function verificationRecordSummary(user) {
  const verification = user.verification ?? {};
  return documentTypes.flatMap(documentType => {
    const saved = (verification.documents ?? []).filter(row => row.documentType === documentType).at(-1);
    const previous = (verification.history ?? []).filter(row => row.documentType === documentType).at(-1);
    const row = documentType === 'driving_licence' && user.drivingEligibility?.status != null
      ? user.drivingEligibility : saved?.status != null ? saved
        : verification.documentType === documentType && verification.status != null ? verification : previous;
    return submitted(row) || previous && row?.status != null ? [{ documentType, status: row.status,
      submittedAt: row.submittedAt, reviewedAt: row.reviewedAt ?? row.verifiedAt,
    }] : [];
  });
}
