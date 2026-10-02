import 'dotenv/config';

const integer = (value, fallback) => {
  const parsed = Number(value ?? fallback);
  return Number.isInteger(parsed) ? parsed : Number.NaN;
};

const boolean = (value, fallback) => {
  if (value === undefined) return fallback;
  return String(value).toLowerCase() === 'true';
};

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 3000),
  mongoUri: process.env.MONGODB_URI ?? 'mongodb://localhost:27017/renthub',
  authMode: process.env.AUTH_MODE ?? 'mock',
  authIssuer: process.env.AUTH0_ISSUER_BASE_URL,
  authAudience: process.env.AUTH0_AUDIENCE,
  authRolesClaim:
    process.env.AUTH0_ROLES_CLAIM ?? 'https://renthub/roles',
  authEmailClaim: process.env.AUTH0_EMAIL_CLAIM ?? 'email',
  authNameClaim: process.env.AUTH0_NAME_CLAIM ?? 'name',
  localJwtSecret: process.env.LOCAL_JWT_SECRET,
  localAccessTokenMinutes: integer(process.env.LOCAL_ACCESS_TOKEN_MINUTES, 15),
  localRefreshTokenDays: integer(process.env.LOCAL_REFRESH_TOKEN_DAYS, 30),
  emailMode: process.env.EMAIL_MODE ?? 'disabled',
  resendApiKey: process.env.RESEND_API_KEY,
  emailFrom: process.env.EMAIL_FROM,
  smtpHost: process.env.SMTP_HOST ?? 'smtp.gmail.com',
  smtpPort: integer(process.env.SMTP_PORT, 587),
  smtpSecure: boolean(process.env.SMTP_SECURE, false),
  smtpUsername: process.env.SMTP_USERNAME,
  smtpPassword: process.env.SMTP_PASSWORD,
  passwordResetSecret: process.env.PASSWORD_RESET_SECRET,
  passwordResetTtlMinutes: integer(process.env.PASSWORD_RESET_TTL_MINUTES, 10),
  passwordResetCooldownSeconds: integer(
    process.env.PASSWORD_RESET_COOLDOWN_SECONDS,
    60,
  ),
  passwordResetMaxAttempts: integer(
    process.env.PASSWORD_RESET_MAX_ATTEMPTS,
    5,
  ),
  storageMode: process.env.STORAGE_MODE ?? 'local',
  uploadDirectory: process.env.UPLOAD_DIRECTORY ?? '.data/uploads',
  firebaseStorageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  fcmMode: process.env.FCM_MODE ?? 'disabled',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID,
  webAppUrl: process.env.WEB_APP_URL,
  maxUploadBytes: integer(process.env.MAX_UPLOAD_BYTES, 10 * 1024 * 1024),
  aiUrl: process.env.AI_SERVICE_URL ?? 'http://localhost:8001',
  aiTimeoutMs: integer(process.env.AI_TIMEOUT_MS, 5000),
  aiEnforcementMode: process.env.AI_ENFORCEMENT_MODE ?? 'advisory',
  blockchainMode: process.env.BLOCKCHAIN_MODE ?? 'disabled',
  ganacheRpcUrl: process.env.GANACHE_RPC_URL ?? 'http://localhost:8545',
  rentalContractArtifact:
    process.env.RENTAL_CONTRACT_ARTIFACT ??
    '../../blockchain/artifacts/contracts/RentalAgreement.sol/RentalAgreement.json',
  lifecycleJobsEnabled: boolean(process.env.LIFECYCLE_JOBS_ENABLED, true),
  lifecycleJobIntervalMs: integer(
    process.env.LIFECYCLE_JOB_INTERVAL_MS,
    15 * 60 * 1000,
  ),
  pendingBookingExpiryMinutes: integer(
    process.env.PENDING_BOOKING_EXPIRY_MINUTES,
    60,
  ),
  lifecycleReminderHours: integer(process.env.LIFECYCLE_REMINDER_HOURS, 24),
  overdueGraceHours: integer(process.env.OVERDUE_GRACE_HOURS, 0),
  corsOrigins: (process.env.CORS_ORIGINS ?? 'http://localhost:8080')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
};

export function validateEnv(config = env) {
  const errors = [];
  const storageMode = config.storageMode ?? 'local';
  const fcmMode = config.fcmMode ?? 'disabled';
  const maxUploadBytes = config.maxUploadBytes ?? 10 * 1024 * 1024;
  const aiTimeoutMs = config.aiTimeoutMs ?? 5000;
  const aiEnforcementMode = config.aiEnforcementMode ?? 'advisory';
  const blockchainMode = config.blockchainMode ?? 'disabled';
  const emailMode = config.emailMode ?? 'disabled';
  const localAccessTokenMinutes = config.localAccessTokenMinutes ?? 15;
  const localRefreshTokenDays = config.localRefreshTokenDays ?? 30;
  const passwordResetTtlMinutes = config.passwordResetTtlMinutes ?? 10;
  const passwordResetCooldownSeconds = config.passwordResetCooldownSeconds ?? 60;
  const passwordResetMaxAttempts = config.passwordResetMaxAttempts ?? 5;
  const lifecycleJobIntervalMs = config.lifecycleJobIntervalMs ?? 15 * 60 * 1000;
  const pendingBookingExpiryMinutes = config.pendingBookingExpiryMinutes ?? 60;
  const lifecycleReminderHours = config.lifecycleReminderHours ?? 24;
  const overdueGraceHours = config.overdueGraceHours ?? 0;
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
    errors.push('PORT must be an integer between 1 and 65535');
  }
  if (!config.mongoUri?.startsWith('mongodb')) {
    errors.push('MONGODB_URI must be a MongoDB connection string');
  }
  if (!['mock', 'local', 'auth0'].includes(config.authMode)) {
    errors.push('AUTH_MODE must be mock, local, or auth0');
  }
  if (config.nodeEnv === 'production' && config.authMode === 'mock') {
    errors.push('AUTH_MODE=mock is not allowed in production');
  }
  if (config.authMode === 'auth0') {
    if (!config.authIssuer) errors.push('AUTH0_ISSUER_BASE_URL is required');
    if (!config.authAudience) errors.push('AUTH0_AUDIENCE is required');
  }
  if (
    config.authMode === 'local' &&
    (!config.localJwtSecret || config.localJwtSecret.length < 32)
  ) {
    errors.push('LOCAL_JWT_SECRET must contain at least 32 characters');
  }
  if (
    !Number.isInteger(localAccessTokenMinutes) ||
    localAccessTokenMinutes < 5 ||
    localAccessTokenMinutes > 1440
  ) {
    errors.push('LOCAL_ACCESS_TOKEN_MINUTES must be an integer from 5 to 1440');
  }
  if (
    !Number.isInteger(localRefreshTokenDays) ||
    localRefreshTokenDays < 1 ||
    localRefreshTokenDays > 365
  ) {
    errors.push('LOCAL_REFRESH_TOKEN_DAYS must be an integer from 1 to 365');
  }
  if (!['disabled', 'resend', 'smtp'].includes(emailMode)) {
    errors.push('EMAIL_MODE must be disabled, resend, or smtp');
  }
  if (emailMode !== 'disabled') {
    if (!config.emailFrom) errors.push('EMAIL_FROM is required');
    if (!config.passwordResetSecret || config.passwordResetSecret.length < 32) {
      errors.push('PASSWORD_RESET_SECRET must contain at least 32 characters');
    }
  }
  if (emailMode === 'resend' && !config.resendApiKey) {
    errors.push('RESEND_API_KEY is required');
  }
  if (emailMode === 'smtp') {
    if (!config.smtpHost) errors.push('SMTP_HOST is required');
    if (!Number.isInteger(config.smtpPort) || config.smtpPort < 1 || config.smtpPort > 65535) {
      errors.push('SMTP_PORT must be an integer between 1 and 65535');
    }
    if (!config.smtpUsername) errors.push('SMTP_USERNAME is required');
    if (!config.smtpPassword) errors.push('SMTP_PASSWORD is required');
  }
  if (!Number.isInteger(passwordResetTtlMinutes) || passwordResetTtlMinutes < 5 || passwordResetTtlMinutes > 60) {
    errors.push('PASSWORD_RESET_TTL_MINUTES must be an integer from 5 to 60');
  }
  if (!Number.isInteger(passwordResetCooldownSeconds) || passwordResetCooldownSeconds < 30) {
    errors.push('PASSWORD_RESET_COOLDOWN_SECONDS must be an integer of at least 30');
  }
  if (!Number.isInteger(passwordResetMaxAttempts) || passwordResetMaxAttempts < 3 || passwordResetMaxAttempts > 10) {
    errors.push('PASSWORD_RESET_MAX_ATTEMPTS must be an integer from 3 to 10');
  }
  if (!['local', 'firebase'].includes(storageMode)) {
    errors.push('STORAGE_MODE must be either local or firebase');
  }
  if (!Number.isInteger(maxUploadBytes) || maxUploadBytes < 1024) {
    errors.push('MAX_UPLOAD_BYTES must be an integer of at least 1024');
  }
  if (storageMode === 'firebase' && !config.firebaseStorageBucket) {
    errors.push('FIREBASE_STORAGE_BUCKET is required for Firebase storage');
  }
  if (!['disabled', 'firebase'].includes(fcmMode)) {
    errors.push('FCM_MODE must be either disabled or firebase');
  }
  if (fcmMode === 'firebase' && !config.firebaseProjectId) {
    errors.push('FIREBASE_PROJECT_ID is required when FCM_MODE=firebase');
  }
  if (!Number.isInteger(aiTimeoutMs) || aiTimeoutMs < 500) {
    errors.push('AI_TIMEOUT_MS must be an integer of at least 500');
  }
  if (!['advisory', 'strict'].includes(aiEnforcementMode)) {
    errors.push('AI_ENFORCEMENT_MODE must be advisory or strict');
  }
  if (!['disabled', 'ganache'].includes(blockchainMode)) {
    errors.push('BLOCKCHAIN_MODE must be disabled or ganache');
  }
  if (!Number.isInteger(lifecycleJobIntervalMs) || lifecycleJobIntervalMs < 10_000) {
    errors.push('LIFECYCLE_JOB_INTERVAL_MS must be an integer of at least 10000');
  }
  if (!Number.isInteger(pendingBookingExpiryMinutes) || pendingBookingExpiryMinutes < 5) {
    errors.push('PENDING_BOOKING_EXPIRY_MINUTES must be an integer of at least 5');
  }
  if (!Number.isInteger(lifecycleReminderHours) || lifecycleReminderHours < 1) {
    errors.push('LIFECYCLE_REMINDER_HOURS must be an integer of at least 1');
  }
  if (!Number.isInteger(overdueGraceHours) || overdueGraceHours < 0) {
    errors.push('OVERDUE_GRACE_HOURS must be a non-negative integer');
  }
  if (config.nodeEnv === 'production' && storageMode !== 'firebase') {
    errors.push('STORAGE_MODE=firebase is required in production');
  }
  if (errors.length) {
    throw new Error(`Invalid environment configuration:\n- ${errors.join('\n- ')}`);
  }
  return config;
}

