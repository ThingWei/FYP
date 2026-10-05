const dateOnlyPattern = /^(\d{4})-(\d{2})-(\d{2})$/;
const malaysiaDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Kuala_Lumpur',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

function checkedUtcDate(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new RangeError('Invalid calendar date');
  }
  return date;
}

/**
 * Converts a renter-selected Malaysian calendar day to UTC midnight storage.
 * Date-only values are never interpreted as instants. Timestamp input remains
 * supported for older clients and is resolved in the marketplace timezone.
 */
export function physicalRentalDate(value) {
  if (typeof value === 'string') {
    const match = dateOnlyPattern.exec(value);
    if (match) {
      return checkedUtcDate(Number(match[1]), Number(match[2]), Number(match[3]));
    }
  }

  const instant = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(instant.getTime())) throw new RangeError('Invalid calendar date');
  const parts = Object.fromEntries(
    malaysiaDateFormatter
      .formatToParts(instant)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return checkedUtcDate(Number(parts.year), Number(parts.month), Number(parts.day));
}

export function calendarDateString(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new RangeError('Invalid calendar date');
  const year = date.getUTCFullYear().toString().padStart(4, '0');
  const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = date.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}
