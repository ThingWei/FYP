import mongoose from 'mongoose';
import { createHash, createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { AppError } from '../../core/errors.js';
import { adminModule } from '../admin/index.js';
import { notifyUser } from '../communication/notification.service.js';
import { DeviceRegistrationModel } from '../communication/deviceRegistration.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ACCOUNT_STATUSES, USER_ROLES, UserModel } from './user.model.js';
import { PasswordResetModel } from './passwordReset.model.js';
import { userRepository } from './user.repository.js';
import { uploadService } from '../upload/upload.service.js';
import { aiClient } from '../../integrations/aiClient.js';
import { disconnectUser } from '../../socket/eventBus.js';
import { env } from '../../config/env.js';
import { hashPassword, verifyPassword } from '../../core/password.js';
import { emailClient } from '../../integrations/emailClient.js';
import { localSessionService } from './localSession.service.js';
import {
  MARKETPLACE_ROLES,
  isMarketplaceRole,
  normalizeStoredUserRoles,
  normalizeTrustedIdentityRoles,
} from './rolePolicy.js';
import {
  approvedDocumentTypes,
  resolveKycRequirement,
} from './kycRequirements.js';
import { drivingEligibilityCheck, hasApprovedMykad, LICENCE_CLASSES, reviewedLicenceExpiry } from './drivingEligibility.js';

const OPEN_BOOKING_STATUSES = ['pending', 'approved', 'active', 'disputed'];
const OPEN_RENTAL_STATUSES = [
  'scheduled',
  'active',
  'overdue',
  'return_submitted',
  'completion_pending',
  'disputed',
];
const OPEN_DISPUTE_STATUSES = [
  'open',
  'awaiting_response',
  'under_review',
  'more_evidence_required',
  'escalated',
];

function preferredRole(roles) {
  return roles.includes('renter') ? 'renter' : roles[0];
}

function verificationAttemptId() {
  return `KYC-${new mongoose.Types.ObjectId().toString().toUpperCase()}`;
}

function maskedIdentityNumber(value) {
  if (!value || typeof value !== 'string') return value;
  const visible = value.replace(/\s/g, '').slice(-4);
  return `${'*'.repeat(Math.max(4, value.length - visible.length))}${visible}`;
}

function privateSafeAiEvidence(analysis) {
  const evidence = JSON.parse(JSON.stringify(analysis ?? {}));
  delete evidence.ocr_text;
  delete evidence.ocrText;
  const fields = evidence.extracted_fields ?? evidence.extractedFields;
  if (fields) {
    for (const key of [
      'identityNumber',
      'identity_number',
      'passportNumber',
      'passport_number',
      'licenceNumber',
      'licence_number',
    ]) {
      if (fields[key]) fields[key] = maskedIdentityNumber(fields[key]);
    }
  }
  return evidence;
}

function aggregateVerificationStatus(verification) {
  const documents = (verification.documents ?? []).filter((document) => document.documentType !== 'driving_licence');
  if (
    documents.some(
      (document) =>
        ['mykad', 'passport'].includes(document.documentType) &&
        document.status === 'approved',
    )
  ) return 'approved';
  if (documents.some((document) => document.status === 'pending')) return 'pending';
  const identityDocuments = documents.filter(
    (document) => ['mykad', 'passport'].includes(document.documentType),
  );
  if (documents.length) return identityDocuments.at(-1)?.status ?? 'unverified';
  // Preserve legacy identity states, but a licence is only a vehicle credential.
  if (verification.documentType === 'driving_licence') return 'unverified';
  return verification.status ?? 'unverified';
}

function identityFingerprint(analysis) {
  const fields = analysis.extracted_fields ?? analysis.extractedFields ?? {};
  const digits = String(fields.identityNumber ?? '').replace(/\D/g, '');
  const secret = env.kycIdentityMatchSecret;
  if (!secret || secret.length < 32 || digits.length !== 12 || fields.identityNumberFormatValid !== true) return null;
  const keyId = createHash('sha256').update(secret).digest('hex').slice(0, 12);
  return `${keyId}:${createHmac('sha256', secret).update(`renthub-mykad:${digits}`).digest('hex')}`;
}

const passwordResetResponse = () => ({
  message: 'If an eligible account exists, a reset code has been sent.',
  expiresInMinutes: env.passwordResetTtlMinutes,
});

function resetCodeHash(email, code) {
  return createHmac('sha256', env.passwordResetSecret)
    .update(`${email}:${code}`)
    .digest('hex');
}

function resetCodeMatches(actual, expected) {
  const actualBuffer = Buffer.from(actual, 'hex');
  const expectedBuffer = Buffer.from(expected, 'hex');
  return (
    actualBuffer.length === expectedBuffer.length &&
    timingSafeEqual(actualBuffer, expectedBuffer)
  );
}

function invalidResetCode() {
  return new AppError(
    'The reset code is invalid or has expired. Request a new code and try again.',
    400,
    'INVALID_RESET_CODE',
  );
}

function identityData(identity) {
  const authId = String(identity.authId ?? '').trim();
  const suppliedEmail =
    typeof identity.email === 'string' ? identity.email.trim().toLowerCase() : '';
  const email =
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(suppliedEmail)
      ? suppliedEmail
      : `auth0-${createHash('sha256')
          .update(authId)
          .digest('hex')
          .slice(0, 24)}@users.renthub.local`;
  const suppliedName =
    typeof identity.displayName === 'string' ? identity.displayName.trim() : '';
  const displayName =
    suppliedName.length >= 2 ? suppliedName.slice(0, 80) : 'RentHub User';

  return {
    authId,
    email,
    displayName,
    roles: normalizeTrustedIdentityRoles(identity.roles),
  };
}

async function requireCurrentUser(identity) {
  const user = await userRepository.findByAuthId(identity.authId);
  if (!user) {
    throw new AppError(
      'User profile has not been created. Start a session first.',
      404,
      'USER_PROFILE_NOT_FOUND',
    );
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(
      `Account is ${user.accountStatus}`,
      403,
      'ACCOUNT_RESTRICTED',
    );
  }
  return user;
}

export const userService = {
  async localLogin({ email, password, role }, metadata) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local login is disabled', 404, 'NOT_FOUND');
    }
    const user = await userRepository.findByEmailWithPassword(email);
    const valid = user?.passwordHash
      ? await verifyPassword(password, user.passwordHash)
      : false;
    if (!user || !valid) {
      throw new AppError(
        'Incorrect email or password',
        401,
        'INVALID_CREDENTIALS',
      );
    }
    if (user.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${user.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    const normalized = normalizeStoredUserRoles(user.roles, user.activeRole);
    user.roles = normalized.roles;
    user.activeRole = normalized.activeRole;
    if (!user.roles.includes(role)) {
      throw new AppError(
        `This account does not have the ${role} role`,
        403,
        'FORBIDDEN',
      );
    }
    user.activeRole = role;
    user.lastLoginAt = new Date();
    await user.save();
    return ['local', 'hybrid'].includes(env.authMode)
      ? localSessionService.create(user, metadata)
      : user;
  },

  async localRegister({ displayName, email, password, role }, metadata) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local registration is disabled', 404, 'NOT_FOUND');
    }
    if (await userRepository.findByEmailWithPassword(email)) {
      throw new AppError(
        'An account with this email already exists',
        409,
        'DUPLICATE_RECORD',
      );
    }
    const suffix = new mongoose.Types.ObjectId().toString();
    const user = await userRepository.create({
      authId: `u-${suffix}`,
      email,
      passwordHash: await hashPassword(password),
      displayName,
      roles: [...MARKETPLACE_ROLES],
      activeRole: role,
      lastLoginAt: new Date(),
    });
    return ['local', 'hybrid'].includes(env.authMode)
      ? localSessionService.create(user, metadata)
      : user;
  },

  async localRefresh({ refreshToken }, metadata) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local refresh is disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.refresh(refreshToken, metadata);
  },

  async localLogout(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local logout is disabled', 404, 'NOT_FOUND');
    }
    await localSessionService.revoke(identity.sessionId);
    return { signedOut: true };
  },

  async localSessions(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.list(identity);
  },

  async revokeLocalSession(identity, sessionId) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.revokeForUser(identity, sessionId);
  },

  async revokeOtherLocalSessions(identity) {
    if (!['local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local sessions are disabled', 404, 'NOT_FOUND');
    }
    return localSessionService.revokeOthers(identity);
  },

  async requestLocalPasswordReset({ email }) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local password reset is disabled', 404, 'NOT_FOUND');
    }
    try {
      emailClient.assertConfigured();
    } catch {
      throw new AppError(
        'Password-reset email is temporarily unavailable. Please contact support.',
        503,
        'EMAIL_NOT_CONFIGURED',
      );
    }
    const normalizedEmail = email.toLowerCase();
    const cooldownStartedAt = new Date(
      Date.now() - env.passwordResetCooldownSeconds * 1000,
    );
    const recent = await PasswordResetModel.exists({
      email: normalizedEmail,
      consumedAt: null,
      createdAt: { $gte: cooldownStartedAt },
    });
    if (recent) return passwordResetResponse();

    const user = await userRepository.findByEmailWithPassword(normalizedEmail);
    if (!user || !user.passwordHash || user.accountStatus !== 'active') {
      return passwordResetResponse();
    }

    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await PasswordResetModel.deleteMany({ email: normalizedEmail });
    const reset = await PasswordResetModel.create({
      userId: user._id,
      email: normalizedEmail,
      codeHash: resetCodeHash(normalizedEmail, code),
      expiresAt: new Date(
        Date.now() + env.passwordResetTtlMinutes * 60 * 1000,
      ),
    });
    try {
      await emailClient.sendPasswordResetCode({
        email: normalizedEmail,
        displayName: user.displayName,
        code,
      });
    } catch (error) {
      await PasswordResetModel.deleteOne({ _id: reset._id });
      console.error('Password-reset email provider rejected the request:', error.message);
      throw new AppError(
        'The password-reset email could not be sent. Please try again later.',
        502,
        'EMAIL_DELIVERY_FAILED',
      );
    }
    return passwordResetResponse();
  },

  async confirmLocalPasswordReset({ email, code, password }) {
    if (!['mock', 'local', 'hybrid'].includes(env.authMode)) {
      throw new AppError('Local password reset is disabled', 404, 'NOT_FOUND');
    }
    if (!env.passwordResetSecret) throw invalidResetCode();
    const normalizedEmail = email.toLowerCase();
    const reset = await PasswordResetModel.findOne({
      email: normalizedEmail,
      consumedAt: null,
      expiresAt: { $gt: new Date() },
      attempts: { $lt: env.passwordResetMaxAttempts },
    })
      .sort({ createdAt: -1 })
      .select('+codeHash');
    if (!reset) throw invalidResetCode();

    reset.attempts += 1;
    await reset.save();
    const suppliedHash = resetCodeHash(normalizedEmail, code);
    if (!resetCodeMatches(suppliedHash, reset.codeHash)) {
      throw invalidResetCode();
    }

    const claimed = await PasswordResetModel.findOneAndUpdate(
      { _id: reset._id, consumedAt: null },
      { consumedAt: new Date() },
      { new: true },
    );
    if (!claimed) throw invalidResetCode();
    const user = await UserModel.findById(reset.userId).select('+passwordHash');
    if (!user || user.accountStatus !== 'active') throw invalidResetCode();
    user.passwordHash = await hashPassword(password);
    user.accessRevokedAt = new Date();
    await user.save();
    await Promise.all([
      PasswordResetModel.deleteMany({ userId: user._id }),
      localSessionService.revokeAllForUser(user._id),
    ]);
    disconnectUser(user.authId);
    return { message: 'Your password has been updated. You can now sign in.' };
  },

  async startSession(identity) {
    const data = identityData(identity);
    let user = await userRepository.findByAuthId(data.authId);
    if (!user) {
      user = await userRepository.create({
        ...data,
        activeRole: preferredRole(data.roles),
        lastLoginAt: new Date(),
      });
      return { user, created: true };
    }
    if (user.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${user.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    normalizeStoredUserRoles(user.roles, user.activeRole);
    const activeRole = data.roles.includes(user.activeRole)
      ? user.activeRole
      : preferredRole(data.roles);
    const updated = await userRepository.updateByAuthId(data.authId, {
      email: data.email,
      // A profile may have been created before Auth0 returned usable profile
      // claims (for example, an Android login that initially only supplied a
      // subject). Repair that placeholder when a later login provides a real
      // name, but do not overwrite a name the user has edited in RentHub.
      ...(user.displayName === 'RentHub User' &&
        data.displayName !== 'RentHub User' && {
          displayName: data.displayName,
        }),
      roles: data.roles,
      activeRole,
      lastLoginAt: new Date(),
    });
    return { user: updated, created: false };
  },

  getMe: requireCurrentUser,

  async deactivateMe(identity, reason) {
    const user = await requireCurrentUser(identity);
    const participant = {
      $or: [{ renterId: user.authId }, { ownerId: user.authId }],
    };
    const disputeParticipant = {
      $or: [{ raisedById: user.authId }, { respondentId: user.authId }],
    };
    const [openBookings, openRentals, openDisputes] = await Promise.all([
      BookingModel.countDocuments({
        ...participant,
        status: { $in: OPEN_BOOKING_STATUSES },
      }),
      RentalModel.countDocuments({
        ...participant,
        status: { $in: OPEN_RENTAL_STATUSES },
      }),
      DisputeModel.countDocuments({
        ...disputeParticipant,
        status: { $in: OPEN_DISPUTE_STATUSES },
      }),
    ]);
    if (openBookings || openRentals || openDisputes) {
      throw new AppError(
        'Resolve active bookings, rentals, and disputes before deactivating your account.',
        409,
        'ACCOUNT_HAS_OPEN_OBLIGATIONS',
      );
    }
    if (
      user.roles.includes('admin') &&
      (await user.constructor.countDocuments({
        roles: 'admin',
        accountStatus: 'active',
      })) <= 1
    ) {
      throw new AppError(
        'The final active administrator cannot deactivate their account.',
        409,
        'LAST_ACTIVE_ADMIN',
      );
    }
    const now = new Date();
    user.accountStatus = 'deactivated';
    user.accountStatusReason = reason.trim();
    user.accountStatusChangedAt = now;
    user.accountStatusChangedBy = user.authId;
    user.deactivatedAt = now;
    user.deactivatedBy = user.authId;
    user.accessRevokedAt = now;
    await user.save();
    await Promise.all([
      ListingModel.updateMany(
        { ownerId: user.authId, status: { $in: ['active', 'pending_review'] } },
        { status: 'inactive' },
      ),
      DeviceRegistrationModel.deleteMany({ userId: user.authId }),
      localSessionService.revokeAllForUser(user._id),
      adminModule.service.create({
        actorId: user.authId,
        action: 'account.self_deactivated',
        targetType: 'user',
        targetId: user.authId,
        metadata: { reason: user.accountStatusReason },
        createdBy: user.authId,
      }),
    ]);
    disconnectUser(user.authId);
    return {
      accountStatus: user.accountStatus,
      deactivatedAt: user.deactivatedAt,
    };
  },

  async updateMe(identity, input) {
    const user = await requireCurrentUser(identity);
    if (input.avatarUrl?.startsWith('/api/v1/uploads/')) {
      await uploadService.assertOwnedReferences(identity, [input.avatarUrl], ['avatar']);
    }
    const allowed = {
      ...(input.displayName !== undefined && { displayName: input.displayName }),
      ...(input.phone !== undefined && { phone: input.phone }),
      ...(input.avatarUrl !== undefined && { avatarUrl: input.avatarUrl }),
      ...(input.addresses !== undefined && { addresses: input.addresses }),
      ...(input.settings !== undefined && { settings: input.settings }),
    };
    user.set(allowed);
    await user.save();
    return user;
  },

  async selectRole(identity, role) {
    const user = await requireCurrentUser(identity);
    const normalized = normalizeStoredUserRoles(user.roles, user.activeRole);
    if (!isMarketplaceRole(role) || normalized.roles.includes('admin')) {
      throw new AppError(
        'Role switching is available only to marketplace accounts',
        403,
        'ROLE_SWITCH_NOT_AVAILABLE',
      );
    }
    if (!normalized.roles.includes(role)) {
      throw new AppError('Role is not assigned to this user', 403, 'ROLE_NOT_ASSIGNED');
    }
    return userRepository.updateByAuthId(user.authId, {
      roles: normalized.roles,
      activeRole: role,
    });
  },

  async submitVerification(identity, input) {
    const user = await requireCurrentUser(identity);
    const driving = input.documentType === 'driving_licence';
    await uploadService.assertOwnedReferences(
      identity,
      input.documentRefs,
      ['verification_document'],
    );
    const currentDocument = user.verification.documents?.find(
      (document) => document.documentType === input.documentType,
    );
    const legacyDrivingStatus = currentDocument?.status ??
      (user.verification.documentType === 'driving_licence' ? user.verification.status : undefined);
    const legacyDrivingRecord = driving && legacyDrivingStatus === 'approved' && !user.drivingEligibility?.latestAttemptId
      ? { document: currentDocument?.toObject() ?? {
            documentType: 'driving_licence', status: legacyDrivingStatus,
            reviewedAt: user.verification.reviewedAt, reviewedBy: user.verification.reviewedBy,
          },
          documentRefs: user.verification.documentType === 'driving_licence' ? [...user.verification.documentRefs] : [],
          aiEvidence: user.verification.documentType === 'driving_licence' ? privateSafeAiEvidence(user.verification.ocrResult) : {},
          migrationReason: 'Historical approval retained; complete driving-eligibility re-review required' }
      : user.drivingEligibility?.legacyRecord;
    if (currentDocument?.status === 'pending') {
      throw new AppError(
        'This document type is already pending verification',
        409,
        'VERIFICATION_PENDING',
      );
    }
    if (currentDocument?.status === 'approved' && !driving) {
      throw new AppError(
        'This document type is already verified',
        409,
        'ALREADY_VERIFIED',
      );
    }
    if (input.documentType === 'mykad' && (input.documentRefs.length !== 2 || new Set(input.documentRefs).size !== 2)) {
      throw new AppError('Upload distinct MyKad front and back images', 400, 'MYKAD_SIDES_REQUIRED');
    }
    const images = await uploadService.readOwnedReferences(
      identity,
      input.documentRefs,
      ['verification_document'],
    );
    const platform =
      (await adminModule.PlatformSettingModel.findOne({ key: 'platform' })) ??
      await adminModule.PlatformSettingModel.create({ key: 'platform' });
    const analysis = await aiClient.verifyDocument({
      images,
      documentType: input.documentType,
      profileName: user.displayName,
      reviewThreshold: platform.verificationManualReviewThreshold,
      minimumAge: platform.minimumVerificationAge,
    });
    const submittedAt = new Date();
    const attemptId = verificationAttemptId();
    const evidence = privateSafeAiEvidence(analysis);
    const fingerprint = identityFingerprint(analysis);
    if (!driving && input.documentType === 'mykad') {
      user.identityMatchFingerprint = fingerprint ?? undefined;
    }
    if (driving) {
      const stored = await UserModel.findById(user._id).select('+identityMatchFingerprint');
      const previous = stored?.identityMatchFingerprint;
      const comparable = hasApprovedMykad(user) && fingerprint && previous &&
        fingerprint.split(':')[0] === previous.split(':')[0];
      evidence.identityMatch = comparable ? (fingerprint === previous ? 'matched' : 'mismatch') : 'unavailable';
      evidence.reviewScope = 'driving_eligibility';
    }
    const requiresRescan = analysis.outcome === 'rescan_required';
    const status = requiresRescan ? 'resubmission_required' : 'pending';
    const reason = requiresRescan
      ? (analysis.reasons ?? ['Image quality requires a rescan']).join(' ')
      : '';
    const document = currentDocument ?? {
      documentType: input.documentType,
    };
    Object.assign(document, {
      status,
      latestAttemptId: attemptId,
      submittedAt,
      reviewedAt: undefined,
      reviewedBy: '',
      reason,
    });
    if (!currentDocument) user.verification.documents.push(document);
    user.verification.history.push({
      attemptId,
      documentType: input.documentType,
      documentRefs: input.documentRefs,
      aiEvidence: evidence,
      status,
      submittedAt,
      reviewReason: reason,
    });
    if (driving) {
      user.drivingEligibility = {
        status, latestAttemptId: attemptId, submittedAt,
        identityMatch: evidence.identityMatch, reviewNotes: reason,
        identityMatchConfirmed: false, classReviewConfirmed: false,
        legacyRecord: legacyDrivingRecord,
      };
      user.verification.status = aggregateVerificationStatus(user.verification);
      if (user.verification.status !== 'approved') user.verification.tier = 'none';
      // Licence attempts live in the shared protected history, not identity state.
      await user.save();
      return user;
    }
    user.verification.status = aggregateVerificationStatus(user.verification);
    user.verification.tier =
      user.verification.status === 'approved' ? user.verification.tier : 'none';
    user.verification.documentType = input.documentType;
    user.verification.documentRefs = input.documentRefs;
    user.verification.ocrResult = evidence;
    user.verification.reason = reason;
    user.verification.submittedAt = submittedAt;
    user.verification.reviewedAt = undefined;
    user.verification.reviewedBy = '';
    await user.save();
    return user;
  },

  async inspectVerificationFrame(identity, input) {
    await requireCurrentUser(identity);
    return aiClient.inspectDocumentFrame({
      contentBase64: input.contentBase64,
      contentType: input.contentType ?? 'image/jpeg',
      documentType: input.documentType,
    });
  },

  async verificationRequirements(identity, query) {
    const user = await requireCurrentUser(identity);
    const settings =
      (await adminModule.PlatformSettingModel.findOne({ key: 'platform' })) ??
      await adminModule.PlatformSettingModel.create({ key: 'platform' });
    const requirement = resolveKycRequirement(settings, {
      category: query.category,
      dailyPrice: query.dailyPrice ?? 0,
    });
    const approved = approvedDocumentTypes(user);
    return {
      ...requirement,
      approvedDocumentTypes: [...approved],
      missingDocumentTypes: requirement.requiredDocumentTypes.filter(
        (type) => !approved.has(type),
      ),
      ...(query.category === 'Vehicles' && {
        drivingEligibility: drivingEligibilityCheck(user, { requiredLicenceClass: query.requiredLicenceClass }),
      }),
    };
  },

  async reviewVerification(id, input, identity) {
    const user = await userRepository.findById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    let attempt = input.attemptId
      ? user.verification.history?.find((item) => item.attemptId === input.attemptId)
      : input.drivingOnly ? user.verification.history?.findLast((item) => item.documentType === 'driving_licence' && item.status === 'pending')
      : user.verification.history?.find(
          (item) => item.attemptId === user.verification.documents?.find(
            (document) => document.documentType === user.verification.documentType,
          )?.latestAttemptId,
        );
    if (!attempt && user.verification.status === 'pending') {
      attempt = {
        attemptId: verificationAttemptId(),
        documentType: user.verification.documentType,
        documentRefs: user.verification.documentRefs,
        aiEvidence: privateSafeAiEvidence(user.verification.ocrResult),
        status: 'pending',
        submittedAt: user.verification.submittedAt ?? new Date(),
      };
      user.verification.history.push(attempt);
    }
    if (!attempt || attempt.status !== 'pending') {
      throw new AppError(
        'Only pending verification submissions can be reviewed',
        409,
        'INVALID_VERIFICATION_STATE',
      );
    }
    const driving = attempt.documentType === 'driving_licence';
    if (input.drivingOnly && !driving) throw new AppError('Select a driving eligibility attempt', 400, 'INVALID_DRIVING_ATTEMPT');
    if (driving && input.status === 'approved') {
      if (!hasApprovedMykad(user)) throw new AppError('Approve MyKad identity first', 409, 'MYKAD_REQUIRED');
      if (attempt.aiEvidence?.identityMatch === 'mismatch') throw new AppError('Licence holder identity does not match the verified MyKad', 409, 'DRIVING_IDENTITY_MISMATCH');
      if (input.identityMatchConfirmed !== true || input.classReviewConfirmed !== true) {
        throw new AppError('Confirm holder identity and licence class from the protected evidence', 400, 'DRIVING_REVIEW_CONFIRMATION_REQUIRED');
      }
      if (!input.licenceClasses?.length || input.licenceClasses.some((value) => !LICENCE_CLASSES.includes(value))) {
        throw new AppError('Enter the reviewed licence classes', 400, 'LICENCE_CLASS_REQUIRED');
      }
      input.reviewedExpiry = reviewedLicenceExpiry(input.expiresAt);
    }
    if (input.status !== 'approved' && !input.reason?.trim()) {
      throw new AppError(
        'A review reason is required',
        400,
        'REASON_REQUIRED',
      );
    }
    const reviewedAt = new Date();
    attempt.status = input.status;
    attempt.reviewReason = input.reason?.trim() ?? '';
    attempt.reviewedAt = reviewedAt;
    attempt.reviewedBy = identity.authId;
    let document = user.verification.documents?.find(
      (item) => item.documentType === attempt.documentType,
    );
    if (!document) {
      document = { documentType: attempt.documentType };
      user.verification.documents.push(document);
    }
    if (!document.latestAttemptId || document.latestAttemptId === attempt.attemptId) {
      document.status = input.status;
      document.latestAttemptId = attempt.attemptId;
      document.submittedAt = attempt.submittedAt;
      document.reviewedAt = reviewedAt;
      document.reviewedBy = identity.authId;
      document.reason = attempt.reviewReason;
    }
    if (driving) {
      const legacyRecord = user.drivingEligibility?.legacyRecord;
      user.drivingEligibility = {
        status: input.status, latestAttemptId: attempt.attemptId,
        submittedAt: attempt.submittedAt, verifiedAt: input.status === 'approved' ? reviewedAt : undefined,
        verifiedBy: identity.authId, reviewNotes: attempt.reviewReason,
        identityMatch: attempt.aiEvidence?.identityMatch ?? 'unavailable',
        licenceClasses: input.status === 'approved' ? input.licenceClasses : [],
        expiresAt: input.status === 'approved' ? input.reviewedExpiry : undefined,
        identityMatchConfirmed: input.status === 'approved',
        classReviewConfirmed: input.status === 'approved',
        legacyRecord,
      };
      attempt.drivingReview = user.drivingEligibility.toObject();
      await user.save();
      await adminModule.service.create({
        actorId: identity.authId, action: `driving_eligibility.${input.status}`,
        targetType: 'user', targetId: user.authId,
        metadata: { attemptId: attempt.attemptId, licenceClasses: user.drivingEligibility.licenceClasses, expiresAt: user.drivingEligibility.expiresAt },
        createdBy: identity.authId,
      });
      await notifyUser({
        userId: user.authId, category: 'verification', type: `driving_eligibility_${input.status}`,
        title: `Driving eligibility ${input.status.replaceAll('_', ' ')}`,
        body: attempt.reviewReason || 'Your vehicle driving eligibility review is complete.',
        entityType: 'user', entityId: user.authId,
      });
      return user;
    }
    user.verification.status = aggregateVerificationStatus(user.verification);
    const existingTier = user.verification.tier;
    user.verification.tier = user.verification.status === 'approved'
      ? input.status === 'approved'
        ? (input.tier ?? (existingTier === 'none' ? 'basic' : existingTier))
        : (existingTier === 'none' ? 'basic' : existingTier)
      : 'none';
    user.verification.documentType = attempt.documentType;
    user.verification.documentRefs = attempt.documentRefs;
    user.verification.ocrResult = attempt.aiEvidence;
    user.verification.reason = input.reason?.trim() ?? '';
    user.verification.reviewedAt = reviewedAt;
    user.verification.reviewedBy = identity.authId;
    user.verification.ocrResult = {
      ...(user.verification.ocrResult ?? {}),
      administratorReview: {
        status: input.status,
        attemptId: attempt.attemptId,
        reviewedBy: identity.authId,
        reviewedAt: new Date(),
      },
    };
    await user.save();
    if (user.roles.includes('owner')) {
      await ListingModel.updateMany(
        { ownerId: user.authId },
        { verified: user.verification.status === 'approved' },
      );
    }
    await Promise.all([
      adminModule.service.create({
        actorId: identity.authId,
        action: `verification.${input.status}`,
        targetType: 'user',
        targetId: user.authId,
        metadata: {
          attemptId: attempt.attemptId,
          documentType: attempt.documentType,
          tier: user.verification.tier,
          reason: user.verification.reason,
        },
        createdBy: identity.authId,
      }),
      notifyUser({
        userId: user.authId,
        category: 'verification',
        type: `verification_${input.status}`,
        title:
          input.status === 'approved'
            ? `${attempt.documentType.replaceAll('_', ' ')} approved`
            : `${attempt.documentType.replaceAll('_', ' ')} needs attention`,
        body:
          input.status === 'approved'
            ? `Your ${attempt.documentType.replaceAll('_', ' ')} has been approved.`
            : user.verification.reason,
        entityType: 'user',
        entityId: user.authId,
      }),
    ]);
    return user;
  },

  async blockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    if (targetId === user.authId || targetId === user.id) {
      throw new AppError('You cannot block your own account', 400, 'INVALID_TARGET');
    }
    const target = await userRepository.findPublicById(targetId);
    if (!target) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (!user.blockedUserIds.includes(target.authId)) {
      user.blockedUserIds.push(target.authId);
      await user.save();
    }
    return user;
  },

  async unblockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    user.blockedUserIds = user.blockedUserIds.filter((id) => id !== targetId);
    await user.save();
    return user;
  },

  async savedListings(identity) {
    const user = await requireCurrentUser(identity);
    return ListingModel.find({
      publicId: { $in: user.savedListingIds },
      status: 'active',
    }).sort({ updatedAt: -1 });
  },

  async saveListing(identity, listingId) {
    const user = await requireCurrentUser(identity);
    const listing = await ListingModel.findOne({ publicId: listingId, status: 'active' });
    if (!listing) throw new AppError('Listing not found', 404, 'NOT_FOUND');
    if (!user.savedListingIds.includes(listingId)) {
      if (user.savedListingIds.length >= 100) {
        throw new AppError('Wishlist limit reached', 409, 'WISHLIST_LIMIT');
      }
      user.savedListingIds.push(listingId);
      await user.save();
    }
    return listing;
  },

  async removeSavedListing(identity, listingId) {
    const user = await requireCurrentUser(identity);
    user.savedListingIds = user.savedListingIds.filter((id) => id !== listingId);
    await user.save();
    return { listingId, saved: false };
  },

  async comparison(identity) {
    const user = await requireCurrentUser(identity);
    return ListingModel.find({
      publicId: { $in: user.comparisonListingIds },
      status: 'active',
    });
  },

  async updateComparison(identity, listingIds) {
    const user = await requireCurrentUser(identity);
    const uniqueIds = [...new Set(listingIds)];
    const listings = await ListingModel.find({
      publicId: { $in: uniqueIds },
      status: 'active',
    });
    if (listings.length !== uniqueIds.length) {
      throw new AppError(
        'Every comparison item must be an active listing',
        400,
        'INVALID_COMPARISON',
      );
    }
    user.comparisonListingIds = uniqueIds;
    await user.save();
    const byId = new Map(listings.map((listing) => [listing.publicId, listing]));
    return uniqueIds.map((id) => byId.get(id));
  },

  async getPublic(id) {
    if (!mongoose.isValidObjectId(id) && !/^u-[a-z0-9-]+$/i.test(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    const user = await userRepository.findPublicById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    return user;
  },

  async list(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);
    const [items, total] = await userRepository.list({
      page,
      limit,
      search: query.search?.trim(),
      role: USER_ROLES.includes(query.role) ? query.role : undefined,
      status: ACCOUNT_STATUSES.includes(query.status) ? query.status : undefined,
    });
    return { items, meta: { page, limit, total } };
  },

  async changeAccountStatus(id, status, reason, identity) {
    if (!mongoose.isValidObjectId(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    if (!ACCOUNT_STATUSES.includes(status)) {
      throw new AppError('Invalid account status', 400, 'INVALID_STATUS');
    }
    if (status !== 'active' && !reason?.trim()) {
      throw new AppError('A reason is required', 400, 'REASON_REQUIRED');
    }
    const user = await userRepository.findById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (status !== 'active' && user.authId === identity.authId) {
      throw new AppError(
        'Administrators cannot restrict their own account from this screen.',
        409,
        'SELF_RESTRICTION_NOT_ALLOWED',
      );
    }
    if (
      status !== 'active' &&
      user.roles.includes('admin') &&
      (await user.constructor.countDocuments({
        roles: 'admin',
        accountStatus: 'active',
      })) <= 1
    ) {
      throw new AppError(
        'The final active administrator cannot be restricted.',
        409,
        'LAST_ACTIVE_ADMIN',
      );
    }
    const previousStatus = user.accountStatus;
    const now = new Date();
    user.accountStatus = status;
    user.accountStatusReason = status === 'active' ? '' : reason.trim();
    user.accountStatusChangedAt = now;
    user.accountStatusChangedBy = identity.authId;
    if (status === 'active') user.reactivatedAt = now;
    if (status === 'deactivated') {
      user.deactivatedAt = now;
      user.deactivatedBy = identity.authId;
    }
    if (status !== 'active') user.accessRevokedAt = now;
    await user.save();
    if (status !== 'active') {
      await Promise.all([
        ListingModel.updateMany(
          {
            ownerId: user.authId,
            status: { $in: ['active', 'pending_review'] },
          },
          { status: 'inactive' },
        ),
        DeviceRegistrationModel.deleteMany({ userId: user.authId }),
        localSessionService.revokeAllForUser(user._id),
      ]);
      disconnectUser(user.authId);
    }
    await Promise.all([
      adminModule.service.create({
        actorId: identity.authId,
        action: `account.${status}`,
        targetType: 'user',
        targetId: user.authId,
        metadata: { previousStatus, reason: user.accountStatusReason },
        createdBy: identity.authId,
      }),
      notifyUser({
        userId: user.authId,
        category: 'account',
        type: `account_${status}`,
        title: status === 'active' ? 'Account reactivated' : `Account ${status}`,
        body:
          status === 'active'
            ? 'Your RentHub account is active again. Please sign in with a new session.'
            : user.accountStatusReason,
        entityType: 'user',
        entityId: user.authId,
      }),
    ]);
    return user;
  },
};
