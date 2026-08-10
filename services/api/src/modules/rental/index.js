import { createModule } from '../../core/moduleFactory.js';
export const rentalModule = createModule('Rental', { bookingId: String, status: { type: String, default: 'scheduled' }, contractAddress: String, transactionHash: String });

