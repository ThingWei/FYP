import { UserModel } from './user.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { ReviewModel } from '../review/review.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { calculateTrustProfile, realTrustScore, ownerTrustSummary, TRUST_VERSION, TRUST_WINDOW_DAYS } from './trustPolicy.js';
import { AppError } from '../../core/errors.js';

const maximum = 1000;
export async function computeTrustProfile(userId, now = new Date()) {
  const bookings = await BookingModel.find({ $or: [{ ownerId: userId }, { renterId: userId }],
    completedAt: { $gte: new Date(+now - TRUST_WINDOW_DAYS * 86_400_000), $lte: now }, status: { $in: ['completed', 'disputed'] } })
    .select('publicId ownerId renterId listingId listingType sourceType completedAt startDate endDate status pricing.baseAmount pricingEvidenceSnapshot.sourceType')
    .sort({ completedAt: -1, _id: -1 }).limit(maximum + 1).lean();
  const ids = bookings.slice(0, maximum).map(row => row.publicId);
  const [rentals, payments, reviews, disputes, listings] = ids.length ? await Promise.all([
    RentalModel.find({ bookingId: { $in: ids } }).select('publicId bookingId listingId listingType ownerId renterId status startDate endDate handover.recordedAt returnSubmission.recordedAt serviceDeliveredAt').lean(),
    PaymentModel.find({ bookingId: { $in: ids } }).select('publicId bookingId type status amount currency simulated gatewayReference createdAt').limit(20001).lean(),
    ReviewModel.find({ bookingId: { $in: ids }, subjectId: userId, status: 'published' }).select('rentalId bookingId authorId authorRole subjectId subjectRole status overallRating createdAt editedAt').lean(),
    DisputeModel.find({ bookingId: { $in: ids }, status: 'resolved' }).select('rentalId status resolution.outcome resolution.resolvedAt resolution.responsibleParty').lean(),
    ListingModel.find({ publicId: { $in: [...new Set(bookings.map(row => row.listingId))] } }).select('publicId sourceType').lean(),
  ]) : [[], [], [], [], []];
  return calculateTrustProfile(userId, { bookings: bookings.slice(0, maximum), rentals, payments, reviews, disputes, listings, truncated: bookings.length > maximum || payments.length > 20000 }, now);
}

export async function refreshTrustProfile(userId, { force = false } = {}) {
  return withOperationLock('trust-profile', userId, async ensureOwned => {
    const user = await UserModel.findOne({ authId: userId }).select('authId trustProfile').lean();
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    const cached = user.trustProfile;
    if (!force && cached?.version === TRUST_VERSION && +new Date(cached.calculatedAt) <= Date.now() && +new Date(cached.calculatedAt) > Date.now() - 60_000) return cached;
    const profile = await computeTrustProfile(userId);
    await ensureOwned();
    await UserModel.updateOne({ authId: userId }, { $set: { trustProfile: profile, trustScore: realTrustScore(profile.overall.marketplace) } }, { timestamps: false });
    await ensureOwned();
    await ListingModel.updateMany({ ownerId: userId }, { $set: { ownerTrustProfile: ownerTrustSummary(profile), ownerTrustScore: realTrustScore(profile.owner.marketplace) } }, { timestamps: false });
    return profile;
  });
}

export async function refreshTrustAfterActivity(userIds) {
  // Financial/lifecycle writes are already committed. A cache failure must not
  // tell a caller to repeat a successful payment or moderation action.
  for (const userId of [...new Set(userIds.filter(Boolean))]) {
    try { await refreshTrustProfile(userId, { force: true }); }
    catch {
      await Promise.allSettled([
        UserModel.updateOne({ authId: userId }, { $unset: { trustProfile: 1 }, $set: { trustScore: 50 } }, { timestamps: false }),
        ListingModel.updateMany({ ownerId: userId }, { $unset: { ownerTrustProfile: 1 }, $set: { ownerTrustScore: 50 } }, { timestamps: false }),
      ]);
      console.error('Trust summary refresh deferred');
    }
  }
}

export async function withTrustProfile(user) {
  const profile = await availableTrustProfile(user.authId);
  user.trustProfile = profile;
  user.trustScore = realTrustScore(profile.overall.marketplace);
  return user;
}

export async function availableTrustProfile(userId) {
  try { return await refreshTrustProfile(userId); }
  catch {
    // Reputation is optional context. Its cache must not block sign-in,
    // listing creation or manual pricing when the underlying facts are unavailable.
    return calculateTrustProfile(userId, { truncated: true });
  }
}
