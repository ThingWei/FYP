import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { databaseHealth } from './config/database.js';
import { env } from './config/env.js';
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
import { uploadModule } from './modules/upload/index.js';
import { catalogModule } from './modules/catalog/index.js';
import { mapsRouter } from './modules/maps/maps.routes.js';

morgan.token('safe-path', (req) => req.path);
export const app = express();
const apiCapabilities = ['product-catalog-v1', 'mykad-capture-validation-v1', 'mykad-readability-pair-v1', 'mandatory-identity-access-v1', 'listing-maps-push-status-v1', 'precise-locations-v1'];
app.use(
  helmet(),
  cors({ origin: env.corsOrigins }),
  express.json({ limit: '2mb' }),
  morgan(':method :safe-path :status :response-time ms'),
  audit,
);
const api = express.Router();
api.use('/maps', mapsRouter);
api.get('/health', (_req, res) =>
  res.json({
    success: true,
    data: { status: 'ok', capabilities: apiCapabilities },
  }),
);
api.get('/ready', (_req, res) => {
  const database = databaseHealth();
  const ready = database.status === 'up';
  return res.status(ready ? 200 : 503).json({
    success: ready,
    data: {
      status: ready ? 'ready' : 'not_ready',
      database,
      capabilities: apiCapabilities,
    },
  });
});
for (const [path, module] of Object.entries({
  users: userModule,
  listings: listingModule,
  bookings: bookingModule,
  payments: paymentModule,
  rentals: rentalModule,
  messages: communicationModule,
  reviews: reviewModule,
  disputes: disputeModule,
  rewards: loyaltyModule,
  admin: adminModule,
  uploads: uploadModule,
  catalog: catalogModule,
})) {
  api.use(`/${path}`, module.router);
}
app.use('/api/v1', api);
app.use(notFound);
app.use(errorHandler);

