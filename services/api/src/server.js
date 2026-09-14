import http from 'node:http';
import { Server } from 'socket.io';
import { app } from './app.js';
import { connectDatabase, disconnectDatabase } from './config/database.js';
import { env, validateEnv } from './config/env.js';
import { registerSocket } from './socket/registerSocket.js';

validateEnv();
await connectDatabase();
const server = http.createServer(app);
registerSocket(new Server(server, { cors: { origin: env.corsOrigins } }));
server.listen(env.port, () => console.log(`RentHub API listening on ${env.port}`));

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`${signal} received; shutting down RentHub API`);
  server.close(async () => {
    await disconnectDatabase();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

