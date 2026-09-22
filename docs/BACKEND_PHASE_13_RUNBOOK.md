# Backend Phase 13 Runbook — Production Preflight and Live E2E

Phase 13 verifies the final RentHub client and API against real MongoDB Atlas, Auth0, and Firebase Storage services. Credentials remain in ignored environment files or process environment variables and must never be committed.

## 1. API environment

Create `services/api/.env` from `.env.example` and supply the project values:

```dotenv
NODE_ENV=production
MONGODB_URI=mongodb+srv://...
AUTH_MODE=auth0
AUTH0_ISSUER_BASE_URL=https://YOUR_TENANT.auth0.com/
AUTH0_AUDIENCE=https://api.renthub.my
AUTH0_ROLES_CLAIM=https://renthub/roles
AUTH0_EMAIL_CLAIM=https://renthub/email
AUTH0_NAME_CLAIM=https://renthub/name
STORAGE_MODE=firebase
FIREBASE_STORAGE_BUCKET=YOUR_BUCKET
CORS_ORIGINS=http://localhost:8080,http://localhost:3001
```

Provide Firebase Application Default Credentials outside the repository through `GOOGLE_APPLICATION_CREDENTIALS` or the deployment platform's workload identity.

Use a dedicated Atlas test database for the drill. Do not run the seed command against a production customer database.

## 2. Production preflight

From `services/api`:

```powershell
npm.cmd run preflight:production
```

The command checks:

- production-safe environment configuration;
- MongoDB reachability, database name, and topology;
- Auth0 discovery metadata and current JWKS signing keys;
- Firebase bucket access plus a temporary write/delete probe.

It prints no connection string, access token, service-account data, or credential path. A standalone MongoDB topology produces a warning because multi-document transactions are unavailable.

## 3. E2E identities

Obtain short-lived API access tokens for three dedicated test users. Their Auth0 roles must be `owner`, `renter`, and `admin`, respectively. Set the tokens only in the current terminal:

```powershell
$env:RENTHUB_E2E_OWNER_TOKEN = 'SHORT_LIVED_OWNER_TOKEN'
$env:RENTHUB_E2E_RENTER_TOKEN = 'SHORT_LIVED_RENTER_TOKEN'
$env:RENTHUB_E2E_ADMIN_TOKEN = 'SHORT_LIVED_ADMIN_TOKEN'
```

The runner reads tokens from the environment. They are not included in command arguments, source files, test output, or generated documentation.

## 4. Write, restart, and read

Start the API with the production `.env`, choose a unique non-secret run ID, and execute:

```powershell
.\scripts\run-live-e2e.ps1 -Phase write -RunId atlas-001
```

Restart the API process or deployment without changing the database or bucket. Then execute the read phase with the same run ID:

```powershell
.\scripts\run-live-e2e.ps1 -Phase read -RunId atlas-001
```

The write phase uses the production Flutter API client to create user sessions, upload a real listing image and private handover/return evidence, moderate a listing, book and authorize payment, approve and complete the rental, exchange a message, submit a review, and inspect transactions and notifications. The read phase starts a separate Flutter test process and verifies that the same listing, booking, rental, messages, review, payment state, and profile changes persisted.

## 5. Final manual UI pass

After the automated drill, launch the renter/Owner client and administrator portal with the Auth0 Dart defines from the Phase 12 guide. Verify Universal Login, role access, uploaded-image rendering, evidence access rules, messaging, and administrator moderation in Chrome or Edge.

Remove the three token environment variables when finished:

```powershell
Remove-Item Env:RENTHUB_E2E_OWNER_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:RENTHUB_E2E_RENTER_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:RENTHUB_E2E_ADMIN_TOKEN -ErrorAction SilentlyContinue
```
