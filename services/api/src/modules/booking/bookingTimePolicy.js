import { physicalRentalDate } from '../../core/calendarDate.js';
import { AppError } from '../../core/errors.js';

export function assertBookingTimeAvailable(listing, input, now = new Date()) {
  const today = +physicalRentalDate(now);
  if (listing.listingType === 'service') {
    const start = new Date(input.startDate);
    if (+physicalRentalDate(start) === today && start <= now) throw new AppError('Choose a service time later than now.', 422, 'APPOINTMENT_TIME_PASSED');
    return;
  }
  for (const [date, time] of [[input.startDate, input.pickupTime], [input.endDate, input.returnTime]]) {
    if (+physicalRentalDate(date) !== today || !/^\d{2}:\d{2}$/.test(time ?? '')) continue;
    const [hour, minute] = time.split(':').map(Number);
    const instant = new Date(today + ((hour - 8) * 60 + minute) * 60000);
    if (instant <= now) throw new AppError('This appointment time has passed. Choose a later time.', 422, 'APPOINTMENT_TIME_PASSED');
  }
}
