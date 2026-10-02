# RentHub remaining implementation and setup checklist

Last verified: 2 October 2026

This checklist separates code that exists from external services, credentials,
model artifacts, and production checks that still have to be supplied. No secret
values are recorded here.

## Completed in the current phase

- [x] Added a restart-safe lifecycle scheduler to the API process.
- [x] Expire pending, unpaid bookings after a configurable period.
- [x] Send one-time reminders for upcoming starts and physical-item returns.
- [x] Mark late physical rentals as `overdue` and keep return/extension actions
  available in the renter UI.
- [x] Send service-delivery and service-completion reminders.
- [x] Deduplicate automated notifications across repeated scheduler runs.
- [x] Added administrator-only technology health and manual lifecycle-run APIs.
- [x] Added the technology-health panel and operational counts to the live
  Flutter administrator dashboard.
- [x] Added AI artifact visibility to the FastAPI health response.
- [x] Added environment settings for interval, expiry, reminder, and grace
  periods to `services/api/.env.example`.
- [x] Added automated lifecycle, administrator health, reporting, password-
  reset, and local bearer-session tests; the complete API suite passes 67/67
  with isolated test auth and local storage.
- [x] Dart static analysis of `lib/` passes with no issues.
- [x] Added persistent daily/weekly/monthly administrator report schedules.
- [x] Added manual and scheduled CSV generation for platform summaries,
  bookings, payments, users, listings, and disputes.
- [x] Added authenticated CSV downloads, audit entries, duplicate-run locking,
  formula-injection protection, and a 10,000-row export cap.
- [x] Added the reporting endpoints and request contracts to the shared OpenAPI
  document.
- [x] Replaced the live forgot/change-password simulation. Auth0 accounts use
  Auth0 reset links; local MongoDB accounts use expiring, single-use codes sent
  through Nodemailer SMTP or Resend, with hashed storage, cooldown, attempt
  limits, and generic account-discovery-safe responses.
- [x] Added a Security-page inventory for registered notification devices with
  user-scoped removal. This is intentionally labelled separately from Auth0
  login-session revocation.
- [x] Added entity-aware push tap routing for conversations, bookings, rentals,
  payments, disputes, and loyalty activity, with a notification-centre fallback.
- [x] Removed prefilled login credentials and added restart-persistent,
  role-aware sessions that are revalidated through `/users/me`.
- [x] Replaced live development identity headers with signed short-lived local
  JWTs, rotating MongoDB refresh sessions, secure Flutter credential storage,
  automatic refresh, authenticated Socket.IO, and lifecycle revocation.
- [x] Added a user-facing local login-session inventory with current-device
  identification, individual revocation, sign-out-all-others, and immediate
  Socket.IO disconnection for revoked sessions.
- [x] Added protected image messages with authenticated upload/download,
  participant-only access, Socket.IO delivery, conversation previews, full-size
  viewing, attachment cleanup on failed sends, and server-side ownership checks.

## Immediate local setup still required

The existing `services/api/.env` file was inspected only by key/status; values
were not printed. It is not currently usable:

- [ ] Replace the placeholder `MONGODB_URI`. No MongoDB server was listening on
  local port 27017 during this check.
- [ ] Complete the selected development profile with MongoDB, local JWT, email,
  Supabase Storage, AI, and Ganache credentials.
- [ ] For a local demonstration, use development-safe settings:

  ```dotenv
  NODE_ENV=development
  MONGODB_URI=mongodb://localhost:27017/renthub
  AUTH_MODE=local
  LOCAL_JWT_SECRET=replace-with-at-least-32-random-characters
  LOCAL_ACCESS_TOKEN_MINUTES=15
  LOCAL_REFRESH_TOKEN_DAYS=30
  EMAIL_MODE=smtp
  EMAIL_FROM=RentHub <your.personal@gmail.com>
  SMTP_HOST=smtp.gmail.com
  SMTP_PORT=587
  SMTP_SECURE=false
  SMTP_USERNAME=your.personal@gmail.com
  SMTP_PASSWORD=your-google-app-password-without-spaces
  PASSWORD_RESET_SECRET=replace-with-at-least-32-random-characters
  STORAGE_MODE=supabase
  SUPABASE_URL=https://your-project-ref.supabase.co
  SUPABASE_SECRET_KEY=replace-with-server-secret-key
  SUPABASE_STORAGE_BUCKET=renthub-files
  MAPS_MODE=openstreetmap
  OPENSTREETMAP_NOMINATIM_URL=https://nominatim.openstreetmap.org
  OPENSTREETMAP_USER_AGENT=RentHub/1.0 (contact: your-email@example.com)
  OPENSTREETMAP_MIN_INTERVAL_MS=1000
  AI_SERVICE_URL=http://localhost:8001
  AI_ENFORCEMENT_MODE=advisory
  BLOCKCHAIN_MODE=ganache
  GANACHE_RPC_URL=http://localhost:8545
  LIFECYCLE_JOBS_ENABLED=true
  LIFECYCLE_JOB_INTERVAL_MS=900000
  PENDING_BOOKING_EXPIRY_MINUTES=60
  LIFECYCLE_REMINDER_HOURS=24
  OVERDUE_GRACE_HOURS=0
  ```

- [ ] Install/start MongoDB Community locally, or install Docker Desktop and run
  `docker compose up -d mongodb`. Docker is not installed on this workstation.
- [ ] From `services/api`, run `npm.cmd run seed`, then `npm.cmd run dev`.
- [ ] Confirm `GET http://localhost:3000/api/v1/ready` returns HTTP 200.
- [ ] Enable two-step verification for the sender Google account, create an App
  Password, and send a password-reset code to a real test account. Keep the App
  Password and reset secret only in the ignored `.env`.
- [x] Make live Express/MongoDB repositories the Flutter default. Normal
  `flutter run` no longer needs `USE_MOCKS=false`; `USE_MOCKS=true` is retained
  only as an explicit UI-preview/test override.
- [ ] Launch Flutter with the appropriate mobile `API_BASE_URL` and `SOCKET_URL`
  as documented in the root README.
- [ ] Sign in, close and reopen the app, verify session restoration, then log
  out and confirm the revoked session cannot access `/users/me`.

Do not copy `.env.example` over the existing `.env` without first preserving any
real credentials stored outside source control.

## MongoDB / production data setup

- [ ] Create the Atlas project/cluster and a dedicated RentHub database, or
  finish the local MongoDB installation.
- [ ] Create a least-privilege database user and add the intended IP/network
  allow-list entry.
- [ ] Put the real connection string only in ignored `.env`/deployment secrets.
- [ ] Run `npm.cmd run preflight:production` and confirm database connectivity,
  database name, and topology.
- [ ] Prefer an Atlas replica set/cluster for transaction-capable production
  operation; a standalone local MongoDB instance cannot provide the same
  multi-document transaction guarantees.
- [ ] Establish backup, restore, retention, and index-monitoring procedures.
- [ ] Run the Phase 13 write/restart/read drill against a dedicated Atlas test
  database before using any production data.

## Auth0 setup

- [ ] Replace the placeholder Auth0 issuer/tenant value.
- [ ] Set Flutter `AUTH0_DATABASE_CONNECTION` to the enabled Auth0 database
  connection name and verify password-reset email delivery.
- [ ] Verify the API audience, RS256 signing, role claim, email claim, and name
  claim against the actual tenant.
- [ ] Register the Flutter Web callback/logout/origin URLs for ports 8080 and
  3001, plus the native loopback callback if the desktop build is demonstrated.
- [ ] Assign renter, Owner, and administrator roles to dedicated E2E users.
- [ ] Run login and role-access checks with real short-lived Auth0 tokens.
- [ ] Resolve the product decision on Google/social login; it is not currently
  implemented.
- [x] Self-service account deactivation, immediate API/Socket.IO access
  revocation, listing hiding, administrator reactivation, and audit logging are
  implemented.
- [x] Local accounts can inspect and selectively revoke multi-device login
  sessions from the Security page.
- [ ] Auth0 session inventory, token lifetime, and rotation remain managed by
  and require configuration in the real Auth0 tenant if Auth0 is selected.

## Supabase Storage setup

- [ ] Create a Supabase project and a private `renthub-files` bucket.
- [ ] Add the project URL and server secret to the ignored API `.env`; never
  expose the server secret to Flutter or commit it.
- [ ] Keep client access private. RentHub API routes perform user/participant
  authorization before serving listing images or protected evidence.
- [ ] Run the production preflight write/delete probe.
- [ ] Complete a real upload/download/access-control E2E test for listing,
  identity, handover, return, dispute, and claim evidence.
- [ ] Keep Firebase only if push notifications are enabled with
  `FCM_MODE=firebase`.

## AI / machine-learning / image-processing setup

The API and UI integrations exist. A Python 3.11 virtual environment and the
required packages are installed in `services/ai/.venv`, but the trained model
artifacts are not present. Docker remains optional for this local workflow.

- [x] Install Python 3.11 and create a virtual environment in `services/ai`.
- [x] Install `services/ai/requirements.txt`.
- [ ] Start FastAPI on port 8001 and confirm its health endpoint.
- [ ] Generate and review the XGBoost price artifact and Surprise SVD artifact:

  ```powershell
  python -m app.training.train_tabular_models
  ```

- [ ] Obtain reviewed, labelled image datasets with documented provenance.
- [ ] Train/evaluate the EfficientNet-B0 image-risk model and YOLO item detector.
- [ ] Install EasyOCR model files, or intentionally enable the first download.
- [ ] Produce and retain held-out metrics; label synthetic tabular evaluation as
  synthetic in the FYP report.
- [ ] Keep `AI_ENFORCEMENT_MODE=advisory` until image artifacts and thresholds
  have been evaluated. Do not enable strict mode merely because files exist.
- [ ] Run the FastAPI tests and an end-to-end document/item/pricing/recommendation
  flow after the Python runtime and artifacts are installed.

Expected runtime paths are listed in `services/ai/.env.example` and
`services/ai/README.md`.

## Blockchain setup

- [ ] Start Ganache; nothing was listening on port 8545 during this check.
- [ ] From `blockchain`, run `npm.cmd run compile`, then
  `npm.cmd run node:ganache` in a dedicated terminal.
- [ ] Set `BLOCKCHAIN_MODE=ganache` and confirm the configured contract artifact
  exists.
- [ ] Run an approved physical booking through deploy/sign, handover, dispute,
  resolution or dismissal, return completion, and cancellation while checking
  the administrator health panel.
- [ ] Keep this clearly labelled as a local FYP prototype. Wallet ownership,
  non-custodial signing, public-chain deployment, contract audit, and real-value
  escrow are not implemented.

## External or deferred product work

- [ ] Real payment-provider authorization, capture, refund, payout, and webhook
  reconciliation are not implemented; payments remain simulated.
- [ ] Firebase Cloud Messaging production activation remains pending. The code
  integration is present, while MongoDB/Socket.IO remains the source of truth.
  - [ ] Create the Firebase project and register the Android app as
    `com.weith.renthub`.
  - [x] Generate the Android runner with application ID `com.weith.renthub`.
  - [ ] Choose the final iOS bundle ID and generate/configure its runner on
    macOS with Xcode.
  - [ ] Configure FlutterFire files locally and server credentials through
    environment/workload identity; do not commit service-account secrets.
  - [x] Add device-token registration, refresh, sign-out removal, and stale-token
    cleanup endpoints backed by MongoDB.
  - [x] Add the API delivery adapter with error isolation while retaining
    MongoDB notifications as the source of truth.
  - [x] Add Flutter permission prompts plus foreground, background, and tapped
    notification handling.
  - [x] Add a user-visible registered-device list/removal flow and entity-aware
    notification tap routing.
  - [ ] Verify booking, message, rental, dispute, and account notifications on a
    real device/browser end to end.
- [x] Protected image messages are implemented.
- [ ] Location-pin messages are not implemented.
- [ ] Interactive OpenStreetMap rendering and MongoDB geospatial search remain
  deferred. The Nominatim backend adapter, caching, and rate limiting are ready.
- [ ] Cross-Owner multi-item checkout/bundles are not implemented. Existing
  bundle metadata supports only the simpler same-Owner presentation.
- [x] Internal scheduled administrator reports and CSV exports are implemented.
  Email delivery remains dependent on a future email-provider integration.
- [ ] The expanded searchable/category-specific guide remains a basic help page.
- [ ] Production monitoring, alerting, centralized logs, rate limiting policy,
  TLS/domain configuration, CI/CD, and disaster-recovery drills still need an
  operational design.

## Final verification still required

- [ ] Run the production preflight with real Atlas/Auth0/Supabase credentials.
- [ ] Run the Phase 13 write/restart/read E2E drill.
- [ ] Run Python tests and capture model metrics after installing Python.
- [ ] Repeat Hardhat and Ganache smoke tests with the final environment.
- [x] Full Flutter tests pass with 74 tests and two existing environment-dependent
  skips. The administrator web build also passes; the existing Socket.IO WASM
  advisory and Cupertino-font warning remain non-blocking.
- [ ] Rebuild the renter/Owner web entry point after the final external-provider
  configuration is available.
- [ ] Perform a manual browser pass at 1440x900 and 1024px for the admin health
  panel, and at 390px/360px for overdue actions and status badges.
- [ ] Verify all three interfaces with real authentication and persisted data,
  including messaging after an application/API restart.

## Useful verification commands

```powershell
# API tests without consuming production/Auth0/Supabase settings
cd services/api
$env:NODE_ENV='test'
$env:AUTH_MODE='mock'
$env:STORAGE_MODE='local'
$env:UPLOAD_DIRECTORY='.data/test-uploads'
npm.cmd test

# Production provider preflight (only after real secrets are configured)
npm.cmd run preflight:production

# Contract tests
cd ../../blockchain
npm.cmd test
```
