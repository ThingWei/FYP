import http from 'node:http';
import { Server } from 'socket.io';
import { app } from './app.js';
import { connectDatabase, disconnectDatabase } from './config/database.js';
import { env, validateEnv } from './config/env.js';
import { registerSocket } from './socket/registerSocket.js';
import { startPriceSyncScheduler, stopPriceSyncScheduler } from './operations/priceSyncJobs.js';
import { drainPriceSyncJobs } from './modules/listing/priceSync.service.js';
import { MessageModel } from './modules/communication/message.model.js';
import {
  startLifecycleScheduler,
  stopLifecycleScheduler,
} from './operations/lifecycleJobs.js';

validateEnv();
await connectDatabase();
await MessageModel.init();
const server = http.createServer(app);
registerSocket(new Server(server, { cors: { origin: env.corsOrigins } }));
startLifecycleScheduler();
server.listen(env.port, () => {
  console.log(`RentHub API listening on ${env.port}`);
  startPriceSyncScheduler();
});

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  stopLifecycleScheduler();
  stopPriceSyncScheduler();
  console.log(`${signal} received; shutting down RentHub API`);
  server.close(async () => {
    await drainPriceSyncJobs();
    await disconnectDatabase();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

