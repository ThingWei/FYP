# RentHub Live MongoDB End-to-End Result

## A. Environment used

- Verification date: 18 September 2026 (Asia/Kuala_Lumpur).
- Database: local ephemeral MongoDB provided by the repository's existing `mongodb-memory-server` development dependency.
- Database name: `renthub`.
- API: Node.js/Express started with `npm.cmd start` on port 3000.
- Flutter: VM test processes using the production `ApiClient`, `SessionIdentity`, and `LiveRentHubController` classes.
- Authentication mode: the existing development `mock` header identity mode.
- MongoDB Atlas was **not** used or tested.
- No `.env` file was present. The local URI was supplied only to the test processes through `MONGODB_URI`.
- No credentials were printed, written to the repository, or committed.

This environment proves persistence across API requests and a Flutter process restart while the local MongoDB process remains running. Because the database was intentionally ephemeral, it does not prove persistence across a MongoDB server restart.

## B. Live-mode confirmation

Both Flutter E2E phases were compiled and run with:

```text
USE_MOCKS=false
API_BASE_URL=http://localhost:3000/api/v1
SOCKET_URL=http://localhost:3000
```

The opt-in test is [live_mongodb_e2e_test.dart](../apps/renthub_flutter/test/live_mongodb_e2e_test.dart). It uses the same live controller and HTTP client as the final renter and Owner shells; it does not substitute mock repositories.

The browser-control connector reported no available Chrome, Edge, in-app browser, or native app. Therefore, a manual browser click-through was not performed and is not marked as passed. The automated Flutter-to-API-to-MongoDB acceptance path did pass.

## C. Persistence evidence

The write phase created two development users and drove one new physical listing through moderation, booking, simulated authorization, Owner approval, handover, messaging, return, settlement, review, notification, and loyalty-award processing.

Persistent identifiers:

- Listing: `l-6aad20c6b36bfee66e2d2c53`
- Booking: `RH-BKG-2030-6E2D2CB3`
- Rental: `RH-RNT-2030-6E2D2CEE`

The write test process exited. A separate Flutter test process then authenticated the same users, reloaded the live renter, Owner, and administrator controllers, and found the same records and booking ID.

| Flow | API reached | Stored in MongoDB | Persists after Flutter restart | Status |
|---|---:|---:|---:|---|
| User/session and profile name update | Yes | `u-e2e-renter`, name `E2E Renter Persisted` | Yes | Passed |
| Owner listing creation and administrator moderation | Yes | Listing remained `active` | Yes | Passed |
| Renter booking creation | Yes | Same booking ID in renter and Owner views | Yes | Passed |
| Booking creation retry | Yes | Sequential and concurrent retries return one booking ID | Not rerun | Passed in follow-up API tests |
| Authoritative price calculation | Yes | Base RM82 + deposit RM100 = total RM182 | Yes | Passed |
| Payment authorization retry | Yes | Same authorization returned for the same idempotency key | Yes | Passed |
| Owner approval and rental creation | Yes | Linked rental used the same booking ID | Yes | Passed |
| Handover, return and Owner inspection | Yes | Rental and booking remained `completed` | Yes | Passed |
| Simulated payment records | Yes | Authorization, capture, deposit release and Owner settlement | Yes | Passed |
| Booking-linked message | Yes | Message remained in thread `THR-E66E2D2CB6` | Yes | Passed |
| Notifications | Yes | Four renter notifications were stored | Yes | Passed |
| Completed-rental review | Yes | Review `RH-REV-E66E2D2DA6`, rating 5 | Yes | Passed |
| Automatic loyalty award | Yes | 120 completion points linked to the rental | Yes | Passed |

Direct Mongoose verification independently confirmed the stored user, listing, booking, rental, four payment documents, conversation/message, notifications, review, loyalty account, and reward-ledger entry.

API readiness after the flow reported:

```text
process: ok
readiness: ready
database: up / connected
```

## D. Remaining mock-only or deferred areas

The principal renter/Owner lifecycle above is live. RentHub is not yet fully live in every UI area:

- Login and registration use the development header identity adapter. Passwords are not authenticated and Auth0/JWT is not integrated.
- Profile editing, saved addresses, notification preferences, and identity-verification status are now connected to MongoDB in the final live renter and Owner shells. Real document upload remains deferred; the development verification flow stores local placeholder references and OCR-result placeholders.
- The administrator Verification destination now reviews MongoDB-backed pending identity submissions and records decisions in notifications and audit logs.
- The live Reports destination currently covers persistent reported messages, not the full analytics/reporting scope.
- Platform Settings currently persists loyalty/referral rules only; categories, policies, notification templates, verification thresholds, and content settings remain deferred.
- Wishlist, listing comparison, advanced discovery/recommendations, and several rich filter behaviors remain in the mock interface rather than the final live shell.
- Owner availability, listing editing/resubmission, promotion configuration, and physical-item bundle management are now connected through the live controller. Bundle checkout remains a future extension; the current renter UI presents the offer on the listing.
- Evidence and listing images use local placeholder references. Firebase/object storage upload is not integrated.
- Referral sharing produces a visible local action but does not invoke an operating-system share provider.
- Maps/geospatial search, Firebase push notifications, real AI/ML inference, and real local smart-contract execution are not part of this verified path.
- Payments, refunds, deposit allocation, claims, and dispute allocations are intentionally simulated, although their current records persist in MongoDB.

## E. Seed data

The test retained all seed/demo data. The following visible records come from `services/api/src/scripts/seed.js`, then travel through Express to Flutter in live mode; they are not Flutter hard-coded mock objects:

- Alex Tan, Sarah J., Aina Rahman, Nur Izzati, and Admin Farah.
- Sony Alpha a7S III Mirrorless Camera and the other twelve seeded listings.
- Event Photography Package.
- Booking `RH-BKG-2026-09142` and the other seeded booking/rental states.
- Seeded payments, conversations, messages, notifications, review, dispute, claim, loyalty accounts, reward entries, referral, and loyalty rules.

The E2E records listed in section C were created after seeding and were not inserted by the seed script.

## F. Problems found

1. **Manual browser verification unavailable.** The browser-control integration returned an empty browser/app inventory. No visual manual pass is claimed.
2. **No persistent local/Atlas environment configured.** There is no `services/api/.env`, Docker is unavailable, and no local `mongod` service was running. The architecture was verified with an ephemeral local MongoDB process.
3. **Development watcher interrupted the first attempt.** `npm.cmd run dev` watched accessed dependency files and restarted the API during concurrent Flutter requests. Running the API with `npm.cmd start` was stable. This affects the recommended E2E command, not stored data correctness.
4. **Atlas-specific checks remain unverified.** Cluster reachability, database-user permissions, IP access rules, and Atlas database selection could not be tested without an Atlas URI.
The earlier booking-creation idempotency gap was resolved on 20 September 2026. `POST /bookings` now requires a renter-scoped idempotency key, stores a request fingerprint, returns the original booking for a matching retry, and rejects changed input with `IDEMPOTENCY_CONFLICT`. Flutter reuses one checkout key for booking creation and payment authorization. Sequential and concurrent API tests confirm one booking, one thread, and one Owner notification.

No inconsistent booking IDs, stale persisted statuses, duplicate bookings, duplicate payment authorizations, schema errors, or broken live API routes were found in the verified lifecycle.

## G. Validation

- Live write phase: passed.
- Separate restart/read phase: passed with the same booking ID.
- `npm.cmd test`: 43/43 passed after the Owner operations follow-up.
- `flutter analyze`: no issues found.
- `flutter test`: 59 passed, with the two opt-in live E2E phases skipped during the ordinary offline suite.
- Live renter/Owner web build with `USE_MOCKS=false`: passed.
- Live administrator web build with `USE_MOCKS=false`: passed.

The web compiler continues to report the existing upstream Socket.IO WebAssembly dry-run warning and a Cupertino icon font notice. JavaScript web builds succeed.

## H. Next step

The next product implementation should connect wishlist, comparison, and advanced discovery filters to MongoDB-backed live mode. Separately, configure either a persistent local MongoDB instance or an ignored Atlas `MONGODB_URI`, enable a controllable browser, and repeat the write/restart/read scenario manually from the final screens.
