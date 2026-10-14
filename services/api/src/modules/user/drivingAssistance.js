import { UserModel } from './user.model.js';
import { hasApprovedMykad } from './drivingEligibility.js';
import { currentFingerprint, fingerprintForNumber } from './identityBinding.js';

export const DRIVING_CONTRACT = 'malaysian-driving-ocr-v1';
export async function drivingAssessment(user, analysis) {
  const fields = analysis?.extracted_fields ?? analysis?.extractedFields ?? {};
  const validation = fields.licenceValidation;
  const available = validation?.method === DRIVING_CONTRACT && analysis?.outcome !== 'unavailable';
  let canReview = available && validation.acceptedForReview === true &&
    ['ready_for_review', 'needs_review'].includes(validation.status) &&
    !['wrong_document', 'rescan_required', 'rejected', 'unavailable'].includes(analysis.outcome);
  const fingerprint = fingerprintForNumber(fields.identityNumber, fields.identityNumberFormatValid);
  const stored = await UserModel.findById(user._id).select('+verifiedIdentityFingerprint +identityMatchFingerprint');
  const previous = stored?.verifiedIdentityFingerprint ?? stored?.identityMatchFingerprint;
  const comparable = hasApprovedMykad(user) && fingerprint && currentFingerprint(previous);
  const identityMatch = comparable ? (previous === fingerprint ? 'matched' : 'mismatch') : 'unavailable';
  if (identityMatch === 'mismatch') canReview = false;
  const status = !available ? 'unavailable' : identityMatch === 'mismatch' ? 'holder_mismatch' : validation.status;
  return { method: DRIVING_CONTRACT, available, canReview, status, identityMatch,
    licenceClasses: Array.isArray(fields.licenceClasses) ? fields.licenceClasses : [],
    validUntil: fields.validUntil ?? null, validFrom: fields.validFrom ?? null,
    fieldStates: validation?.fieldStates ?? {}, requiresAdminReview: true,
    authenticityVerified: false, officialVerification: false,
    guidance: !available ? 'Licence text checks are unavailable. Retry before submitting.' :
      identityMatch === 'mismatch' ? 'The licence holder does not match your verified MyKad. Upload your own licence.' :
      status === 'expired' ? 'This licence has expired. Upload renewed evidence.' :
      status === 'not_yet_valid' ? 'This licence is not valid yet. Check its validity dates.' :
      status === 'unreadable_image' ? 'The image is blurry, poorly lit or too small. Retake a clear full licence image.' :
      !canReview ? 'This image could not be checked as a driving licence. Show the full licence clearly.' :
      identityMatch === 'unavailable' || status === 'needs_review' ?
        'Licence detected. Some details or the holder match need administrator review.' :
        'Licence details checked. Administrator review is still required.' };
}
