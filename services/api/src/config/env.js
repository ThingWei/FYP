import 'dotenv/config';

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 3000),
  mongoUri: process.env.MONGODB_URI ?? 'mongodb://localhost:27017/renthub',
  authMode: process.env.AUTH_MODE ?? 'mock',
  authIssuer: process.env.AUTH0_ISSUER_BASE_URL,
  authAudience: process.env.AUTH0_AUDIENCE,
  aiUrl: process.env.AI_SERVICE_URL ?? 'http://localhost:8001',
  corsOrigins: (process.env.CORS_ORIGINS ?? 'http://localhost:8080')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
};

export function validateEnv(config = env) {
  const errors = [];
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
    errors.push('PORT must be an integer between 1 and 65535');
  }
  if (!config.mongoUri?.startsWith('mongodb')) {
    errors.push('MONGODB_URI must be a MongoDB connection string');
  }
  if (!['mock', 'auth0'].includes(config.authMode)) {
    errors.push('AUTH_MODE must be either mock or auth0');
  }
  if (config.nodeEnv === 'production' && config.authMode === 'mock') {
    errors.push('AUTH_MODE=mock is not allowed in production');
  }
  if (config.authMode === 'auth0') {
    if (!config.authIssuer) errors.push('AUTH0_ISSUER_BASE_URL is required');
    if (!config.authAudience) errors.push('AUTH0_AUDIENCE is required');
  }
  if (errors.length) {
    throw new Error(`Invalid environment configuration:\n- ${errors.join('\n- ')}`);
  }
  return config;
}

