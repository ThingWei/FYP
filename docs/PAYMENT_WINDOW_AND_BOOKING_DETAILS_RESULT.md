# Ten-minute checkout and compact booking details

Implemented on 7 November 2026 in the live RentHub app and Express API.

Later full-platform follow-up: the formerly excluded paid-pending test was
reconciled with the approved independent deadlines; the unfiltered API suite now
passes **677 tests with 3 opt-in skips**. See [the testing result](testing/PLATFORM_TEST_EXECUTION_RESULT.md).
The earlier exclusion/results below describe their original run.

## What users see

- Before payment: **Awaiting payment**, a countdown and **Continue payment**.
  The rental progress steps are hidden for both participants, including unpaid
  records that have expired. This is a saved checkout, not a paid request awaiting
  the Owner's decision.
- After successful demo payment: **Awaiting Owner approval** and the existing
  rental/service progress steps. Payment does not approve the booking or reserve
  pending physical-item dates.
- At the deadline: **Expired**, no payment action, and an explanation that a new
  checkout is needed. Closing checkout, changing screens or reopening the app does
  not restart the timer.
- Bookings and Owner Requests use compact summary cards with status first, item,
  dates and total. **View details** opens a dedicated, scrollable page containing
  the existing agreement, location, progress and authorized actions. Owner order
  cards keep their saved item title and link to the same details.
- Owner Home's requests-needing-a-decision count includes paid pending requests
  only. Unpaid checkouts remain visible with their actual payment state.

## Deadline and payment enforcement

New bookings save `paymentDueAt` ten minutes after checkout creation. The existing
`expiresAt` Owner-response deadline is preserved separately; successful payment
does not extend it. An earlier existing Owner deadline still takes precedence.
The internal `pending` status and endpoint paths remain compatible; the app derives
the readable payment/approval labels without introducing a replacement lifecycle.

Older unpaid bookings without `paymentDueAt` derive it from their original
creation time, capped by an earlier existing expiry. No backfill is run and opening
an old checkout never grants another ten minutes. An old unpaid checkout already
beyond its deadline expires when checked. Approved/active rentals are unaffected
by the unpaid-payment timer.

Payment authorization checks the current deadline when taking the attempt lease,
after the demo gateway returns and when linking a successful authorization. A late
result cannot become a payable/authorized booking. Existing concurrent-attempt and
idempotency protections remain. If a process stopped after durably saving a timely
authorization but before linking it to the booking, expiry recovers that success
while the Owner deadline is still current. Terminal requests are never revived;
expired authorization holds are released instead.

Booking responses include a server timestamp. Flutter uses the server/device clock
offset for the countdown, rechecks on foreground return and performs a read-only
refresh at zero. The API remains authoritative; clock display is not a payment
authorization. A failed refresh does not extend the window or blindly retry a
payment write.

## Notifications and scheduled checks

The existing notification-centre/Firebase delivery pipeline is reused for:

1. Checkout creation: **Finish your payment**, with the deadline in Malaysia time.
2. The final two minutes: one **Your payment window is ending** reminder.
3. Expiry: **Payment window expired**. Paid requests use the existing Owner-expiry
   notification and authorization-release rules instead.

Notification keys prevent duplicate reminders/notices. Targets identify the
booking and use the existing protected notification navigation.

With `LIFECYCLE_JOBS_ENABLED=true`, a separate 30-second payment check runs while
the API is online. It avoids rerunning unrelated report/rental jobs at this faster
interval. Deadline enforcement on booking reads and payment writes remains
immediate; persistence and expiry notices from the background check can follow by
up to approximately 30 seconds under normal conditions. Database/service outages
can delay housekeeping. Notifications are not guaranteed to arrive at the exact
second of expiry.

In-app notices use the existing account preferences. Android push also requires
working Firebase credentials, device registration, notification permission and
network access. If scheduled jobs are switched off, background reminders do not
run; a booking read/payment attempt still enforces expiry. The API must be running
for server-side jobs and push delivery.

## Verification

- Focused API suites: **97 passed**, covering booking/payment lifecycles, checkout
  agreements, location privacy, notification targets and booking filters. The
  known conflicting legacy paid-pending duplicate test was excluded explicitly.
- Five new API deadline tests cover fixed creation deadlines, unchanged reopening,
  notification deduplication, exact expiry boundaries, paid-state preservation,
  legacy creation-time fallback, late gateway results and interrupted-write
  recovery. Owner counts distinguish unpaid checkouts from paid requests.
- Flutter tests cover server clock offset, countdown zero/reopening, one expiry
  callback, hidden unpaid steps, paid steps, persisted unpaid expiry and protected
  detail navigation. Layout assertions cover 360/390/1024-pixel widths and larger
  text. Owner dashboard/order tests cover saved identity and paid-only decisions.
- Full Flutter tests: **633 passed, 3 existing skips**. Analysis: **no issues**.
- Web build: **passed**. Existing `socket_io_common` WebAssembly dry-run and
  Cupertino font warnings remain; the normal JavaScript web build succeeds.
- Android debug APK: **passed**. Existing future Kotlin Gradle Plugin migration
  warnings for `firebase_core` and `shared_preferences_android` remain.
- `git diff --check`: **passed**. No files were staged or committed.

The excluded API test is `legacy paid pending requests block duplicates after
their payment timer, ahead of newer unpaid duplicates`. Its fixture moves the
Owner-response `expiresAt` into the past but expects that paid request to remain
pending. The existing Owner-expiry policy expires/releases it. This work preserves
that policy and does not claim the unfiltered API suite is green.

An existing checkout recovery assertion was updated to expect the actual expired
and voided state after expiry reconciles a persisted authorization. Payment/refund
test fixtures now reach the physical rental start day before handover, respecting
the earlier start-day guard rather than bypassing it in application code.

## Try it

Restart through the normal launcher and rebuild/open the current app. Services-only
mode does not install UI changes.

1. Start checkout with a prepared demo account; leave it unpaid. Check **Awaiting
   payment**, countdown and hidden steps in Bookings and its detail page.
2. Leave and reopen checkout. The deadline must remain the original deadline.
3. Leave another checkout unpaid through expiry. Check the reminder, expiry notice
   and disabled payment action. Starting again creates a new checkout, not an
   extension of the expired record.
4. Successfully pay a separate demo checkout before its deadline. Check the paid
   approval state and progress steps; the actual Owner must still approve it.
5. Check notification delivery on the Android device with permission enabled.

No real-device walkthrough or background push-delivery timing was performed during
this change. Automated layout checks/builds do not replace those final checks.
No live records were created or modified for testing; API tests use temporary
databases. Existing uncommitted work is preserved.

## Commit message

```text
feat(bookings): add timed checkout and compact booking details

- enforce a fixed ten-minute unpaid payment window without reset on reopening
- add payment reminders and expiry notices through existing notifications
- reconcile interrupted authorizations and reject late payment completion
- separate unpaid checkout labels from paid Owner-approval requests
- hide rental steps until payment and count only paid Owner decisions
- replace oversized lists with compact cards and protected detail pages
- test deadline boundaries, recovery, role isolation and responsive layouts
```
