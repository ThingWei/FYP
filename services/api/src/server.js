import http from 'node:http';
import mongoose from 'mongoose';
import { Server } from 'socket.io';
import { app } from './app.js';
import { env } from './config/env.js';
import { registerSocket } from './socket/registerSocket.js';

await mongoose.connect(env.mongoUri);
const server = http.createServer(app);
registerSocket(new Server(server, { cors: { origin: '*' } }));
server.listen(env.port, () => console.log(`RentHub API listening on ${env.port}`));

