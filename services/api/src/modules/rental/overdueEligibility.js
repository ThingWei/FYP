import { RentalModel } from './rental.model.js';
import { physicalRentalDate } from '../../core/calendarDate.js';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { BookingModel } from '../booking/booking.model.js';

export async function assertNoOverdueReturn(renterId, now = new Date()) {
  // Inclusive UTC-stored rental days become overdue after Malaysia midnight
  // plus grace. Filter before limiting, including legacy non-midnight values.
  const cutoff = physicalRentalDate(new Date(now.getTime() - env.overdueGraceHours * 3600000));
  const rows = await RentalModel.aggregate([
    { $match: { renterId, listingType: 'physical', status: { $in: ['active', 'overdue', 'disputed'] },
      endDate: { $lt: cutoff }, 'returnSubmission.recordedAt': null } },
    { $lookup: { from: BookingModel.collection.name, localField: 'bookingId', foreignField: 'publicId', as: 'closedBooking',
      pipeline: [{ $match: { status: { $in: ['completed', 'cancelled', 'expired'] } } }, { $project: { _id: 1 } }] } },
    { $match: { closedBooking: { $size: 0 } } }, { $limit: 1 }, { $project: { _id: 1 } },
  ]);
  if (rows.length) {
    throw new AppError('Return your overdue item before making another booking. You can still message the Owner, submit your return or report an issue.',
      409, 'OVERDUE_RETURN_REQUIRED');
  }
}
