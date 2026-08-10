import { createModule } from '../../core/moduleFactory.js';
export const paymentModule = createModule('Payment', { bookingId: String, amount: Number, status: { type: String, default: 'pending' }, simulated: { type: Boolean, default: true } });

