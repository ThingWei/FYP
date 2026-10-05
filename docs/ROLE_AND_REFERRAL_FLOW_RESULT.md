# Role and Referral Flow Result

## Result

RentHub now treats public marketplace capability and the currently displayed interface as separate concepts:

- an ordinary account has exactly `roles: [renter, owner]`;
- `activeRole` is either `renter` or `owner` and selects the current Flutter interface;
- an administrator has exactly `roles: [admin]` and cannot use marketplace role switching;
- a verified token that mixes `admin` with a marketplace role is rejected with `CONTRADICTORY_ROLE_CLAIMS` and a structured security log.

Local registration stores both marketplace roles and uses the submitted role as the starting interface. Local login can start either public interface. Auth0 token normalization, MongoDB synchronization, local JWT authorization, model validation, mock data, and Flutter now use the same invariant. A narrower Auth0 claim cannot remove a public capability. Flutter awaits `PATCH /users/me/active-role` before committing an Auth0 starting role or an in-app role switch, and keeps the previous interface if persistence fails.

## Existing-user migration

The migration is dry-run by default:

```powershell
cd services/api
npm.cmd run migrate:marketplace-roles
```

It reports counts for legacy renter, legacy owner, normalized marketplace, reordered marketplace, admin, mixed-admin, and invalid records without printing user identifiers or credentials. It plans changes only for legacy single-role public accounts and reordered valid public accounts. Mixed administrator/public and invalid records are left untouched for manual security review.

Before applying it:

1. Back up the target database with an approved MongoDB backup process, for example `mongodump --uri $env:MONGODB_URI --out <dated-backup-directory>`.
2. Run the dry-run command against staging and review `manualReview`; do not apply while that count is unexplained.
3. Run application authentication and role-switch smoke tests against staging.
4. Apply explicitly with `npm.cmd run migrate:marketplace-roles -- --apply`.
5. Run the dry run again. `remainingUpdates` must be zero; a second apply is a no-op.
6. Verify that public records contain both roles, administrators contain only admin, and every `activeRole` belongs to its role set.

Rollback is a restore from the pre-migration backup using the organization's reviewed `mongorestore` procedure. Do not use an ad-hoc reverse update because the legacy role set cannot be inferred safely after normalization.

The apply command was not run during implementation because the configured MongoDB may contain real project data.

## Referral lifecycle

```text
code applied
  -> pending / browse_listings
  -> booking started / view_booking
  -> physical: Owner confirms return
     or service: renter confirms completion
  -> earliest eligible completed booking is recorded
  -> referrer points + referee reward record
  -> rewarded / view_reward
```

Creating or paying for a booking is not sufficient. There is no administrator approval step.

`GET /rewards/summary` now exposes `completionTrigger`, `progressState`, `nextAction`, `nextActionMessage`, lifecycle dates, the qualifying booking, and the configured referee reward amount. Flutter displays waiting, programme-paused, reconciliation, and rewarded states from this contract. `browse_listings` selects Explore and `view_booking` selects Bookings in the existing renter shell; it does not create a second marketplace shell.

New referral applications are rejected with `LOYALTY_DISABLED` while the programme is paused. Existing pending referrals are retained and show `wait_for_programme`. After re-enablement, summary loading safely reconciles them.

## Recovery and idempotency

Referral reconciliation deterministically selects the earliest completed booking by `completedAt`, then `publicId`, and verifies that the referral was applied before completion. It does not depend on the completed-booking count remaining exactly one.

Loyalty account updates use a unique operation marker, and ledger records retain their existing unique `sourceKey`. This supports retries after partial processing without applying a balance change twice or duplicating a reward. The qualifying booking is stored on the referral before grants begin. Summary loading calls the same reconciliation operation, so a stranded pending referral can self-heal.

Rental completion is authoritative before non-critical reward and notification follow-ups. Those follow-ups are attempted independently; a notification failure cannot turn an already completed rental endpoint into an unretryable client error. Referral notifications also use stable deduplication keys.

## Main implementation files

- Role policy, schema, sessions, migration and seed: `services/api/src/modules/user/rolePolicy.js`, `user.model.js`, `user.service.js`, `localSession.service.js`, `services/api/src/middleware/auth.js`, `services/api/src/scripts/migrateMarketplaceRoles.js`, `seed.js`, and `services/api/package.json`.
- Referral persistence and recovery: `services/api/src/modules/loyalty/loyalty.model.js`, `loyalty.repository.js`, `loyalty.service.js`, `rental.service.js`, and `dispute.service.js`.
- Flutter persistence and UI: `auth_repository.dart`, `auth_controller.dart`, `register_screen.dart`, `role_selection_screen.dart`, `domain_models.dart`, `live_loyalty_page.dart`, `live_renthub_controller.dart`, `live_renter_shell.dart`, and `app.dart`.
- Contract and guidance: `packages/api_contracts/openapi.yaml`, `README.md`, `docs/BACKEND_PHASE_8_RESULT.md`, and `docs/BACKEND_PHASE_12_RESULT.md`.
- Regression coverage: API user, role-policy, loyalty, booking/rental, listing, payment, and recommendation tests; Flutter auth, account, and role/referral tests.

## Validation run on 5 October 2026

- Focused API role/referral/lifecycle run: 41 passed, 0 failed.
- Complete API suite with `AUTH_MODE=mock`, `STORAGE_MODE=local`, and `BLOCKCHAIN_MODE=disabled`: 121 passed, 3 skipped, 0 failed.
- Dart format check: 145 files checked, 0 changes required.
- Dart analyzer: no issues found.
- Complete Flutter suite: 106 passed, 2 skipped, 0 failed.
- Live Flutter web build with `USE_MOCKS=false`: passed.
- OpenAPI behavior is covered by the API and Dart contract tests; no production migration was executed.

The web build still reports the repository's existing Socket.IO WebAssembly compatibility warning and missing Cupertino icon-font notice. The standard JavaScript web build succeeds.

## Known limitation

The referee's generated reward code is a persistent reward record. The current booking/checkout contract does not consume that code or settle a cash discount. Checkout reward application remains a separate follow-up and the UI states this explicitly.
