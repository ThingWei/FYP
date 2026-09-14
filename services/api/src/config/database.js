import mongoose from 'mongoose';
import { env } from './env.js';

const states = ['disconnected', 'connected', 'connecting', 'disconnecting'];

export async function connectDatabase(uri = env.mongoUri) {
  mongoose.set('strictQuery', true);
  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 10_000,
    maxPoolSize: 10,
  });
  return mongoose.connection;
}

export async function disconnectDatabase() {
  if (mongoose.connection.readyState !== 0) await mongoose.disconnect();
}

export function databaseHealth() {
  const readyState = mongoose.connection.readyState;
  return {
    status: readyState === 1 ? 'up' : 'down',
    state: states[readyState] ?? 'unknown',
  };
}
