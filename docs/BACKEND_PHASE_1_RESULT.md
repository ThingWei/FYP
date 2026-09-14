# RentHub Backend Phase 1 Result

Date: 14 September 2026

## Outcome

The Express API now has a tested MongoDB foundation and a strict User/Auth module. Flutter remains on mock repositories by default, so the completed UI can still be demonstrated without running the API.

## Architecture

```text
Flutter -> Express /api/v1 -> Mongoose -> MongoDB
                 |
                 +-> mock identity headers in development
                 +-> Auth0 JWT verification in production
```

MongoDB stores RentHub profiles and business data. It does not receive passwords. Auth0 will own production credentials and issue signed access tokens.

## Implemented

- Validated environment configuration
- Explicit MongoDB connect, disconnect and health helpers
- Process liveness and database readiness endpoints
- Graceful API shutdown on `SIGINT` and `SIGTERM`
- Auth0-compatible identity normalization and development mock identities
- Production safeguard that rejects `AUTH_MODE=mock`
- Strict Mongoose user schema with:
  - unique Auth0/mock identity and email
  - renter, Owner and administrator roles
  - active-role switching
  - trust score and verification state
  - active, suspended and banned account states
  - Malaysian addresses and account preferences
  - blocked-user relationships
- Layered user model, repository, service, controller, validation and router files
- Privacy-safe public profiles
- Administrator user directory and account-status actions
- Idempotent seed script aligned with the Flutter prototype
- Dependency lockfile and reproducible production Docker install

## User endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/users/session` | Create or refresh the authenticated profile |
| `GET` | `/api/v1/users/me` | Read the current profile |
| `PATCH` | `/api/v1/users/me` | Update profile, addresses or settings |
| `PATCH` | `/api/v1/users/me/active-role` | Switch to an assigned role |
| `POST` | `/api/v1/users/me/blocked-users/:userId` | Block a user |
| `DELETE` | `/api/v1/users/me/blocked-users/:userId` | Unblock a user |
| `GET` | `/api/v1/users/public/:id` | Read safe public profile fields |
| `GET` | `/api/v1/users` | Search/filter users as an administrator |
| `PATCH` | `/api/v1/users/:id/status` | Suspend, ban or reactivate an account |
| `GET` | `/api/v1/health` | Process liveness |
| `GET` | `/api/v1/ready` | MongoDB readiness |

## Local run instructions

From the repository root:

```powershell
Copy-Item services/api/.env.example services/api/.env
docker compose up -d mongodb
Set-Location services/api
npm install
npm run seed
npm run dev
```

Use `http://localhost:3000/api/v1/health` for the liveness check. When using Flutter Web, run it on a CORS-approved port such as `8080`.

In mock mode, requests can use these development-only headers:

```text
x-user-id: u-renter
x-user-email: renter@renthub.my
x-user-name: Alex Tan
x-user-roles: renter
```

## Validation

- JavaScript syntax check passed for all API source and test files.
- `npm test` passed all 13 tests.
- The test suite uses `mongodb-memory-server`; it does not modify the developer's local MongoDB data.
- Seed execution is tested twice to verify that it is idempotent.
- `npm install` reported zero vulnerabilities.

## Next phase

Implement strict Listing and Availability modules, seed the complete UI catalog, and add the first live Flutter repositories behind `USE_MOCKS=false`.
