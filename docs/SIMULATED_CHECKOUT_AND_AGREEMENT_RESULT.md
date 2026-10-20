# Simulated checkout and professional agreements

Implemented: 12 October 2026.

## Workflow

1. Renter reviews the current server-owned rental/service agreement in a full document page.
2. Renter explicitly accepts the reviewed version and creates a pending, unpaid request.
3. Checkout retrieves the saved booking and payment history. Opening checkout creates no transaction.
4. Renter chooses Demo Card, Demo FPX or Demo Wallet. A test selection replaces real financial credentials.
5. Explicit success records a simulated authorization. The screen says **Demo payment complete — awaiting Owner approval**.
6. Owner approval is still required. Only the existing approval flow creates the rental/order and attempts the physical-rental supporting record.

Pending physical requests remain soft holds. Payment does not reserve dates. Overlapping pending requests remain permitted; existing approved/active/disputed availability and competing-request invalidation remain in force.

Canceling or dismissing the demo selection sends no payment write. Decline records a failed transaction and leaves the request pending/unpaid. **Continue payment** appears in renter Bookings for current pending/unpaid requests. Leaving checkout also retains the request until existing expiry processing.

## Checkout and access

- Shared blue/white cards with a maximum desktop width, scrolling mobile content and itemized saved MYR rental/service amount, deposit, selected damage waiver, applicable platform fee and total.
- Service checkout omits physical deposit/waiver rows.
- Any difference from the earlier estimate requires acknowledgment. A changed saved total discovered immediately before payment also requires review, including resumed checkout with no prior estimate.
- No card-number, real bank, wallet-password or OTP field.
- Server is authoritative for charges; client payment requests contain no amount.
- Page uses the existing session and renter role. API verifies booking ownership.
- Logout, account changes or active-role changes remove checkout. An already-open demo dialog also hides its test details/actions when the session changes.
- API 401/403/404 blocks sensitive checkout content. No automatic Auth0/browser launch.
- Check status on open and immediately before payment. Terminal, past-deadline, already-paid or malformed-charge requests cannot start another payment.
- Busy controls prevent duplicate dialog/payment actions.
- Lost/malformed write responses trigger read-only booking/payment reconciliation. Unresolved status disables payment. Explicit retry of an uncertain attempt retains its key/method/outcome; a known decline gets a new attempt key.
- A recorded authorization with a missing booking update can be explicitly reconciled using its original attempt key, without a second transaction.

## API compatibility and persistence

Existing booking, payment, approval and cancellation endpoints retain their paths/payloads.

New authenticated endpoints:

| Endpoint | Purpose |
| --- | --- |
| GET /api/v1/bookings/agreement-terms?listingType=physical | Current rental wording/version/hash |
| GET /api/v1/bookings/agreement-terms?listingType=service | Current service wording/version/hash |
| GET /api/v1/bookings/:id/agreement | Participant/admin document, saved charges/history and filtered locations |

Payment authorization accepts optional `simulationOutcome: success | declined`; omitted outcome remains success for existing callers. Cancel is local and does not send an authorization request.

Idempotency binds a recorded attempt to booking, payer, method and outcome. Replays return the durable result; changed parameters conflict. This is rechecked after concurrent duplicate-key collisions, preventing another booking's payment from being returned.

A conditional 60-second booking lease serializes new authorizations. Lease fields are excluded from responses. New successful authorization records use a unique sparse `authorizationSlot` indexed by booking; failed attempts do not occupy it. Durable authorization records can repair interrupted booking updates. Expired leases can be reclaimed. No multi-document transactions are required.

The standard Mongoose model/index initialization creates the added sparse unique index. No migration, record cleanup or database backfill was executed; old records omit the new slot. Retain normal index creation in deployments. This is a simulator, not a real payment gateway or a general production financial ledger.

Owner approval requires authorization and a request that has not passed its expiry deadline, even before lifecycle processing runs. Normal rejection voids an existing demo hold. Existing cancellation/expiry mechanisms remain.

The legacy controller compatibility helper still serves older test/integration callers; the live booking form exclusively uses separate creation and checkout actions.

## Agreement presentation and historical accuracy

Shared, scrollable full-page agreement is available from renter/Owner booking cards before and after approval, including services. It shows:

- reference, actual booking status, saved item/service title and dates (scheduled times for services);
- renter and Owner name snapshots;
- fulfilment/venue and privacy-filtered available location snapshots;
- saved charge breakdown;
- server-owned responsibilities;
- recorded renter acceptance and Owner decision timestamps, or an explicit unavailable/not-recorded message.

Terms registry: `services/api/src/modules/booking/agreementTerms.js`.

- New live physical bookings use `renthub-rental-v2`.
- New live service bookings use `renthub-service-v2`.
- Legacy `renthub-booking-v1` remains exactly available with its original hash for compatibility/history.
- Physical terms cover collection, condition, care, return, extensions, deposit/optional protection and supporting-record limits.
- Service terms cover venue, service delivery and completion, without physical return/deposit duties.
- Both cover simulated payment, pending requests, approval, eligible changes/cancellation and disputes.
- Booking stores accepted version, SHA-256 terms hash and acceptance time.
- Do not edit a published version: register a new version instead. Missing/unknown or hash-mismatched historical wording is not replaced by today's wording.
- New bookings save the actual Owner display name at creation. Legacy missing names stay unavailable; there is no historical-profile substitution or bulk migration.

Existing booking location filtering is reused. Pending/rejected/cancelled/expired counterparts do not receive exact locations. Qualifying approved/active/completed/disputed participants retain existing unlock rules, and Owner/admin access is preserved. Public coordinates and maps logic are unchanged.

## Supporting record, not a booking guarantee

Physical display states:

- Before approval: **Record available after Owner approval**.
- Confirmed existing integration result: **Rental record saved**.
- Failed/disabled integration after approval: **Supporting record unavailable**.

Approval stays separate from record status. Ordinary renter/Owner pages do not display transaction hashes, contract addresses, wallet identifiers, raw errors or network internals. Existing administrator/development diagnostics remain available.

Copy explains: **RentHub records rental amounts and status changes to support later review.**

The current integration is the local Ganache demonstration network using backend-managed test accounts and test funds. It records amounts and supported lifecycle changes, not the complete agreement text/hash or user-controlled wallet signatures. There is no claim of document authenticity, legal certification, insurance guarantee or production payment protection. Service agreements remain ordinary RentHub booking records without blockchain coverage.

No blockchain contract was rewritten, real payment provider added, PDF export added, financial credentials collected, Auth0 configuration changed or production dependency installed.

## Verification

All tests use local fake APIs or isolated temporary MongoDB databases; no live personal bookings were edited. Blockchain display tests inject stored confirmed/failed/unavailable states; they do not claim a new live Ganache transaction was tested.

| Check | Result |
| --- | --- |
| New checkout/agreement API suite | 13 passed |
| Focused API suites: payment, booking/rental, precise locations, checkout/agreement | 43 passed |
| New Flutter checkout/agreement adapter/widget suite | 27 passed |
| Focused Flutter suites: booking/payment contracts, precise locations, input-validation widgets, live account contracts, checkout/agreement | 68 passed |
| flutter analyze lib | Passed |
| Full flutter analyze | Two existing Auth0 test errors; see below |
| flutter build web | Passed |
| flutter build apk --debug | Passed |

New regressions include creation without authorization, all three methods, success/decline/cancel, unpaid resumption, deadline/already-paid controls, malformed charges, charge-change acknowledgment, duplicate/concurrent authorizations, cross-booking key collision, interrupted-write recovery, session revocation including open dialog, participant access, legacy/missing terms, names/charges snapshots, approval history, record states and services.

Layout widgets were tested at 360, 390 and 1024 logical pixels with 1.3x text scaling and no layout exceptions. Existing location-privacy tests remain passing.

Existing unrelated full-analysis failures:

- `test/auth0_persistence_test.dart:41`: unsupported `latestLinkProvider` named parameter.
- `test/auth0_persistence_test.dart:43`: unsupported `mobileLinkPollInterval` named parameter.

No Auth0 code/tests were modified to conceal these failures. Full-project analysis/test cleanliness is not claimed.

Build warnings remain about existing socket_io_common WebAssembly compatibility, missing Cupertino icon font and firebase_core/shared_preferences_android Kotlin Gradle migration. Standard JavaScript web and Android debug builds succeeded. These builds verify compilation, not production deployment configuration.

## Try it

Restart the API through the normal RentHub launcher and rebuild/restart Flutter so both use the new registry/routes.

1. Sign in as a verified renter and choose an available physical listing.
2. Review the full agreement, accept it and continue to checkout.
3. Cancel a demo method: verify pending/unpaid and resume using Bookings → Continue payment.
4. Choose Demo FPX → Simulate decline: verify still unpaid and Owner approval unavailable.
5. Retry with Demo Wallet → Complete demo payment: verify awaiting Owner approval, not confirmed.
6. Sign in as the Owner, open View agreement and approve the paid request.
7. Open the renter agreement again: verify recorded approval, permitted location details and supporting-record state.
8. Repeat with an online service: inspect venue/scheduled time and service responsibilities without physical-item/chain claims.
9. Log out while checkout/demo selection is open: verify sensitive content/actions disappear.
10. With the existing Ganache launcher/configuration running, verify a real local demo booking's confirmed record separately. Disabled/failed integration must not turn an approved booking into a failed booking.

Physical Android/device walkthrough and an actual live Ganache booking remain recommended demonstration checks; this task verified automated UI behavior and compilation, not a hands-on device session.

## Commit message

```text
feat(bookings): add simulated checkout and versioned full-page agreements

- separate pending request creation from explicit demo payment authorization
- add Demo Card, FPX and Wallet outcomes with unpaid booking resumption
- enforce session/ownership access and server-controlled charge review
- reconcile uncertain outcomes and protect concurrent/idempotent attempts
- reject approval after expiry and void demo holds on Owner rejection
- serve versioned rental/service terms with saved participant and acceptance history
- present privacy-filtered agreements and plain-language supporting-record states
- add checkout, agreement, concurrency and location-privacy regressions
- document simulation limitations, verification and remaining Auth0 test errors
```

## Lifecycle follow-up — 20 October 2026

See [Auth0/source/lifecycle handoff](AUTH0_SOURCES_AND_LIFECYCLE_RESULT.md).
Confirmed overlapping-approval and concurrent-refund bugs were reproduced and
fixed. Listing-scoped leases now coordinate approval/cancellation and rental
transitions without turning pending requests into hard holds. Refunds enforce
cent-based balances and changed-input idempotency conflicts, reconcile interrupted
booking-status writes and deduplicate notifications. Extensions respect unresolved
disputed dates and cannot be approved after return submission.

Full API suite: 389 passed/3 skipped; Flutter: 407 passed/3 skipped; analysis and
Web/Android debug builds pass. The previously reported Auth0 analyzer errors are
fixed. Payments remain simulated. Those counts describe the earlier review;
the financial gaps recorded then are superseded by the follow-up below. Claim
payouts deliberately remain unfunded/pending rather than inventing a fund.

## Subsequent financial lifecycle update — 20 October 2026

Paid extra days, held-balance dispute allocations, unfunded-claim status, refund
reconciliation and recorded-intent crash recovery are documented in
`PAID_EXTENSIONS_AND_SETTLEMENT_RECOVERY_RESULT.md`. Original agreement/pricing
snapshots are retained; approved extension charges are displayed separately.

