# Disputes close at final completion

Implemented on 7 November 2026 for the live Renter and Owner flows.

Later full-platform follow-up: the formerly excluded paid-pending test was
reconciled with the independent payment/Owner deadlines. The unfiltered API suite
now passes **677 tests with 3 opt-in skips**. The older exclusion described below
is historical. See [the consolidated testing result](testing/PLATFORM_TEST_EXECUTION_RESULT.md).

## User-facing rule

A new dispute must be raised before final completion:

- Physical item: before the Owner confirms the returned item.
- Service: before the Renter confirms service completion.

The booked end date and a successful demo payment do not close the window.
Active/overdue rentals, returns awaiting inspection and services awaiting completion
confirmation retain their existing issue-reporting access. There is no additional
grace period after completion.

Completed bookings no longer offer **Raise Dispute** to either participant.
Existing cases retain **View case** navigation and their authorized history access;
closed cases remain read-only under the existing rules. Reviews and ratings remain
available. Completion confirmations now explain that issues must be reported first.

## Enforcement

`POST /api/v1/disputes` retains its existing payload and authorization. It now
returns HTTP **409** with code **DISPUTE_WINDOW_CLOSED** when either the rental or
its linked booking is completed. The user message is:

> This rental is complete, so a new dispute can no longer be opened.

The service rereads both records inside the existing listing lifecycle lock after
recovering any previously interrupted operation. The cutoff runs before new case
creation, blockchain calls, notifications or financial/status changes. Return
confirmation, service completion and dispute creation use the same lock, so a
concurrent request cannot reopen a completed transaction or settle a rental after
a dispute wins the transition. Unrelated users still receive the existing access
failure rather than private booking details.

Flutter shares an eligibility rule between booking actions, Owner order cards,
the controller and the dispute page. A new form refreshes its rental and booking
before submission is enabled. Read failures offer **Try again** and keep submission
disabled. Superseded account sessions cannot accept the eligibility refresh.

An updated completion state disables an open form. If completion occurs remotely
after the refresh, the API remains authoritative: its rejection closes the form's
submission action and displays the friendly message. Typed fields and already
uploaded evidence remain in the draft; they are not cleared or automatically sent
again. Existing-case viewing does not depend on new-case eligibility and does not
create another case. An existing case must still be loaded through the normal
case/notification/record navigation; this change does not prefetch every historical
case into all booking-list pages.

The issue-category dropdown was also constrained to its available width to avoid
overflow on small screens with larger text.

## Verification

- Dispute API suite: **17 passed**, including actual physical-return/service
  completion, both participants, outsider access, one completed linked record,
  unchanged payments/notifications/lifecycle records after rejection, and no
  blockchain dispute call on blocked attempts.
- Concurrent completion/dispute tests verify that only the valid transition wins.
  Calendar-expired but unfinished active/overdue/inspection/service records remain
  disputable. Existing resolved cases remain readable to participants/admin and
  hidden from unrelated users.
- Relevant API regression suites: **112 passed**, covering disputes, bookings,
  rentals, payments, lifecycle jobs, agreements, location privacy and notification
  navigation. The existing conflicting paid-pending duplicate test was explicitly
  excluded, as documented below.
- New Flutter cutoff suite: **11 passed**. Tests cover cached completion, no-write
  controller guards, linked-booking completion, delayed account changes, mandatory
  fresh checks, retry, retained draft/evidence after rejection, live completion
  updates, and Renter/Owner historical-case navigation with reviews retained.
- Layout checks cover **360, 390 and 1024 logical pixels** with **1.5× text**.
- Full Flutter suite: **644 passed, 3 existing skips**.
- Flutter analysis: **no issues**.
- Web build: **passed**. Existing `socket_io_common` WebAssembly dry-run and
  Cupertino font warnings remain; the normal JavaScript build succeeds.
- Android debug APK: **passed**. Existing future Kotlin Gradle Plugin migration
  warnings for `firebase_core` and `shared_preferences_android` remain.
- `git diff --check`: **passed**. No files were staged or committed.

The excluded existing API test is `legacy paid pending requests block duplicates
after their payment timer, ahead of newer unpaid duplicates`. It moves the
Owner-response deadline into the past while expecting the request to stay pending;
the existing expiry policy expires/releases that request. This task preserves that
policy and does not claim that the unfiltered API suite passes.

Tests use temporary databases. No live records, settlements, historical disputes
or approved identities were changed. No migration, new dependency, Auth0 change or
new payment/blockchain behavior was introduced. Existing uncommitted work remains.

## Device check

Restart the normal launcher and rebuild/open the current app; services-only mode
does not install Flutter changes.

1. Open an active physical rental or service and check that **Raise Dispute** is
   still available before final completion.
2. Open the completion confirmation and check its warning. Cancel the confirmation
   if you still need to report an issue.
3. After a prepared demo transaction is completed, check both accounts: review
   actions remain, but **Raise Dispute** is absent.
4. Open an earlier existing case through **View case**, case history or its
   notification. Check that its recorded history remains available.
5. For a stale-form check, open the form on one device and complete the transaction
   from the other participant's device. Attempt submission: it must be rejected
   without clearing the draft or creating a new case.

These real-device steps have not been operated during this change. Automated
tests/builds do not replace the final two-device walkthrough.

## Commit message

```text
fix(disputes): prevent new cases after rental completion

- reject completed rentals or bookings inside the shared lifecycle lock
- hide new-dispute actions for completed Renter and Owner records
- retain existing case history and review actions
- refresh form eligibility and preserve drafts on stale-state rejection
- explain the cutoff before confirming returns or service completion
- test completion races, access rules, side effects and responsive layouts
```
