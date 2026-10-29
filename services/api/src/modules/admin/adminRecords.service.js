import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { UserModel } from '../user/user.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { ReviewModel } from '../review/review.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ClaimModel } from '../dispute/claim.model.js';
import { MessageReportModel } from '../communication/messageReport.model.js';
import { ModerationReportModel } from './moderationReport.model.js';
import { GeneratedReportModel, ReportScheduleModel } from './report.model.js';
import { RewardLedgerModel, ReferralModel } from '../loyalty/loyalty.model.js';
import { PricingReferenceModel } from '../listing/pricingReference.model.js';
import { verificationRecordsFilter, verificationRecordSummary, VERIFICATION_RECORD_STATUSES } from './adminVerificationRecords.js';

const common = 'publicId createdAt updatedAt status';
const entry = (model, fields, search, statusField = 'status') => ({ model, fields: `${common} ${fields}`, search, statusField });
const pendingVerification = verificationRecordsFilter({ status: 'pending' });
export function adminRecordRegistry(auditModel) {
  const userFields = 'authId displayName email phone roles activeRole accountStatus accountStatusReason verification drivingEligibility trustScore trustProfile';
  return {
    users: entry(UserModel, userFields, ['displayName', 'email'], 'accountStatus'),
    verification: entry(UserModel, userFields, ['displayName', 'email']),
    listings: entry(ListingModel, 'title description ownerId ownerName listingType category subcategory brand productModel dailyPrice securityDeposit deliveryFee fulfilmentMethods condition itemAgeYears images verified itemVerification moderationReason serviceDetails', ['title', 'brand', 'productModel', 'ownerName']),
    bookings: entry(BookingModel, 'listingId listingTitle listingType renterId renterName ownerId ownerName category startDate endDate fulfilmentMethod serviceVenue serviceVenueMode paymentStatus pricing extensionCharges agreement renterNote ownerDecisionReason cancellationReason decidedAt cancelledAt activatedAt completedAt expiredAt expiresAt sourceType', ['publicId', 'listingTitle', 'renterName', 'ownerName']),
    rentals: entry(RentalModel, 'bookingId listingId listingType renterId ownerId category startDate endDate handover returnSubmission returnOutcome serviceDeliveredAt serviceCompletedAt extension extensionHistory', ['publicId', 'bookingId', 'listingId']),
    transactions: entry(PaymentModel, 'bookingId payerId payeeId amount currency type method status simulated reason metadata', ['publicId', 'bookingId', 'type']),
    disputes: entry(DisputeModel, 'bookingId rentalId listingId listingTitle listingType raisedById raisedByName raisedByRole respondentId respondentName respondentRole category summary reason description evidence responses resolution history priority adminNote createdAt', ['publicId', 'listingTitle', 'description']),
    claims: entry(ClaimModel, 'disputeId rentalId bookingId listingId listingTitle ownerId renterId amountRequested description evidence status decision', ['publicId', 'listingTitle', 'description']),
    reports: entry(ModerationReportModel, 'targetType targetId targetLabel reporterId reason details resolution reviewedAt reviewedBy', ['publicId', 'targetLabel', 'reason', 'details']),
    'message-reports': entry(MessageReportModel, 'messageId threadId reporterId reportedUserId reason details messageText resolution reviewedAt reviewedBy', ['publicId', 'reason', 'details']),
    reviews: entry(ReviewModel, 'bookingId rentalId listingId listingTitle listingType authorId authorName authorRole subjectId subjectName subjectRole overallRating communicationRating conditionRating valueRating text flag moderation editedAt', ['publicId', 'listingTitle', 'authorName', 'subjectName', 'text']),
    'audit-logs': entry(auditModel, 'actorId action targetType targetId metadata createdBy', ['action', 'targetType', 'targetId'], null),
    'generated-reports': entry(GeneratedReportModel, 'name reportType generationKind periodStart periodEnd fileName rowCount truncated summary createdBy scheduleId format', ['publicId', 'fileName', 'reportType'], null),
    'report-schedules': entry(ReportScheduleModel, 'name reportType cadence rangeDays enabled nextRunAt lastRunAt lastReportId createdBy updatedBy', ['publicId', 'name', 'reportType'], null),
    referrals: entry(ReferralModel, 'referralCode referrerId refereeId status appliedAt rewardedAt qualifyingBookingId refereeRewardAmount', ['publicId', 'referralCode']),
    'reward-history': entry(RewardLedgerModel, 'userId type points balanceAfter description sourceType sourceId reward', ['publicId', 'description', 'type'], null),
    'pricing-references': entry(PricingReferenceModel, 'category subcategory brand productModel quotedAmount rentalDurationDays dailyPrice currency sourceName sourceUrl observedAt condition itemAgeYears packageNotes variant edition isbn packageType includedLens active collectionMethod', ['brand', 'productModel', 'sourceName'], 'active'),
  };
}

const blockedKey = /password|secret|token|fingerprint|ocr.?text|raw.?text|ic.?number|identity.?number|document.?number|gatewayReference|idempotency|storagePath|lockedUntil|stack|traceback/i;
export function safeAdminValue(value, depth = 0) {
  if (depth > 10) return undefined;
  if (value instanceof Date) return value.toISOString();
  if (value instanceof mongoose.Types.ObjectId) return String(value);
  if (Array.isArray(value)) return value.map(v => safeAdminValue(v, depth + 1)).filter(v => v !== undefined);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !blockedKey.test(key) && !['__v', 'extracted_fields', 'extractedFields', 'content', 'lastError'].includes(key))
    .map(([key, v]) => [key, safeAdminValue(v, depth + 1)]).filter(([, v]) => v !== undefined));
  return value;
}
const auditMetadataKeys = new Set(['reason', 'status', 'outcome', 'amount', 'renterAmount', 'ownerAmount', 'enabled', 'acceptedCount', 'skippedCount', 'count', 'note']);
const identityFilter = (model, id) => {
  if (typeof id !== 'string' || !id.length || id.length > 160 || /[\x00-\x1f]/.test(id)) throw new AppError('Invalid record reference', 422, 'VALIDATION_ERROR');
  const alternatives = [];
  if (model.schema.path('publicId')) alternatives.push({ publicId: id });
  if (model === UserModel) alternatives.push({ authId: id });
  if (mongoose.isValidObjectId(id)) alternatives.push({ _id: id });
  if (!alternatives.length) throw new AppError('Record not found', 404, 'NOT_FOUND');
  return { $or: alternatives };
};
function options(query) {
  const number = (name, fallback, max) => {
    const value = query[name] ?? `${fallback}`;
    if (typeof value !== 'string' || !/^\d+$/.test(value) || +value < 1 || +value > max) throw new AppError('Choose a valid page and page size', 422, 'VALIDATION_ERROR');
    return +value;
  };
  for (const field of ['search', 'status', 'documentType', 'sort']) if (query[field] !== undefined &&
      (typeof query[field] !== 'string' || query[field].length > 100)) throw new AppError('Invalid filter', 422, 'VALIDATION_ERROR');
  return { page: number('page', 1, 100000), limit: number('limit', 20, 100) };
}
const literal = value => new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
export function createAdminRecordsService(auditModel) {
  const registry = adminRecordRegistry(auditModel);
  const spec = type => { if (!Object.hasOwn(registry, type)) throw new AppError('Record type not found', 404, 'NOT_FOUND'); return registry[type]; };
  function project(doc, type, accountNames = {}, bookings = {}) {
    const raw = doc.toObject ? doc.toObject() : doc;
    if (type === 'rentals') {
      const booking = bookings[raw.bookingId];
      // These names come from the booking snapshot, never today's profile.
      if (booking) for (const key of ['listingTitle', 'renterName', 'ownerName']) raw[key] = booking[key];
    }
    if (type === 'users' || type === 'verification') {
      raw.trustScore = raw.trustProfile?.version === 'renthub-trust-v1' && raw.trustProfile.overall?.marketplace?.status === 'established'
        ? raw.trustProfile.overall.marketplace.score : 50;
      raw.verificationSummary = verificationRecordSummary(raw);
      const check = value => value && Object.fromEntries(['status', 'documentType', 'reason', 'submittedAt', 'reviewedAt', 'verifiedAt', 'reviewNotes', 'identityMatch', 'documentRefs', 'licenceClasses', 'expiresAt', 'latestAttemptId', 'holderMatch']
        .filter(key => value[key] !== undefined).map(key => [key, value[key]]));
      const attempt = value => ({ ...check(value), attemptId: value.attemptId, reviewReason: value.reviewReason,
        aiEvidence: value.aiEvidence ? { outcome: value.aiEvidence.outcome, identityMatch: value.aiEvidence.identityMatch } : undefined });
      const verification = raw.verification;
      raw.verification = verification ? { ...check(verification), history: (verification.history ?? []).map(attempt),
        ocrResult: verification.ocrResult ? { outcome: verification.ocrResult.outcome, identityMatch: verification.ocrResult.identityMatch } : undefined } : undefined;
      raw.drivingEligibility = check(raw.drivingEligibility);
    }
    if (type === 'audit-logs') raw.metadata = Object.fromEntries(Object.entries(raw.metadata ?? {}).filter(([key]) => auditMetadataKeys.has(key)));
    if (type === 'transactions') raw.metadata = { simulationOutcome: raw.metadata?.simulationOutcome };
    const result = safeAdminValue(raw);
    result.id = String(raw.publicId ?? raw._id);
    if (raw._id) result._id = String(raw._id); // Existing user moderation requires its database identifier.
    result.accountNames = accountNames;
    return result;
  }
  async function accountsFor(docs) {
    const fields = ['actorId', 'reporterId', 'reportedUserId', 'renterId', 'ownerId', 'payerId', 'payeeId', 'referrerId', 'refereeId', 'userId', 'claimantId', 'reviewedBy', 'createdBy'];
    const ids = [...new Set(docs.flatMap(doc => [...fields.map(key => doc[key]), doc.resolution?.resolvedBy, doc.decision?.decidedBy, doc.moderation?.moderatedBy]).filter(v => typeof v === 'string'))];
    if (!ids.length) return {};
    const users = await UserModel.find({ authId: { $in: ids } }).select('authId displayName').lean();
    return Object.fromEntries(users.map(user => [user.authId, user.displayName]));
  }
  async function rentalBookings(type, docs) {
    if (type !== 'rentals' || !docs.length) return {};
    const rows = await BookingModel.find({ publicId: { $in: docs.map(row => row.bookingId) } })
      .select('publicId listingTitle renterName ownerName').lean();
    return Object.fromEntries(rows.map(row => [row.publicId, row]));
  }
  const listFields = {
    users: 'authId displayName email roles accountStatus', verification: 'authId displayName email verification.status verification.documentType verification.submittedAt verification.reviewedAt verification.documents.documentType verification.documents.status verification.documents.submittedAt verification.documents.reviewedAt verification.history.documentType verification.history.status verification.history.submittedAt verification.history.reviewedAt drivingEligibility.status drivingEligibility.submittedAt drivingEligibility.verifiedAt',
    listings: 'title listingType dailyPrice ownerName ownerId', bookings: 'listingTitle listingType pricing.total renterName renterId ownerName ownerId',
    rentals: 'bookingId listingId listingType renterId ownerId', transactions: 'type amount simulated bookingId payerId payeeId',
    disputes: 'listingTitle summary category', claims: 'listingTitle description amountRequested', reports: 'targetLabel reason', 'message-reports': 'reason',
    reviews: 'authorName subjectName overallRating listingTitle flag.reason', 'audit-logs': 'actorId action targetType targetId',
    'generated-reports': 'fileName reportType', 'report-schedules': 'name reportType cadence enabled', referrals: 'referralCode referrerId refereeId',
    'reward-history': 'description points userId', 'pricing-references': 'brand productModel quotedAmount rentalDurationDays sourceName observedAt active',
  };
  return {
    async list(type, query = {}) {
      const config = spec(type), { page, limit } = options(query), clauses = [];
      if (query.documentType && type !== 'verification') throw new AppError('Document filters apply to verification requests only', 422, 'VALIDATION_ERROR');
      if (type === 'verification') {
        if (query.status && query.status !== 'all' && !VERIFICATION_RECORD_STATUSES.includes(query.status)) throw new AppError('Choose a valid verification status', 422, 'VALIDATION_ERROR');
        if (query.documentType && !['all', 'mykad', 'driving_licence'].includes(query.documentType)) throw new AppError('Choose a valid document type', 422, 'VALIDATION_ERROR');
        clauses.push(verificationRecordsFilter({ status: query.status, documentType: query.documentType }));
      } else if (query.status && query.status !== 'all') {
        if (!config.statusField) throw new AppError('This collection has no status filter', 422, 'VALIDATION_ERROR');
        const allowed = config.statusField === 'active' ? ['active', 'inactive'] : config.model.schema.path(config.statusField)?.enumValues;
        if (!allowed?.includes(query.status)) throw new AppError('Choose a valid status filter', 422, 'VALIDATION_ERROR');
      }
      if (config.base) clauses.push(config.base);
      if (type !== 'verification' && query.status && query.status !== 'all' && config.statusField) clauses.push({ [config.statusField]: config.statusField === 'active' ? query.status === 'active' : query.status });
      if (query.search?.trim()) clauses.push({ $or: config.search.map(field => ({ [field]: literal(query.search.trim()) })) });
      const filter = clauses.length ? { $and: clauses } : {};
      const sort = { createdAt: -1, _id: -1 };
      const [docs, total] = await Promise.all([config.model.find(filter).select(`${common} ${listFields[type]}`).sort(sort).skip((page - 1) * limit).limit(limit).lean(), config.model.countDocuments(filter)]);
      const [names, bookings] = await Promise.all([accountsFor(docs), rentalBookings(type, docs)]);
      return { items: docs.map(doc => project(doc, type, names, bookings)), meta: { page, limit, total } };
    },
    async get(type, id) {
      const config = spec(type);
      const doc = await config.model.findOne(identityFilter(config.model, id)).select(config.fields).lean();
      if (!doc) throw new AppError('This record is no longer available', 404, 'NOT_FOUND');
      const [names, bookings] = await Promise.all([accountsFor([doc]), rentalBookings(type, [doc])]);
      return { recordType: type, record: project(doc, type, names, bookings) };
    },
    async summary() {
      const [users, pendingListings, bookings, openReports, openMessages, flaggedReviews, verification] = await Promise.all([
        UserModel.countDocuments(), ListingModel.countDocuments({ status: 'pending_review' }), BookingModel.countDocuments(),
        ModerationReportModel.countDocuments({ status: 'open' }), MessageReportModel.countDocuments({ status: 'open' }),
        ReviewModel.countDocuments({ 'flag.reason': { $exists: true, $ne: '' } }), UserModel.countDocuments(pendingVerification),
      ]);
      return { users, pendingListings, bookings, openReports: openReports + openMessages, flaggedReviews, verification, checkedAt: new Date() };
    },
  };
}
