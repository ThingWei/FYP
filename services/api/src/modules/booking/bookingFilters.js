import { physicalRentalDate } from '../../core/calendarDate.js';

const day = 24 * 60 * 60 * 1000;
const literal = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export function bookingListFilter(query = {}) {
  const filter = {};
  for (const key of ['status', 'listingType', 'paymentStatus', 'category']) {
    if (query[key]) filter[key] = query[key];
  }
  if (typeof query.q === 'string' && query.q.trim()) {
    const expression = { $regex: literal(query.q.trim()), $options: 'i' };
    filter.$or = ['publicId', 'listingTitle', 'ownerName', 'renterName'].map((key) => ({ [key]: expression }));
  }
  if (query.fromDate || query.toDate) {
    const from = query.fromDate ? physicalRentalDate(query.fromDate) : null;
    const to = query.toDate ? physicalRentalDate(query.toDate) : null;
    // Physical dates are calendar days; service instants are compared to MYT
    // day boundaries. Match any overlap, not only bookings starting in the range.
    filter.$and = [{ $or: [
      { listingType: 'physical', ...(from && { endDate: { $gte: from } }), ...(to && { startDate: { $lte: to } }) },
      { listingType: 'service', ...(from && { endDate: { $gt: new Date(from.getTime() - 8 * 60 * 60 * 1000) } }),
        ...(to && { startDate: { $lt: new Date(to.getTime() + day - 8 * 60 * 60 * 1000) } }) },
    ] }];
  }
  return filter;
}

export function bookingListSort(sort) {
  return ({ oldest: { createdAt: 1, _id: 1 }, start_soonest: { startDate: 1, _id: 1 },
    start_latest: { startDate: -1, _id: -1 } })[sort] ?? { createdAt: -1, _id: -1 };
}
