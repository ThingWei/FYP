// Project-showcase maintenance only. Generated history never becomes clean market evidence.
import { createHash } from 'node:crypto';
import { BookingModel } from '../modules/booking/booking.model.js';
import { RentalModel } from '../modules/rental/rental.model.js';
import { PaymentModel } from '../modules/payment/payment.model.js';
import { hasApprovedMykad } from '../modules/user/drivingEligibility.js';

export const SHOWCASE_BATCH = 'showcase-20261114-v1';
const digest = value => createHash('sha256').update(JSON.stringify(value) ?? 'undefined').digest('hex');
const cents = value => Math.round(Number(value) * 100);
const money = value => value / 100;
export const showcaseTitle = title => String(title).replace(/^\s*\[(?:demo|sample)\]\s*/i, '');

export function assertShowcaseOwner(owner, listing) {
  if (listing.sourceType !== 'demo_seed' || listing.status !== 'active' || !owner ||
      owner.authId !== listing.ownerId || owner.accountStatus !== 'active' ||
      !owner.roles?.includes('owner') || !hasApprovedMykad(owner)) {
    throw new Error('Only existing active showcase inventory of a verified Owner is eligible');
  }
}

export function photoRefreshFields(listing, owner, photo) {
  assertShowcaseOwner(owner, listing);
  if (!photo.reviewed || !/^upload:\/\/UPL-[A-Z0-9]+$/.test(photo.reference) ||
      !/^https:\/\//.test(photo.sourceUrl) || !/^[a-f0-9]{64}$/.test(photo.sha256)) {
    throw new Error('A reviewed stored photo and source credit are required');
  }
  const title = showcaseTitle(listing.title);
  return { title, images: [photo.reference],
    description: `${title}. ${listing.listingType === 'service'
      ? 'Contact the Owner to discuss the package and availability.'
      : `Condition: ${listing.condition || 'Not specified'}. Collection by arrangement.`}\nPhoto credit: ${photo.sourceUrl}`,
    verified: false,
  };
}

// No approvals, signatures, evidence photos, reviews or chain receipts are invented.
// Completion dates and ledger entries are explicitly generated showcase history.
export async function buildShowcaseCompletion(listing, owner, renter, { day, now = new Date() }) {
  assertShowcaseOwner(owner, listing);
  if (!renter || renter.authId === owner.authId || renter.accountStatus !== 'active' ||
      !renter.roles?.includes('renter') || !hasApprovedMykad(renter)) throw new Error('A different verified participant is required');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new Error('A calendar day is required');
  const startDate = new Date(day + 'T00:00:00.000Z');
  const completedAt = new Date(day + 'T12:00:00.000Z');
  if (!Number.isFinite(+startDate) || startDate.toISOString().slice(0,10) !== day || completedAt >= now) throw new Error('Only past showcase dates are supported');
  const code = digest([SHOWCASE_BATCH, listing.publicId, renter.authId]).slice(0,12).toUpperCase();
  const bookingId = `RH-${listing.listingType === 'service' ? 'SVC' : 'BKG'}-${day.slice(0,4)}-SC${code}`;
  const base = cents(listing.dailyPrice), deposit = listing.listingType === 'physical' ? cents(listing.securityDeposit || 0) : 0;
  if (!Number.isSafeInteger(base) || base <= 0 || !Number.isSafeInteger(deposit) || deposit < 0) throw new Error('Valid saved charges are required');
  const total = base + deposit;
  const booking = new BookingModel({ publicId: bookingId, listingId: listing.publicId,
    listingTitle: showcaseTitle(listing.title), listingType: listing.listingType, category: listing.category,
    ownerId: owner.authId, ownerName: owner.displayName, renterId: renter.authId, renterName: renter.displayName,
    startDate, endDate: startDate, status: 'completed', paymentStatus: 'settled', completedAt,
    ...(listing.listingType === 'physical' ? { fulfilmentMethod: 'pickup' } : { serviceVenue: 'Venue details not recorded' }),
    sourceType: 'demo_seed',
    pricing: { baseAmount: money(base), securityDeposit: money(deposit), damageWaiverFee: 0,
      platformFee: 0, deliveryFee: 0, total: money(total), currency: 'MYR', originalRentalDays: 1, originalDailyRate: money(base) },
    pricingEvidenceSnapshot: { sourceType: 'demo_seed', origin: 'generated_showcase', batch: SHOWCASE_BATCH,
      priceProvenance: listing.priceProvenance || { origin: 'unknown' }, brand: listing.brand,
      productModel: listing.productModel, subcategory: listing.subcategory },
    createdAt: startDate, updatedAt: completedAt });
  const rental = new RentalModel({ publicId: `RH-RNT-${day.slice(0,4)}-SC${code}`, bookingId, listingId: listing.publicId,
    listingType: listing.listingType, category: listing.category, ownerId: owner.authId, renterId: renter.authId,
    startDate, endDate: startDate, status: 'completed', createdAt: startDate, updatedAt: completedAt });
  const payment = (type, amount, payerId, payeeId) => new PaymentModel({ publicId: `TXN-SC${code}-${type.toUpperCase()}`,
    bookingId, payerId, payeeId, type, amount: money(amount), currency: 'MYR', method: 'system', status: 'succeeded',
    gatewayReference: `showcase-${code}-${type}`, idempotencyKey: `${SHOWCASE_BATCH}:${code}:${type}`,
    simulated: true, metadata: { origin: 'generated_showcase', batch: SHOWCASE_BATCH }, createdAt: completedAt, updatedAt: completedAt });
  const payments = [payment('capture', total, renter.authId, 'renthub'),
    payment('owner_settlement', base, 'renthub', owner.authId),
    ...(deposit ? [payment('deposit_release', deposit, 'renthub', renter.authId)] : [])];
  await booking.validate(); await rental.validate();
  for (const row of payments) await row.validate();
  const plain = row => { const object = row.toObject({flattenMaps:true}); delete object._id; return object; };
  return { booking: plain(booking), rental: plain(rental), payments: payments.map(plain) };
}

export async function saveShowcaseCompletion(db, plan, { apply = false } = {}) {
  if (plan.booking.sourceType !== 'demo_seed' || plan.booking.pricingEvidenceSnapshot?.batch !== SHOWCASE_BATCH ||
      plan.payments.some(row => row.simulated !== true || row.metadata?.batch !== SHOWCASE_BATCH)) throw new Error('Showcase provenance required');
  const documents = [['bookings', plan.booking], ['rentals', plan.rental], ...plan.payments.map(row => ['payments', row])];
  // Check every collision before writing anything. A rerun never replaces existing records.
  for (const [collection, row] of documents) {
    const existing = await db.collection(collection).findOne({publicId:row.publicId});
    if (existing) {
      for (const key of Object.keys(row)) {
        if (digest(existing[key]) !== digest(row[key])) throw new Error('Existing showcase record changed; preserved for review');
      }
    }
  }
  if (!apply) return {planned:documents.length,written:0};
  let written = 0;
  for (const [collection, row] of documents) {
    const result = await db.collection(collection).updateOne({publicId:row.publicId}, {$setOnInsert:row}, {upsert:true});
    written += result.upsertedCount;
  }
  return {planned:documents.length,written};
}
