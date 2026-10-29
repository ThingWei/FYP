export const TRUST_VERSION = 'renthub-trust-v1';
export const TRUST_WINDOW_DAYS = 365;
export const TRUST_MIN_COMPLETIONS = 3;
export const TRUST_MIN_PARTNERS = 2;
const day = 86_400_000;
const date = value => value ? new Date(value).getTime() : NaN;
const money = value => typeof value === 'number' && Number.isFinite(value) && value > 0;

export function realTrustScore(summary) {
  return summary?.status === 'established' && Number.isFinite(summary.score) ? summary.score : 50;
}

function calendarDeadline(value) {
  const parsed = new Date(value);
  return Number.isFinite(+parsed) ? Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate() + 1) - 8 * 3_600_000 - 1 : NaN;
}

function cohortFor(booking, listing, payments) {
  const records = [...new Map(payments.filter(row => typeof row.publicId === 'string' && row.bookingId === booking.publicId).map(row => [row.publicId, row])).values()];
  const captures = records.filter(row => row.type === 'capture' && row.status === 'succeeded' && row.currency === 'MYR' && money(row.amount));
  if (!money(booking.pricing?.baseAmount) || captures.reduce((sum, row) => sum + row.amount, 0) < booking.pricing.baseAmount) return null;
  const snapshot = booking.pricingEvidenceSnapshot;
  if (booking.sourceType === 'demo_seed' || listing?.sourceType === 'demo_seed' || snapshot?.sourceType === 'demo_seed' ||
      records.some(row => row.simulated === true || typeof row.gatewayReference === 'string' && row.gatewayReference.startsWith('sim_'))) return 'demo';
  if (booking.sourceType !== 'marketplace' || (snapshot?.sourceType ?? listing?.sourceType) !== 'marketplace' ||
      captures.some(row => row.simulated !== false || typeof row.gatewayReference !== 'string' || !row.gatewayReference)) return null;
  return 'marketplace';
}

function summary(events, userId, role, reviews, now, truncated) {
  const partners = new Set(), byRental = new Map();
  let faults = 0, issues = 0, measured = 0, timely = 0;
  for (const event of events) {
    const actualRole = event.booking.ownerId === userId ? 'owner' : 'renter';
    if (role !== 'overall' && actualRole !== role) continue;
    byRental.set(event.rental.publicId, { ...event, actualRole });
    partners.add(actualRole === 'owner' ? event.booking.renterId : event.booking.ownerId);
    const responsible = event.dispute?.resolution?.responsibleParty;
    if (responsible === actualRole || responsible === 'both') { faults += responsible === 'both' ? .5 : 1; issues++; }
    let observed, deadline;
    if (event.rental.listingType === 'physical') {
      observed = date(actualRole === 'renter' ? event.rental.returnSubmission?.recordedAt : event.rental.handover?.recordedAt);
      deadline = calendarDeadline(actualRole === 'renter' ? event.rental.endDate : event.rental.startDate);
    } else if (actualRole === 'owner') {
      observed = date(event.rental.serviceDeliveredAt); deadline = date(event.rental.endDate);
    }
    if (Number.isFinite(observed) && observed <= +now && Number.isFinite(deadline)) { measured++; if (observed <= deadline) timely++; }
  }
  const received = new Map();
  for (const review of reviews) {
    const event = byRental.get(review.rentalId);
    if (!event || review.subjectId !== userId || review.subjectRole !== event.actualRole || review.bookingId !== event.booking.publicId ||
        review.authorId !== (event.actualRole === 'owner' ? event.booking.renterId : event.booking.ownerId) ||
        review.authorRole !== (event.actualRole === 'owner' ? 'renter' : 'owner') || review.status !== 'published' ||
        !Number.isFinite(review.overallRating) || review.overallRating < 1 || review.overallRating > 5 ||
        !Number.isFinite(date(review.createdAt)) || date(review.createdAt) < date(event.booking.completedAt) || date(review.createdAt) > +now) continue;
    const previous = received.get(review.rentalId);
    if (!previous || date(review.editedAt ?? review.createdAt) > date(previous.editedAt ?? previous.createdAt)) received.set(review.rentalId, review);
  }
  const n = byRental.size, ratings = [...received.values()], ratingSum = ratings.reduce((sum, row) => sum + row.overallRating, 0);
  const parts = [{ value: 100 * (n - faults + 2) / (n + 4), weight: .55 }];
  parts.push({ value: (ratingSum * 20 + 200) / (ratings.length + 4), weight: .25 });
  if (measured) parts.push({ value: 100 * (timely + 2) / (measured + 4), weight: .20 });
  const established = !truncated && n >= TRUST_MIN_COMPLETIONS && partners.size >= TRUST_MIN_PARTNERS;
  return {
    status: truncated ? 'unavailable' : established ? 'established' : 'insufficient_history',
    score: established ? Math.round(Math.max(0, Math.min(100, parts.reduce((sum, part) => sum + part.value * part.weight, 0) / parts.reduce((sum, part) => sum + part.weight, 0)))) : null,
    completedRentals: n, distinctPartners: partners.size, reviewCount: ratings.length,
    averageRating: ratings.length ? Math.round(10 * ratingSum / ratings.length) / 10 : null,
    timelyRentals: timely, measuredTimeliness: measured, confirmedIssues: issues,
  };
}

// Server-recorded facts only. Neither ratings on unrelated rentals nor an open
// report, deposit deduction or monetary settlement implies responsibility.
export function calculateTrustProfile(userId, { bookings = [], rentals = [], payments = [], reviews = [], disputes = [], listings = [], truncated = false } = {}, now = new Date()) {
  const cutoff = +now - TRUST_WINDOW_DAYS * day;
  const rentalByBooking = new Map(rentals.map(row => [row.bookingId, row]));
  const listingById = new Map(listings.map(row => [row.publicId, row]));
  const resolved = new Map(disputes.filter(row => row.status === 'resolved' && row.resolution?.outcome !== 'dismissed' &&
    Number.isFinite(date(row.resolution?.resolvedAt)) && date(row.resolution.resolvedAt) <= +now).map(row => [row.rentalId, row]));
  const cohorts = { marketplace: [], demo: [] };
  const seen = new Set();
  for (const booking of bookings) {
    const rental = rentalByBooking.get(booking.publicId), completedAt = date(booking.completedAt);
    if (!booking.publicId || seen.has(booking.publicId) || !rental || !rental.publicId ||
        !['completed', 'disputed'].includes(booking.status) || !['completed', 'disputed'].includes(rental.status) ||
        !Number.isFinite(completedAt) || completedAt < cutoff || completedAt > +now ||
        typeof booking.ownerId !== 'string' || !booking.ownerId || typeof booking.renterId !== 'string' || !booking.renterId ||
        ![booking.ownerId, booking.renterId].includes(userId) || booking.ownerId === booking.renterId ||
        rental.ownerId !== booking.ownerId || rental.renterId !== booking.renterId || rental.listingId !== booking.listingId || rental.listingType !== booking.listingType) continue;
    const provenance = cohortFor(booking, listingById.get(booking.listingId), payments.filter(row => date(row.createdAt) <= +now));
    if (!provenance) continue;
    seen.add(booking.publicId);
    cohorts[provenance].push({ booking, rental, dispute: resolved.get(rental.publicId) });
  }
  return { version: TRUST_VERSION, windowDays: TRUST_WINDOW_DAYS, calculatedAt: now,
    minimumCompletions: TRUST_MIN_COMPLETIONS, minimumPartners: TRUST_MIN_PARTNERS,
    ...Object.fromEntries(['overall', 'owner', 'renter'].map(role => [role, Object.fromEntries(Object.entries(cohorts).map(([source, events]) => [source, summary(events, userId, role, reviews, now, truncated)]))])),
  };
}

export function ownerTrustSummary(profile) {
  return { version: profile.version, calculatedAt: profile.calculatedAt, windowDays: profile.windowDays,
    minimumCompletions: profile.minimumCompletions, minimumPartners: profile.minimumPartners, ...profile.owner };
}
