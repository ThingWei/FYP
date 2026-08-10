import 'dotenv/config';
export const env = {
  port: Number(process.env.PORT ?? 3000),
  mongoUri: process.env.MONGODB_URI ?? 'mongodb://localhost:27017/renthub',
  authMode: process.env.AUTH_MODE ?? 'mock',
  authIssuer: process.env.AUTH0_ISSUER_BASE_URL,
  authAudience: process.env.AUTH0_AUDIENCE,
  aiUrl: process.env.AI_SERVICE_URL ?? 'http://localhost:8001',
};

