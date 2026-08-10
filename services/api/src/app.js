import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { audit } from './middleware/audit.js';
import { errorHandler, notFound } from './middleware/errorHandler.js';
import { userModule } from './modules/user/index.js';
import { listingModule } from './modules/listing/index.js';
import { bookingModule } from './modules/booking/index.js';
import { paymentModule } from './modules/payment/index.js';
import { rentalModule } from './modules/rental/index.js';
import { communicationModule } from './modules/communication/index.js';
import { reviewModule } from './modules/review/index.js';
import { disputeModule } from './modules/dispute/index.js';
import { loyaltyModule } from './modules/loyalty/index.js';
import { adminModule } from './modules/admin/index.js';

export const app = express();
app.use(helmet(), cors(), express.json({ limit: '2mb' }), morgan('dev'), audit);
const api = express.Router();
api.get('/health', (_req, res) => res.json({ success: true, data: { status: 'ok' } }));
for (const [path, module] of Object.entries({ users: userModule, listings: listingModule, bookings: bookingModule, payments: paymentModule, rentals: rentalModule, messages: communicationModule, reviews: reviewModule, disputes: disputeModule, rewards: loyaltyModule, admin: adminModule })) api.use(`/${path}`, module.router);
app.use('/api/v1', api); app.use(notFound); app.use(errorHandler);

