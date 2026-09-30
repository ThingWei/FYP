# RentHub remaining implementation and setup checklist

Last verified: 30 September 2026

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
- [x] Added automated lifecycle, administrator health, and reporting tests; the
  complete API suite passes 58/58 when run with isolated test auth and local
  storage.
- [x] Dart static analysis of `lib/` passes with no issues.
- [x] Added persistent daily/weekly/monthly administrator report schedules.
- [x] Added manual and scheduled CSV generation for platform summaries,
  bookings, payments, users, listings, and disputes.
- [x] Added authenticated CSV downloads, audit entries, duplicate-run locking,
  formula-injection protection, and a 10,000-row export cap.
- [x] Added the reporting endpoints and request contracts to the shared OpenAPI
  document.

## Immediate local setup still required

The existing `services/api/.env` file was inspected only by key/status; values
were not printed. It is not currently usable:

- [ ] Replace the placeholder `MONGODB_URI`. No MongoDB server was listening on
  local port 27017 during this check.
- [ ] Decide on a development or production profile. The current file selects
  `NODE_ENV=production`, `AUTH_MODE=auth0`, and `STORAGE_MODE=firebase`, while
  required MongoDB/Auth0/Firebase values are still placeholders.
- [ ] For a local demonstration, use development-safe settings:

  ```dotenv
  NODE_ENV=development
  MONGODB_URI=mongodb://localhost:27017/renthub
  AUTH_MODE=mock
  STORAGE_MODE=local
  UPLOAD_DIRECTORY=.data/uploads
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
- [ ] Launch Flutter with `USE_MOCKS=false`, `API_BASE_URL`, and `SOCKET_URL` as
  documented in the root README.

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
- [ ] Verify the API audience, RS256 signing, role claim, email claim, and name
  claim against the actual tenant.
- [ ] Register the Flutter Web callback/logout/origin URLs for ports 8080 and
  3001, plus the native loopback callback if the desktop build is demonstrated.
- [ ] Assign renter, Owner, and administrator roles to dedicated E2E users.
- [ ] Run login and role-access checks with real short-lived Auth0 tokens.
- [ ] Resolve the product decision on Google/social login; it is not currently
  implemented.
- [ ] Account deactivation and session/device management remain unimplemented.

## Firebase Storage setup

- [ ] Replace the placeholder Firebase bucket.
- [ ] Provide Application Default Credentials using
  `GOOGLE_APPLICATION_CREDENTIALS` or workload identity; never commit a service
  account JSON file.
- [ ] Configure bucket CORS and IAM so public listing images and private evidence
  follow the intended access rules.
- [ ] Run the production preflight write/delete probe.
- [ ] Complete a real upload/download/access-control E2E test for listing,
  identity, handover, return, dispute, and claim evidence.

## AI / machine-learning / image-processing setup

The API and UI integrations exist, but the runtime and trained artifacts do not.
The Python launcher is present, but it reports that no Python interpreter is
installed. Docker is also unavailable. All five expected model locations were
empty during this check.

- [ ] Install Python 3.11 and create a virtual environment in `services/ai`.
- [ ] Install `services/ai/requirements.txt` and start FastAPI on port 8001.
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
- [ ] Firebase Cloud Messaging push delivery is not implemented; current
  notifications are MongoDB/Socket.IO application notifications.
- [ ] Image messages and location-pin messages are not implemented.
- [ ] Google Maps/geospatial search is still deferred.
- [ ] Cross-Owner multi-item checkout/bundles are not implemented. Existing
  bundle metadata supports only the simpler same-Owner presentation.
- [x] Internal scheduled administrator reports and CSV exports are implemented.
  Email delivery remains dependent on a future email-provider integration.
- [ ] The expanded searchable/category-specific guide remains a basic help page.
- [ ] Production monitoring, alerting, centralized logs, rate limiting policy,
  TLS/domain configuration, CI/CD, and disaster-recovery drills still need an
  operational design.

## Final verification still required

- [ ] Run the production preflight with real Atlas/Auth0/Firebase credentials.
- [ ] Run the Phase 13 write/restart/read E2E drill.
- [ ] Run Python tests and capture model metrics after installing Python.
- [ ] Repeat Hardhat and Ganache smoke tests with the final environment.
- [x] Full Flutter tests pass with 72 tests and two existing environment-dependent
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
# API tests without consuming production/Auth0/Firebase settings
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
