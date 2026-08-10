import { createModule } from '../../core/moduleFactory.js';
export const bookingModule = createModule('Booking', { listingId: { type: String, required: true }, renterId: String, startDate: Date, endDate: Date, total: Number, status: { type: String, default: 'pending' } });

