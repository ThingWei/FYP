export const blockingBookingCriteria = () => ({
  $or: [
    { status: { $in: ['approved', 'active'] } },
    { status: 'disputed', listingType: 'physical' },
  ],
});

export function bookingDateOverlapCriteria(start, exclusiveEnd) {
  return {
    startDate: { $lt: exclusiveEnd },
    endDate: { $gte: start },
  };
}

export function nextAvailableDate(ranges, from = new Date()) {
  let cursor = new Date(Date.UTC(
    from.getUTCFullYear(),
    from.getUTCMonth(),
    from.getUTCDate(),
  ));
  const sorted = [...ranges].sort((left, right) => left.start - right.start);
  let changed = true;
  while (changed) {
    changed = false;
    for (const range of sorted) {
      if (range.start <= cursor && range.end > cursor) {
        cursor = new Date(range.end);
        changed = true;
      }
    }
  }
  return cursor;
}
