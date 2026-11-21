# Handover refresh and expired-booking archive

Implemented: 21 November 2026.

## Changes

- Confirmed rental-action responses now update the Owner orders cache immediately, alongside booking-detail caches. After handover submission, **Record handover** becomes **Waiting for renter confirmation**.
- An older in-flight rental-list response cannot replace a newly saved result. A failed follow-up refresh retains the saved handover and records the refresh error, rather than presenting the successful submission as failed.
- Expired booking cards offer **Archive** beside **View details**. Archiving requires confirmation and has a busy state that blocks duplicate taps.
- Choose **Archived** in booking-status filters to find archived records and **Restore** them. Existing search, filters, page size and nearest-valid-page recovery are retained.
- Archiving is independent for each participant. The other participant and administrators retain access. Agreements, payments, messages and rental history remain stored; direct authorized details remain accessible.

## API and storage

- `PATCH /api/v1/bookings/:id/archive`, with JSON `{ "archived": true }` or `{ "archived": false }`, archives/restores for the authenticated participant. Boolean strings are rejected. Foreign users and unrelated administrators cannot archive a participant's record.
- Only a freshly checked `expired` booking can be archived/restored. Other statuses return `409 BOOKING_NOT_EXPIRED`.
- Existing `/bookings/mine` and `/bookings/owner` accept optional `archived=true`. Default queries exclude that participant's archived records; filtering occurs before counting and pagination. Admin lists remain inclusive.
- Optional internal `archivedBy` participant IDs are stored on the booking and excluded from normal projections. Existing records are unarchived without a migration or backfill.
- No financial operations, booking-status changes, notifications, historical cleanup, environment changes, new dependency or model deployment are caused by archiving.

Key implementation files: booking model/repository/service/controller/routes/validation; Flutter booking filters, summary card and RentHub controller. Added focused coverage in `test/booking_archive_handover_test.dart` and extended API `test/ux_enhancement.test.js`.

## Verification

- Full Flutter suite: **1,024 passed, 3 skipped**.
- Focused API suite including archive permissions, repeat requests, restore, filtered totals, later pages, private metadata and unchanged financial records: **12 passed**.
- Flutter analysis: **no issues**.
- Main web, administrator web and Android debug builds: **passed**.
- `git diff --check`: **passed**. Model/report fingerprint comparison: **unchanged**.
- Broad API regression: **865 passed, 3 skipped**, using Node's `--test-force-exit`. The first normal run stopped producing output after its booking tests; only the owned isolated test process was stopped. The retry completed successfully. The lingering normal-run test-process handle remains a runner limitation, not a claimed fix. The final focused API policy check also passed all 12 cases.

Logs: private `.data/testing/ux-enhancement-20261120-223546/`, using the `archive-checked` suffix for final Flutter/build results and `api-archive-force-exit` for the broad API retry. Tests use isolated databases and disabled external integrations, not the shared demonstration database.

## Manual check

1. As Owner, submit a permitted handover and return to **Rental and service orders**. Confirm the card says **Waiting for renter confirmation** and does not offer another handover. Sign in as the renter and confirm receipt; verify the rental starts normally.
2. As either participant, archive an expired booking. Confirm it leaves the main booking list. Select **Archived**, open its history and restore it.
3. Check the other participant's account and admin portal: the same booking must remain visible. Confirm scheduled and active bookings have no Archive action.

Physical-device navigation, real connection interruptions and the two-account walkthrough remain manual checks; automated UI results do not claim those observations.

## Commit message

```text
fix: refresh handover actions and archive expired bookings per participant

- apply confirmed rental results to order caches and reject stale list responses
- preserve successful handover state when follow-up refreshes fail
- add authorized, idempotent archive and restore actions for expired bookings
- filter archived records before pagination without hiding participant history
- add API and Flutter regression coverage and document verification
```
