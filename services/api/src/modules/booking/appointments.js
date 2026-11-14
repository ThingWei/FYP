import { AppError } from '../../core/errors.js';
import { physicalRentalDate } from '../../core/calendarDate.js';

export function bookingAppointments(listing, input) {
  if (listing.listingType !== 'physical') return {};
  const valid = value => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
  if (!valid(input.pickupTime) || !valid(input.returnTime)) {
    throw new AppError('Choose pickup and return appointment times.', 422, 'APPOINTMENT_TIMES_REQUIRED');
  }
  if (+physicalRentalDate(input.startDate) === +physicalRentalDate(input.endDate) && input.returnTime <= input.pickupTime) {
    throw new AppError('Choose a return time later than pickup for a same-day rental.', 422, 'INVALID_APPOINTMENT_TIMES');
  }
  return { pickupTime: input.pickupTime, returnTime: input.returnTime, appointmentTimezone: 'Asia/Kuala_Lumpur' };
}

export function agreementProof(rental) {
  if (!rental || rental.listingType !== 'physical') return null;
  const record = rental.blockchain ?? {};
  const hash = value => typeof value === 'string' && /^0x[a-f0-9]{64}$/i.test(value) ? value : null;
  const address = value => typeof value === 'string' && /^0x[a-f0-9]{40}$/i.test(value) ? value : null;
  return { network: record.localPrototype === true ? 'Local demonstration blockchain' : 'Rental blockchain',
    status: record.status ?? 'unavailable', contractAddress: address(record.contractAddress ?? rental.contractAddress),
    deploymentTransactionHash: hash(record.deploymentTransactionHash),
    lastTransactionHash: hash(record.lastTransactionHash ?? rental.transactionHash),
    signatureTransactionHashes: (record.signatureTransactionHashes ?? []).map(hash).filter(Boolean),
    recordedState: ['created', 'signed', 'active', 'completed', 'cancelled', 'disputed', 'resolved'].includes(record.contractState) ? record.contractState : null,
    recordedAt: record.updatedAt ?? null };
}
