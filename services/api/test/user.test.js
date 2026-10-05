import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { PasswordResetModel } from '../src/modules/user/passwordReset.model.js';
import { LocalSessionModel } from '../src/modules/user/localSession.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { MessageModel } from '../src/modules/communication/message.model.js';
import { MessageReportModel } from '../src/modules/communication/messageReport.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
import { ClaimModel } from '../src/modules/dispute/claim.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from '../src/modules/loyalty/loyalty.model.js';
import { adminModule } from '../src/modules/admin/index.js';
import { hashPassword } from '../src/core/password.js';
import { emailClient } from '../src/integrations/emailClient.js';
import { env } from '../src/config/env.js';
import { identityFromPayload } from '../src/middleware/auth.js';

let mongodb;
const runFile = promisify(execFile);
const seedScript = fileURLToPath(
  new URL('../src/scripts/seed.js', import.meta.url),
);

const identity = ({
  id = 'u-renter',
  email = 'renter@renthub.my',
  name = 'Alex Tan',
  roles = 'renter',
} = {}) => ({
  'x-user-id': id,
  'x-user-email': email,
  'x-user-name': name,
  'x-user-roles': roles,
});

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    UserModel.init(),
    PasswordResetModel.init(),
    LocalSessionModel.init(),
    ListingModel.init(),
    NotificationModel.init(),
    adminModule.Model.init(),
    adminModule.PlatformSettingModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    UserModel.deleteMany({}),
    PasswordResetModel.deleteMany({}),
    LocalSessionModel.deleteMany({}),
    ListingModel.deleteMany({}),
    NotificationModel.deleteMany({}),
    adminModule.Model.deleteMany({}),
    adminModule.PlatformSettingModel.deleteMany({}),
  ]);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('starts a session and creates a role-aware MongoDB profile', async () => {
  const response = await request(app)
    .post('/api/v1/users/session')
    .set(identity({ roles: 'renter,owner' }));

  assert.equal(response.status, 201);
  assert.equal(response.body.data.authId, 'u-renter');
  assert.deepEqual(response.body.data.roles, ['renter', 'owner']);
  assert.equal(response.body.data.activeRole, 'renter');

  const stored = await UserModel.findOne({ authId: 'u-renter' }).lean();
  assert.equal(stored.email, 'renter@renthub.my');
});

test('Auth0-style sessions sanitize missing social profile claims', async () => {
  const response = await request(app)
    .post('/api/v1/users/session')
    .set(
      identity({
        id: 'github|123456789',
        email: '',
        name: 'A',
        roles: 'renter,owner',
      }),
    );

  assert.equal(response.status, 201, JSON.stringify(response.body));
  assert.equal(response.body.data.authId, 'github|123456789');
  assert.match(
    response.body.data.email,
    /^auth0-[a-f\d]{24}@users\.renthub\.local$/,
  );
  assert.equal(response.body.data.displayName, 'RentHub User');
  assert.deepEqual(response.body.data.roles, ['renter', 'owner']);
});

test('Auth0 JWT name mapping always supplies a valid display name', () => {
  const oidcIdentity = identityFromPayload({
    sub: 'auth0|mobile-user',
    email: 'mobile.user@example.com',
    given_name: 'Mobile',
    family_name: 'User',
  });
  assert.equal(oidcIdentity.displayName, 'Mobile User');

  const minimalIdentity = identityFromPayload({ sub: 'auth0|minimal-user' });
  assert.equal(minimalIdentity.displayName, 'RentHub User');
  assert.ok(minimalIdentity.displayName.length >= 2);

  const placeholderNameIdentity = identityFromPayload({
    sub: 'auth0|placeholder-name',
    'https://renthub/name': 'RentHub User',
    'https://renthub/email': 'chngthingwei@gmail.com',
  });
  assert.equal(placeholderNameIdentity.displayName, 'chngthingwei');
});

test('repairs a placeholder Auth0 profile name when a later login supplies one', async () => {
  const headers = identity({
    id: 'auth0|profile-name-repair',
    email: 'personal@example.com',
    name: 'RentHub User',
  });
  const firstLogin = await request(app)
    .post('/api/v1/users/session')
    .set(headers);
  assert.equal(firstLogin.status, 201);
  assert.equal(firstLogin.body.data.displayName, 'RentHub User');

  const refreshedHeaders = identity({
    id: 'auth0|profile-name-repair',
    email: 'personal@example.com',
    name: 'Personal Account Name',
  });
  const nextLogin = await request(app)
    .post('/api/v1/users/session')
    .set(refreshedHeaders);
  assert.equal(nextLogin.status, 200);
  assert.equal(nextLogin.body.data.displayName, 'Personal Account Name');

  const editedNameHeaders = identity({
    id: 'auth0|profile-name-repair',
    email: 'personal@example.com',
    name: 'Different Auth0 Name',
  });
  await request(app)
    .patch('/api/v1/users/me')
    .set(editedNameHeaders)
    .send({ displayName: 'RentHub Profile Name' });
  const subsequentLogin = await request(app)
    .post('/api/v1/users/session')
    .set(editedNameHeaders);
  assert.equal(subsequentLogin.status, 200);
  assert.equal(subsequentLogin.body.data.displayName, 'RentHub Profile Name');
});

test('local registration assigns both roles and preserves the starting interface', async () => {
  for (const role of ['renter', 'owner']) {
    const response = await request(app)
      .post('/api/v1/users/local-register')
      .send({
        displayName: `${role} Starter`,
        email: `${role}-starter@renthub.my`,
        password: 'Correct123!',
        role,
      });
    assert.equal(response.status, 201, JSON.stringify(response.body));
    const user = response.body.data.user ?? response.body.data;
    assert.deepEqual(user.roles, ['renter', 'owner']);
    assert.equal(user.activeRole, role);
  }

  const ownerLogin = await request(app).post('/api/v1/users/local-login').send({
    email: 'renter-starter@renthub.my',
    password: 'Correct123!',
    role: 'owner',
  });
  assert.equal(ownerLogin.status, 200);
  assert.equal(
    (ownerLogin.body.data.user ?? ownerLogin.body.data).activeRole,
    'owner',
  );
});

test('session claims cannot narrow public roles and mixed claims are rejected', async () => {
  const renterClaim = identity({ id: 'u-normalized', roles: 'renter' });
  const created = await request(app)
    .post('/api/v1/users/session')
    .set(renterClaim);
  assert.equal(created.status, 201);
  assert.deepEqual(created.body.data.roles, ['renter', 'owner']);

  const ownerClaim = identity({ id: 'u-normalized', roles: 'owner' });
  const refreshed = await request(app)
    .post('/api/v1/users/session')
    .set(ownerClaim);
  assert.equal(refreshed.status, 200);
  assert.deepEqual(refreshed.body.data.roles, ['renter', 'owner']);

  const mixed = await request(app)
    .post('/api/v1/users/session')
    .set(identity({ id: 'u-mixed', roles: 'admin,renter' }));
  assert.equal(mixed.status, 403);
  assert.equal(mixed.body.error.code, 'CONTRADICTORY_ROLE_CLAIMS');
});

test('administrator sessions remain isolated from marketplace role switching', async () => {
  const headers = identity({ id: 'u-admin-only', roles: 'admin' });
  const created = await request(app).post('/api/v1/users/session').set(headers);
  assert.equal(created.status, 201);
  assert.deepEqual(created.body.data.roles, ['admin']);
  const switched = await request(app)
    .patch('/api/v1/users/me/active-role')
    .set(headers)
    .send({ role: 'renter' });
  assert.equal(switched.status, 403);
  assert.equal(switched.body.error.code, 'ROLE_SWITCH_NOT_AVAILABLE');
});

test('local login accepts the stored password and rejects a wrong password', async () => {
  await UserModel.create({
    authId: 'u-password-test',
    email: 'password-test@renthub.my',
    displayName: 'Password Test',
    passwordHash: await hashPassword('Correct123!'),
    roles: ['renter', 'owner'],
    activeRole: 'renter',
  });

  const accepted = await request(app).post('/api/v1/users/local-login').send({
    email: 'password-test@renthub.my',
    password: 'Correct123!',
    role: 'renter',
  });
  const rejected = await request(app).post('/api/v1/users/local-login').send({
    email: 'password-test@renthub.my',
    password: 'Wrong123!',
    role: 'renter',
  });

  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.data.authId, 'u-password-test');
  assert.equal(accepted.body.data.passwordHash, undefined);
  assert.equal(rejected.status, 401);
  assert.equal(rejected.body.error.code, 'INVALID_CREDENTIALS');
});

test('hybrid auth accepts, rotates, and revokes local bearer sessions', async () => {
  await UserModel.create({
    authId: 'u-local-session',
    email: 'local-session@renthub.my',
    displayName: 'Local Session',
    passwordHash: await hashPassword('Correct123!'),
    roles: ['renter', 'owner'],
    activeRole: 'renter',
  });
  const original = {
    authMode: env.authMode,
    localJwtSecret: env.localJwtSecret,
    localAccessTokenMinutes: env.localAccessTokenMinutes,
    localRefreshTokenDays: env.localRefreshTokenDays,
  };
  env.authMode = 'hybrid';
  env.localJwtSecret = 'test-local-jwt-secret-at-least-32-chars';
  env.localAccessTokenMinutes = 15;
  env.localRefreshTokenDays = 30;
  try {
    const login = await request(app)
      .post('/api/v1/users/local-login')
      .set('user-agent', 'RentHub First Device')
      .send({
        email: 'local-session@renthub.my',
        password: 'Correct123!',
        role: 'renter',
      });
    assert.equal(login.status, 200);
    assert.equal(login.body.data.user.authId, 'u-local-session');
    assert.ok(login.body.data.session.accessToken);
    assert.ok(login.body.data.session.refreshToken);

    const accessToken = login.body.data.session.accessToken;
    const me = await request(app)
      .get('/api/v1/users/me')
      .set('authorization', `Bearer ${accessToken}`);
    assert.equal(me.status, 200);
    assert.equal(me.body.data.authId, 'u-local-session');

    const forged = await request(app)
      .get('/api/v1/users/me')
      .set(identity({ id: 'u-local-session' }));
    assert.equal(forged.status, 401);

    const secondLogin = await request(app)
      .post('/api/v1/users/local-login')
      .set('user-agent', 'RentHub Second Device')
      .send({
        email: 'local-session@renthub.my',
        password: 'Correct123!',
        role: 'renter',
      });
    const secondAccessToken = secondLogin.body.data.session.accessToken;
    const secondRefreshToken = secondLogin.body.data.session.refreshToken;
    const sessions = await request(app)
      .get('/api/v1/users/me/sessions')
      .set('authorization', `Bearer ${secondAccessToken}`);
    assert.equal(sessions.status, 200);
    assert.equal(sessions.body.data.length, 2);
    assert.equal(
      sessions.body.data.find((session) => session.current).userAgent,
      'RentHub Second Device',
    );

    const firstSession = sessions.body.data.find((session) => !session.current);
    const revokeFirst = await request(app)
      .delete(`/api/v1/users/me/sessions/${firstSession.id}`)
      .set('authorization', `Bearer ${secondAccessToken}`);
    assert.equal(revokeFirst.status, 200);

    const revokedFirst = await request(app)
      .get('/api/v1/users/me')
      .set('authorization', `Bearer ${accessToken}`);
    assert.equal(revokedFirst.status, 401);

    const refreshed = await request(app)
      .post('/api/v1/users/local-refresh')
      .send({ refreshToken: secondRefreshToken });
    assert.equal(refreshed.status, 200);
    assert.notEqual(
      refreshed.body.data.session.refreshToken,
      secondRefreshToken,
    );

    const thirdLogin = await request(app).post('/api/v1/users/local-login').send({
      email: 'local-session@renthub.my',
      password: 'Correct123!',
      role: 'renter',
    });
    const revokeOthers = await request(app)
      .post('/api/v1/users/me/sessions/revoke-others')
      .set(
        'authorization',
        `Bearer ${refreshed.body.data.session.accessToken}`,
      );
    assert.equal(revokeOthers.status, 200);
    assert.equal(revokeOthers.body.data.revokedCount, 1);

    const revokedThird = await request(app)
      .get('/api/v1/users/me')
      .set(
        'authorization',
        `Bearer ${thirdLogin.body.data.session.accessToken}`,
      );
    assert.equal(revokedThird.status, 401);

    const logout = await request(app)
      .post('/api/v1/users/local-logout')
      .set(
        'authorization',
        `Bearer ${refreshed.body.data.session.accessToken}`,
      );
    assert.equal(logout.status, 200);
    assert.equal(logout.body.data.signedOut, true);

    const revoked = await request(app)
      .get('/api/v1/users/me')
      .set(
        'authorization',
        `Bearer ${refreshed.body.data.session.accessToken}`,
      );
    assert.equal(revoked.status, 401);
  } finally {
    Object.assign(env, original);
  }
});

test('emails a one-time code and changes a local account password', async () => {
  await UserModel.create({
    authId: 'u-reset-test',
    email: 'reset-test@renthub.my',
    displayName: 'Reset Test',
    passwordHash: await hashPassword('OldPassword123!'),
    roles: ['renter', 'owner'],
    activeRole: 'renter',
  });
  const original = {
    emailMode: env.emailMode,
    resendApiKey: env.resendApiKey,
    emailFrom: env.emailFrom,
    passwordResetSecret: env.passwordResetSecret,
    send: emailClient.sendPasswordResetCode,
  };
  let deliveredCode;
  env.emailMode = 'resend';
  env.resendApiKey = 'test-api-key';
  env.emailFrom = 'RentHub <test@renthub.my>';
  env.passwordResetSecret = 'test-password-reset-secret-32-characters';
  emailClient.sendPasswordResetCode = async ({ code }) => {
    deliveredCode = code;
    return { id: 'email-test' };
  };
  try {
    const requested = await request(app)
      .post('/api/v1/users/local-password-reset/request')
      .send({ email: 'reset-test@renthub.my' });
    assert.equal(requested.status, 200);
    assert.match(deliveredCode, /^\d{6}$/);

    const wrong = await request(app)
      .post('/api/v1/users/local-password-reset/confirm')
      .send({
        email: 'reset-test@renthub.my',
        code: deliveredCode === '000000' ? '000001' : '000000',
        password: 'NewPassword123!',
      });
    assert.equal(wrong.status, 400);
    assert.equal(wrong.body.error.code, 'INVALID_RESET_CODE');

    const confirmed = await request(app)
      .post('/api/v1/users/local-password-reset/confirm')
      .send({
        email: 'reset-test@renthub.my',
        code: deliveredCode,
        password: 'NewPassword123!',
      });
    assert.equal(confirmed.status, 200);

    const oldLogin = await request(app)
      .post('/api/v1/users/local-login')
      .send({
        email: 'reset-test@renthub.my',
        password: 'OldPassword123!',
        role: 'renter',
      });
    const newLogin = await request(app)
      .post('/api/v1/users/local-login')
      .send({
        email: 'reset-test@renthub.my',
        password: 'NewPassword123!',
        role: 'renter',
      });
    assert.equal(oldLogin.status, 401);
    assert.equal(newLogin.status, 200);

    const reused = await request(app)
      .post('/api/v1/users/local-password-reset/confirm')
      .send({
        email: 'reset-test@renthub.my',
        code: deliveredCode,
        password: 'AnotherPassword123!',
      });
    assert.equal(reused.status, 400);
  } finally {
    env.emailMode = original.emailMode;
    env.resendApiKey = original.resendApiKey;
    env.emailFrom = original.emailFrom;
    env.passwordResetSecret = original.passwordResetSecret;
    emailClient.sendPasswordResetCode = original.send;
  }
});

test('readiness reports MongoDB and the seed script is idempotent', async () => {
  const ready = await request(app).get('/api/v1/ready');
  assert.equal(ready.status, 200);
  assert.equal(ready.body.data.database.state, 'connected');

  const options = {
    env: { ...process.env, MONGODB_URI: mongodb.getUri(), AUTH_MODE: 'mock' },
  };
  await runFile(process.execPath, [seedScript], options);
  await runFile(process.execPath, [seedScript], options);

  const seededLogin = await request(app)
    .post('/api/v1/users/local-login')
    .send({
      email: 'renter@renthub.my',
      password: 'RentHub123!',
      role: 'renter',
    });
  assert.equal(seededLogin.status, 200);

  assert.equal(await UserModel.countDocuments(), 5);
  assert.equal(await ListingModel.countDocuments(), 13);
  assert.equal(await BookingModel.countDocuments(), 4);
  assert.equal(await RentalModel.countDocuments(), 3);
  assert.equal(await PaymentModel.countDocuments(), 3);
  assert.equal(await ThreadModel.countDocuments(), 2);
  assert.equal(await MessageModel.countDocuments(), 4);
  assert.equal(await NotificationModel.countDocuments(), 4);
  assert.equal(await MessageReportModel.countDocuments(), 1);
  assert.equal(await ReviewModel.countDocuments(), 1);
  assert.equal(await DisputeModel.countDocuments(), 1);
  assert.equal(await ClaimModel.countDocuments(), 1);
  assert.equal(await LoyaltyAccountModel.countDocuments(), 5);
  assert.equal(await RewardLedgerModel.countDocuments(), 2);
  assert.equal(await ReferralModel.countDocuments(), 1);
  assert.equal(await LoyaltyConfigModel.countDocuments(), 1);
  const renter = await UserModel.findOne({ authId: 'u-renter' }).lean();
  assert.equal(renter.displayName, 'Alex Tan');
  assert.equal(renter.trustScore, 92);
  const camera = await ListingModel.findOne({ publicId: 'l-camera' }).lean();
  assert.equal(camera.dailyPrice, 85);
  assert.equal(camera.securityDeposit, 300);
  const cameraBooking = await BookingModel.findOne({
    publicId: 'RH-BKG-2026-09142',
  }).lean();
  assert.equal(cameraBooking.pricing.total, 570);
  assert.equal(cameraBooking.paymentStatus, 'captured');
  const serviceBooking = await BookingModel.findOne({
    publicId: 'RH-SVC-2026-03218',
  }).lean();
  assert.equal(serviceBooking.pricing.total, 472.5);
  assert.equal(serviceBooking.paymentStatus, 'authorized');
  const cameraCapture = await PaymentModel.findOne({
    publicId: 'TXN-CAP-2026-09142',
  }).lean();
  assert.equal(cameraCapture.amount, 570);
  assert.equal(cameraCapture.status, 'succeeded');
  const cameraThread = await ThreadModel.findOne({
    bookingId: 'RH-BKG-2026-09142',
  }).lean();
  assert.deepEqual(cameraThread.participantIds, ['u-renter', 'u-owner']);
});

test('validates profile updates and role switching', async () => {
  const headers = identity({ roles: 'renter,owner' });
  await request(app).post('/api/v1/users/session').set(headers);

  const invalid = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({ displayName: '' });
  assert.equal(invalid.status, 422);
  assert.equal(invalid.body.error.code, 'VALIDATION_ERROR');

  const updated = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({
      displayName: 'Alex T.',
      addresses: [
        {
          label: 'Home',
          line1: '18 Jalan Ampang',
          city: 'Kuala Lumpur',
          state: 'Kuala Lumpur',
          postcode: '50450',
          isDefault: true,
        },
      ],
    });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.data.displayName, 'Alex T.');
  assert.equal(updated.body.data.addresses[0].postcode, '50450');

  const switched = await request(app)
    .patch('/api/v1/users/me/active-role')
    .set(headers)
    .send({ role: 'owner' });
  assert.equal(switched.status, 200);
  assert.equal(switched.body.data.activeRole, 'owner');

  const refreshedIdentity = identity({
    email: 'alex.updated@renthub.my',
    name: 'Auth0 Profile Name',
    roles: 'renter,owner',
  });
  await request(app).post('/api/v1/users/session').set(refreshedIdentity);
  const refreshed = await request(app)
    .get('/api/v1/users/me')
    .set(refreshedIdentity);
  assert.equal(refreshed.status, 200);
  assert.equal(refreshed.body.data.email, 'alex.updated@renthub.my');
  assert.equal(refreshed.body.data.displayName, 'Alex T.');
});

test('submits and reviews identity verification with audit and notification', async () => {
  const owner = identity({
    id: 'u-verification-owner',
    email: 'verification-owner@renthub.my',
    name: 'Nadia Lim',
    roles: 'owner',
  });
  const admin = identity({
    id: 'u-admin',
    email: 'admin@renthub.my',
    name: 'Admin Farah',
    roles: 'admin',
  });
  await request(app).post('/api/v1/users/session').set(owner);
  await request(app).post('/api/v1/users/session').set(admin);
  await ListingModel.create({
    publicId: 'l-verification-test',
    ownerId: 'u-verification-owner',
    ownerName: 'Nadia Lim',
    title: 'Verification Test Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 50,
    condition: 'Good',
    fulfilmentMethods: ['pickup'],
    location: 'Shah Alam, Selangor',
    status: 'active',
    verified: false,
  });

  const submitted = await request(app)
    .post('/api/v1/users/me/verification')
    .set(owner)
    .send({
      documentType: 'mykad',
      documentRefs: [
        'local://verification/mykad-front.jpg',
        'local://verification/mykad-back.jpg',
      ],
    });
  assert.equal(submitted.status, 200);
  assert.equal(submitted.body.data.verification.status, 'pending');
  assert.equal(submitted.body.data.verification.documentRefs.length, 2);
  assert.equal(submitted.body.data.verification.history.length, 1);
  assert.equal(
    submitted.body.data.verification.documents[0].documentType,
    'mykad',
  );

  const duplicate = await request(app)
    .post('/api/v1/users/me/verification')
    .set(owner)
    .send({
      documentType: 'mykad',
      documentRefs: ['local://verification/mykad-front.jpg'],
    });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error.code, 'VERIFICATION_PENDING');

  const target = await UserModel.findOne({
    authId: 'u-verification-owner',
  }).lean();
  const reviewed = await request(app)
    .patch(`/api/v1/users/${target._id}/verification`)
    .set(admin)
    .send({ status: 'approved', tier: 'enhanced' });
  assert.equal(reviewed.status, 200);
  assert.equal(reviewed.body.data.verification.status, 'approved');
  assert.equal(reviewed.body.data.verification.tier, 'enhanced');
  assert.equal(
    reviewed.body.data.verification.history[0].status,
    'approved',
  );

  const licence = await request(app)
    .post('/api/v1/users/me/verification')
    .set(owner)
    .send({
      documentType: 'driving_licence',
      documentRefs: ['local://verification/licence-front.jpg'],
    });
  assert.equal(licence.status, 200, JSON.stringify(licence.body));
  const licenceAttempt = licence.body.data.verification.history.at(-1);
  assert.equal(licenceAttempt.documentType, 'driving_licence');
  assert.equal(licenceAttempt.status, 'pending');
  assert.equal(licence.body.data.verification.status, 'approved');

  const licenceReviewed = await request(app)
    .patch(`/api/v1/users/${target._id}/verification`)
    .set(admin)
    .send({
      status: 'approved',
      tier: 'enhanced',
      attemptId: licenceAttempt.attemptId,
    });
  assert.equal(licenceReviewed.status, 200);
  assert.equal(
    licenceReviewed.body.data.verification.documents.find(
      (item) => item.documentType === 'driving_licence',
    ).status,
    'approved',
  );

  const listing = await ListingModel.findOne({
    publicId: 'l-verification-test',
  }).lean();
  assert.equal(listing.verified, true);
  assert.equal(
    await NotificationModel.countDocuments({
      userId: 'u-verification-owner',
      type: 'verification_approved',
    }),
    2,
  );
  assert.equal(
    await adminModule.Model.countDocuments({
      action: 'verification.approved',
      targetId: 'u-verification-owner',
    }),
    2,
  );
});

test('resolves category KYC rules without disabling always-required categories', async () => {
  const renterIdentity = identity();
  await request(app).post('/api/v1/users/session').set(renterIdentity);

  const belowThreshold = await request(app)
    .get('/api/v1/users/me/verification/requirements')
    .query({ category: 'Devices', dailyPrice: 999 })
    .set(renterIdentity);
  assert.equal(belowThreshold.status, 200);
  assert.deepEqual(belowThreshold.body.data.requiredDocumentTypes, []);

  const highValue = await request(app)
    .get('/api/v1/users/me/verification/requirements')
    .query({ category: 'Devices', dailyPrice: 1000 })
    .set(renterIdentity);
  assert.deepEqual(highValue.body.data.requiredDocumentTypes, ['mykad']);

  await adminModule.PlatformSettingModel.updateOne(
    { key: 'platform' },
    { $set: { highValueKycEnabled: false } },
  );
  const disabledHighValue = await request(app)
    .get('/api/v1/users/me/verification/requirements')
    .query({ category: 'Devices', dailyPrice: 5000 })
    .set(renterIdentity);
  assert.deepEqual(disabledHighValue.body.data.requiredDocumentTypes, []);

  const vehicle = await request(app)
    .get('/api/v1/users/me/verification/requirements')
    .query({ category: 'Vehicles', dailyPrice: 10 })
    .set(renterIdentity);
  assert.deepEqual(vehicle.body.data.requiredDocumentTypes, [
    'mykad',
    'driving_licence',
  ]);
});

test('rejects more than one default address', async () => {
  const headers = identity();
  await request(app).post('/api/v1/users/session').set(headers);

  const address = {
    label: 'Home',
    line1: '18 Jalan Ampang',
    city: 'Kuala Lumpur',
    state: 'Kuala Lumpur',
    postcode: '50450',
    isDefault: true,
  };
  const response = await request(app)
    .patch('/api/v1/users/me')
    .set(headers)
    .send({ addresses: [address, { ...address, label: 'Office' }] });

  assert.equal(response.status, 400);
  assert.equal(response.body.error.code, 'VALIDATION_ERROR');
});

test('allows every marketplace account to select the Owner interface', async () => {
  const headers = identity();
  await request(app).post('/api/v1/users/session').set(headers);

  const response = await request(app)
    .patch('/api/v1/users/me/active-role')
    .set(headers)
    .send({ role: 'owner' });

  assert.equal(response.status, 200);
  assert.deepEqual(response.body.data.roles, ['renter', 'owner']);
  assert.equal(response.body.data.activeRole, 'owner');
});

test('blocks and unblocks an existing Owner', async () => {
  const renter = identity();
  const owner = identity({
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Sarah J.',
    roles: 'owner',
  });
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(owner);

  const blocked = await request(app)
    .post('/api/v1/users/me/blocked-users/u-owner')
    .set(renter);
  assert.equal(blocked.status, 200);
  assert.deepEqual(blocked.body.data.blockedUserIds, ['u-owner']);

  const unblocked = await request(app)
    .delete('/api/v1/users/me/blocked-users/u-owner')
    .set(renter);
  assert.equal(unblocked.status, 200);
  assert.deepEqual(unblocked.body.data.blockedUserIds, []);
});

test('allows only an admin to list and restrict accounts with a reason', async () => {
  const renter = identity();
  const admin = identity({
    id: 'u-admin',
    email: 'admin@renthub.my',
    name: 'Admin Farah',
    roles: 'admin',
  });
  await request(app).post('/api/v1/users/session').set(renter);
  await request(app).post('/api/v1/users/session').set(admin);

  const forbidden = await request(app).get('/api/v1/users').set(renter);
  assert.equal(forbidden.status, 403);

  const directory = await request(app)
    .get('/api/v1/users?role=renter')
    .set(admin);
  assert.equal(directory.status, 200);
  assert.equal(directory.body.meta.total, 1);

  const target = await UserModel.findOne({ authId: 'u-renter' }).lean();
  const missingReason = await request(app)
    .patch(`/api/v1/users/${target._id}/status`)
    .set(admin)
    .send({ status: 'suspended' });
  assert.equal(missingReason.status, 400);
  assert.equal(missingReason.body.error.code, 'REASON_REQUIRED');

  const suspended = await request(app)
    .patch(`/api/v1/users/${target._id}/status`)
    .set(admin)
    .send({ status: 'suspended', reason: 'Repeated safety violations' });
  assert.equal(suspended.status, 200);
  assert.equal(suspended.body.data.accountStatus, 'suspended');
});

test('deactivates an account, revokes access, and allows audited reactivation', async () => {
  const owner = identity({
    id: 'u-deactivation-owner',
    email: 'leaving-owner@renthub.my',
    name: 'Leaving Owner',
    roles: 'renter,owner',
  });
  const admin = identity({
    id: 'u-admin',
    email: 'admin@renthub.my',
    name: 'Admin Farah',
    roles: 'admin',
  });
  await request(app).post('/api/v1/users/session').set(owner);
  await request(app).post('/api/v1/users/session').set(admin);
  await ListingModel.create({
    publicId: 'l-deactivation-test',
    ownerId: 'u-deactivation-owner',
    ownerName: 'Leaving Owner',
    title: 'Deactivation Test Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 50,
    condition: 'Good',
    fulfilmentMethods: ['pickup'],
    location: 'Petaling Jaya, Selangor',
    status: 'active',
  });

  const invalid = await request(app)
    .post('/api/v1/users/me/deactivate')
    .set(owner)
    .send({ confirmation: false, reason: 'Taking a break' });
  assert.equal(invalid.status, 422);
  assert.equal(invalid.body.error.code, 'VALIDATION_ERROR');

  const deactivated = await request(app)
    .post('/api/v1/users/me/deactivate')
    .set(owner)
    .send({ confirmation: true, reason: 'Taking a long break' });
  assert.equal(deactivated.status, 200);
  assert.equal(deactivated.body.data.accountStatus, 'deactivated');
  assert.ok(deactivated.body.data.deactivatedAt);

  const stored = await UserModel.findOne({
    authId: 'u-deactivation-owner',
  }).lean();
  assert.equal(stored.accountStatus, 'deactivated');
  assert.ok(stored.accessRevokedAt);
  assert.equal(
    (await ListingModel.findOne({ publicId: 'l-deactivation-test' }).lean())
      .status,
    'inactive',
  );
  const denied = await request(app).get('/api/v1/users/me').set(owner);
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error.code, 'ACCOUNT_RESTRICTED');

  const reactivated = await request(app)
    .patch(`/api/v1/users/${stored._id}/status`)
    .set(admin)
    .send({ status: 'active' });
  assert.equal(reactivated.status, 200);
  assert.equal(reactivated.body.data.accountStatus, 'active');
  assert.ok(reactivated.body.data.reactivatedAt);

  const newSession = await request(app)
    .post('/api/v1/users/session')
    .set(owner);
  assert.equal(newSession.status, 200);
  assert.equal(
    await adminModule.Model.countDocuments({
      targetId: 'u-deactivation-owner',
      action: { $in: ['account.self_deactivated', 'account.active'] },
    }),
    2,
  );
});

test('blocks deactivation while an account has an open booking', async () => {
  const renter = identity({
    id: 'u-obligated-renter',
    email: 'obligated@renthub.my',
    name: 'Obligated Renter',
  });
  await request(app).post('/api/v1/users/session').set(renter);
  await BookingModel.create({
    publicId: 'RH-BKG-2026-DEACT',
    listingId: 'l-obligation-test',
    listingTitle: 'Open Booking Item',
    listingType: 'physical',
    renterId: 'u-obligated-renter',
    renterName: 'Obligated Renter',
    ownerId: 'u-another-owner',
    startDate: new Date('2026-10-10T00:00:00Z'),
    endDate: new Date('2026-10-11T00:00:00Z'),
    fulfilmentMethod: 'pickup',
    pricing: {
      baseAmount: 50,
      securityDeposit: 20,
      damageWaiverFee: 0,
      platformFee: 5,
      total: 75,
      currency: 'MYR',
    },
    status: 'pending',
  });

  const response = await request(app)
    .post('/api/v1/users/me/deactivate')
    .set(renter)
    .send({ confirmation: true, reason: 'No longer needed' });
  assert.equal(response.status, 409);
  assert.equal(response.body.error.code, 'ACCOUNT_HAS_OPEN_OBLIGATIONS');
  assert.equal(
    (await UserModel.findOne({ authId: 'u-obligated-renter' }).lean())
      .accountStatus,
    'active',
  );
  await BookingModel.deleteOne({ publicId: 'RH-BKG-2026-DEACT' });
});

test('returns only safe fields from a public profile', async () => {
  const headers = identity({
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Sarah J.',
    roles: 'owner',
  });
  await request(app).post('/api/v1/users/session').set(headers);

  const response = await request(app).get('/api/v1/users/public/u-owner');
  assert.equal(response.status, 200);
  assert.equal(response.body.data.displayName, 'Sarah J.');
  assert.equal(response.body.data.email, undefined);
  assert.equal(response.body.data.accountStatusReason, undefined);
});
