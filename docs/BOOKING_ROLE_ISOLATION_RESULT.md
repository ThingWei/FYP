# Renter and Owner booking isolation

Implemented 15 October 2026.

Follow-up: [Duplicate pending booking protection](DUPLICATE_PENDING_BOOKING_RESULT.md)
blocks same-renter overlapping physical-item requests without making pending dates
hard reservations.

## Cause and correction

The live Flutter controller previously assigned renter `/bookings/mine` and Owner
`/bookings/owner` responses to the same list, likewise for rentals. The Owner shell
could render that list while its own load was pending or failed. Focused notification
reads also inserted participant records into the shared list. The Owner request
screen did not check ownership before rendering decision buttons.

The Express decision endpoint already rejected a caller who was not the booking's
actual Owner. Visible controls were therefore not evidence of a successful server
authorization bypass.

The controller now has separate renter, Owner and administrator booking/rental
workspaces, each with loading, successful-load and error state. Live role screens
and Owner dashboard counts consume their own ownership-filtered collections.
Owner records must belong to the signed-in account and must not also name that
account as the renter. Missing participant IDs cannot grant Owner controls.

The legacy `bookings`/`rentals` getters are participant lookups for focused
notification navigation, not role feeds. Administrator screens read the separate
administrator workspace. Booking reads/writes, payment reconciliation, cancellation,
dispute status changes and rental refreshes update the appropriate collections.

## Switching roles and accounts

- Role changes preserve that account's role-specific cached records. Initial loads
  show loading/recovery states; failed booking refreshes retain the correct role's
  records with a safe retry message rather than substituting the other role's data.
- Full-workspace request generations discard superseded loads, including delayed
  responses after switching roles and competing requests for the same workspace.
- Account generations guard booking/rental mutations and focused notification
  hydration. Logging out and returning to the same account does not revive an old
  response from the previous session.
- Mobile and administrator entry points bind the live controller to authentication
  through the existing Provider framework. Logout or account replacement clears
  all three booking/rental workspaces and resets their states.
- Notification destinations still use actual record participation. A renter record
  opens renter details without entering Owner requests or changing roles.

## Approval and compatibility

The controller refuses non-owned booking decisions and Owner rental actions before
issuing the write. Express remains authoritative: the decision endpoint checks the
actual Owner and additionally refuses malformed historical self-bookings. The API
continues to return a non-disclosing 404 for such decisions.

No endpoint, payload, payment amount, agreement requirement, booking expiry or
pending-soft-hold policy changed. Payment authorization remains necessary for
approval, and only the actual Owner can decide a legitimate request. New self-booking
creation remains prohibited. No migration, new dependency or Auth0 behavior change.

## Verification

| Check | Result |
| --- | --- |
| New booking role-isolation Flutter tests | 12 passed |
| Full non-live Flutter suite (`flutter test --no-pub --exclude-tags live`) | 372 passed, 3 skipped |
| Focused booking, checkout and notification API suites | 44 passed |
| Full API suite against ephemeral MongoDB | 350 passed, 3 skipped |
| Flutter source and changed-test analysis | No issues |
| Full Flutter analysis | Two existing Auth0 test errors, described below |
| Flutter web build | Passed |

Coverage includes dual-role outgoing versus incoming records, separate rentals,
rapid role switches, competing loads, failed initial/refresh requests, account
replacement, late focused responses, logout/relogin, actual-ownership notification
hydration, local no-write guards, cancellation/payment read updates, admin separation,
malformed self-records and Owner/renter cards at 360/390 pixels with 1.4x text.
Existing booking/payment test fixtures now supply actual participant IDs and a
signed-in renter. Workspace-error fixtures use the corresponding role's error state;
the preloaded administrator fixture explicitly marks its workspace loaded.

API regressions verify a dual-role renter's request appears in renter bookings but
not Owner requests; approval/rejection attempts fail without changing payment/status
or creating a rental; the real Owner can still approve. Self-booking creation and
decisions on malformed legacy self-records are rejected.

API tests used process-local `NODE_ENV=test`, `AUTH_MODE=mock`, `STORAGE_MODE=local`,
`FCM_MODE=disabled`, `BLOCKCHAIN_MODE=disabled` and `EMAIL_MODE=disabled` with
mongodb-memory-server. No live database was changed. The initial unconfigured API
run picked up development authentication and returned 401; the isolated rerun and
full suite above passed.

Full analysis still reports unrelated undefined constructor arguments
`latestLinkProvider` and `mobileLinkPollInterval` in
`test/auth0_persistence_test.dart:41/43`; these were not modified. The successful
web build reports existing socket_io_common WebAssembly dry-run and Cupertino-font
warnings. No Android/device run is claimed for this fix.

## Manual device verification

1. Sign in to a dual-role account and rent another Owner's item; complete demo payment.
2. Switch to Owner. That outgoing rental must not appear in Requests, pending counts
   or Owner rental actions. Genuine requests for your listings should remain visible.
3. Switch back to renter and confirm the outgoing booking/payment status is retained.
4. Open its notification while Owner is selected: it must open renter details with
   no Approve/Reject controls and no automatic role switch.
5. Repeat with slow/unavailable connectivity, then sign out and sign in to another
   account. No old account's booking/rental records should appear.

## Commit message

```text
fix(bookings): isolate renter and Owner booking state

- separate renter, Owner and admin booking/rental workspaces
- filter Owner requests, counts and actions by actual listing ownership
- discard superseded workspace and previous-account booking responses
- clear booking caches on logout and account changes
- partition focused notification reads without switching roles
- preserve role-specific cached results and offer safe load retries
- guard foreign decisions locally and reject legacy self-approval in the API
- add role-switch, notification, layout and dual-role API regressions
- document verification results and existing Auth0 analysis limitations
```
