import { databaseHealth } from '../config/database.js';
import { env } from '../config/env.js';
import { aiClient } from '../integrations/aiClient.js';
import { blockchainAdapter } from '../integrations/blockchainAdapter.js';
import { storageAdapter } from '../integrations/storageAdapter.js';
import { pushDelivery } from '../integrations/pushDelivery.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { RentalModel } from '../modules/rental/rental.model.js';
import { lifecycleSchedulerStatus } from './lifecycleJobs.js';

async function bounded(name, operation, timeoutMs = 3500) {
  let timer;
  try {
    return await Promise.race([
      operation(),
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${name} health check timed out`)),
          timeoutMs,
        );
      }),
    ]);
  } catch (error) {
    return { status: 'down', error: error.message };
  } finally {
    clearTimeout(timer);
  }
}

export async function technologyHealth() {
  const database = databaseHealth();
  const [ai, storage, blockchain, operationalCounts] = await Promise.all([
    bounded('AI service', () => aiClient.health(), Math.min(env.aiTimeoutMs, 2000)),
    bounded('Storage', async () => ({
      status: 'up',
      ...(await storageAdapter.verify({ writeProbe: false })),
    })),
    bounded('Blockchain', () => blockchainAdapter.health()),
    bounded('Operational counts', async () => ({
      status: 'up',
      expiredBookings: await BookingModel.countDocuments({ status: 'expired' }),
      overdueRentals: await RentalModel.countDocuments({ status: 'overdue' }),
      pendingUnpaidBookings: await BookingModel.countDocuments({
        status: 'pending',
        paymentStatus: 'unpaid',
      }),
    })),
  ]);
  const scheduler = lifecycleSchedulerStatus();
  const authentication = {
    status: env.authMode === 'mock' ? 'development' : 'configured',
    mode: env.authMode,
  };
  const components = {
    database,
    authentication,
    storage,
    ai,
    blockchain,
    pushNotifications: pushDelivery.status(),
    lifecycle: {
      status: scheduler.enabled
        ? scheduler.lastError
          ? 'degraded'
          : 'up'
        : 'disabled',
      ...scheduler,
    },
  };
  const requiredDown = database.status !== 'up' || storage.status === 'down';
  const optionalDown =
    ai.status === 'down' ||
    blockchain.status === 'down' ||
    blockchain.status === 'disabled' ||
    authentication.status === 'development' ||
    components.lifecycle.status !== 'up';
  return {
    status: requiredDown ? 'down' : optionalDown ? 'degraded' : 'healthy',
    checkedAt: new Date(),
    components,
    operationalCounts,
  };
}
