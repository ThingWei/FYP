# Overdue reminders and Owner protection

Implemented 13 November 2026. This applies to physical rentals that actually
started. Scheduled handovers and services retain their existing workflows.

## What happens

The return date includes the entire booked day in Malaysia. The existing
`OVERDUE_GRACE_HOURS` setting is applied after that day. RentHub sends the renter
and Owner an initial overdue email and an in-app notification with the existing
push delivery. After another 24 hours, it sends one follow-up and creates one
in-app/push alert for each active administrator. The administrator rental list
shows **Overdue — needs attention**. This is a request for review, not a finding
of fault and not an automatically created dispute.

Existing overdue rentals are included. If the API restarts after the first
24 hours, only the follow-up stage is queued; missed reminders are not delivered
in a burst. No historical sent dates are invented. Return submission, completion,
cancellation, an opened dispute or a changed extension deadline cancels obsolete
queued deliveries. A final completed/cancelled/expired booking also prevents
delivery when an old linked rental has inconsistent status.

## Using the app

- Owner: open the rental details. **Message renter** opens the existing booking
  conversation. **Report item not returned** opens the existing issue form with
  **Late return** selected. Review the description and evidence and submit it
  yourself. Existing cases show **View case**.
- Renter: **Message Owner**, **Submit return** and the existing eligible extension
  controls remain available. Requesting an extension does not change the deadline;
  only its successful approval can do that.
- Handover condition photos, recorded receipt confirmation and agreement remain
  available under their existing participant access rules. No new private
  location or identity data is sent in notifications or emails.
- Administrator: open **Bookings & Transactions → Rentals → View details**.
  The record shows the overdue date and simple delivery states such as **Sent**,
  **Will retry**, **Delivery not confirmed** or **Email delivery switched off**.
  A sent email means provider acceptance, not proof the recipient read it.

## New-booking restriction

One shared server check runs before creating a new booking, again before its
final persistence, and before authorizing a new unpaid booking payment. It uses
fresh physical-rental end dates, Malaysia calendar rules and the current grace
setting; it does not depend on a scheduler-maintained status flag or a first
page of records. Overdue records in a dispute still count. The response is
`409 OVERDUE_RETURN_REQUIRED` with friendly return/contact guidance in Flutter.
This covers new physical-item and service requests by the affected renter;
services themselves never enter the physical overdue-reminder workflow.

The restriction ends after a recorded return submission or final administrator
resolution. Dismissing a case restores its preceding rental state and does not
clear an unreturned overdue item. Existing durable booking/payment replays still
recover normally. Browsing, messaging, returning, issue reporting and existing
approved bookings remain accessible. The account itself is not suspended.

No late fee, automatic deduction, refund, settlement, compensation promise or
automatic completion is introduced. The existing administrator dispute process
can allocate only funds still held. Demo payments remain simulated; reminders
and a deposit do not guarantee recovery of an item or its full value.

## Email setup and operation

Use the existing private `services/api/.env` sender configuration; no secret or
source setting was changed by this implementation:

```dotenv
EMAIL_MODE=smtp
EMAIL_FROM=RentHub <your-configured-sender>
SMTP_HOST=your-smtp-host
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your-sender-account
SMTP_PASSWORD=your-private-app-password
LIFECYCLE_JOBS_ENABLED=true
```

The existing Resend option is also supported through `EMAIL_MODE=resend`,
`EMAIL_FROM` and `RESEND_API_KEY`. Preserve the existing password-reset secret and
requirements. Do not paste credentials into reports or commit `.env`. Restart
the API/launcher after configuration changes. No new provider or dependency is
installed. The existing **Email notifications** preference is respected; an
opted-out account still receives in-app notifications and eligible push alerts.

The API must be running and able to reach the database/provider. These are
scheduled application jobs, not phone-local alarms or hosting-independent email.
Emails are considered at the next scheduler run, not guaranteed at an exact
second. Queued email with delivery switched off is reconsidered hourly, while
in-app alerts can continue. The standard lifecycle status includes an
`overdueReminders` result; a queue/database failure is shown as unavailable rather
than failing already-completed unrelated lifecycle work.

## Delivery safety and compatibility

The new private `overduedeliveries` collection is derived by Mongoose from
the `OverdueDelivery` model.
It records rental/account references, deadline, stage, channel, attempt count,
lease and safe delivery state. It does not store email bodies, recipient email
addresses, provider exceptions, credentials, IC numbers or private addresses.
A unique event key and atomic leases prevent two laptop schedulers from sending
the same scheduled stage concurrently. Index creation is required; no automatic
historical cleanup or record migration runs.

Known transient rejections retry with exponential backoff, starting at two
minutes and stopping after five actual dispatch attempts. Permanent rejection
does not loop. A timeout after possible submission, missing provider
acknowledgement or an expired email worker lease becomes **Delivery not
confirmed**, with no automatic resend of that attempt. Provider acceptance
followed by a lost database acknowledgement can therefore leave an uncertain
record. This deliberately avoids claiming exactly-once email delivery.

Dispatch is capped at 100 queued attempts and a 20-second admission budget per
job; a single admitted provider call uses the existing bounded transport
timeouts. Unfinished queue work continues on later runs. Overdue candidate and
administrator reads use cursors rather than truncating a fixed first page.
Eligibility is prepared under the existing rental lifecycle lock; network sends
occur after releasing that lock so slow email cannot prevent a return. An email
already accepted/in flight may arrive just after a return or case submission;
it cannot be recalled, and subsequent deliveries stop after rechecking state.

Existing API routes/payloads are retained. Rental responses add only the safe
`overdueInfo` summary (`isOverdue`, `needsAttention`, optional `since`). Admin
record details additionally receive sanitized stage/channel/recipient-role
delivery summaries. Delivery keys, leases, recipient account IDs and provider
errors are excluded. Source data, pricing, models and payment amounts are unchanged.

## Verification and demonstration

Verification results:

- Final isolated API pack `.data/testing/20261113-192751-e2b35cf4`: **744 passed,
  3 existing skips, no failures** (747 total). Covers Malaysia/grace boundaries,
  legacy active/overdue records, 24-hour escalation, concurrent laptop workers,
  missing uniqueness index, preference/provider failures, bounded retry,
  uncertain/malformed acknowledgements, catch-up, stale queues, safe admin
  projections and booking/payment restrictions with replay recovery.
- Full Flutter/build pack `.data/testing/20261113-192022-7c58747f`: **788 passed,
  3 existing skips**. Main web, admin web and Android debug builds passed.
  One new test-only analyzer suggestion was corrected; final separate analysis
  `apps/renthub_flutter/.data/overdue-analysis-final.log` reports **No issues found**.
- After aligning the final fixtures' dates and recorded handover, **28 focused
  UI/render tests passed**: 19 feature tests and 9 render tests. Private log:
  `apps/renthub_flutter/.data/overdue-final-focused.log`. Render coverage includes
  360/390/1024/1440-pixel Owner/renter panels at 150% text and admin delivery
  details. Mobile panels and desktop admin details were visually inspected.
- Test-pack verification `.data/testing/20261113-192617-9845142e`: **10 passed**.
  P1-B03 now includes the reminder/restriction walkthrough without changing the
  82 groups/584 variants or assigning manual passes. P0 recorded results remain
  untouched.
- The full API run exposed an older race assertion requiring a dispute to win
  against completion. The assertion now checks both permitted serialized outcomes:
  a dispute blocks return completion, or completion closes the dispute window
  without creating a case. Both paths verify financial limits and record states.
  No dispute-resolution or payment production rule was changed to satisfy the test.
- An initial interrupted API run was replaced after a streamed eligibility check
  was changed to an indexed database query/lookup. Final runs exit normally.
  Final artifact checksums remain unchanged. Existing web font/WASM notices are
  warnings; no unresolved Auth0 analyzer/test failure was observed in these runs.

No live emails, bookings, financial changes or moderation actions are used by
the isolated test suites. Live inbox delivery, phone push and the presentation
device walkthrough are **not verified by these automated passes**. The existing
private configuration currently enables SMTP and lifecycle jobs; credentials
were not changed or included in test reports. No live reminder job was manually
invoked as a test. A running development watcher may pick up these source changes;
ordinary configured lifecycle automation then follows the new policy.

For your real-device walkthrough:

1. Use dedicated test accounts with email notifications enabled and a started
   physical rental. Confirm the sender configuration and API scheduler are active.
2. After its legitimate Malaysia return deadline/grace, open both accounts:
   check the overdue panel, email and notification; test new-booking rejection.
3. If it remains overdue for 24 hours, inspect the follow-up and admin rental
   alert. Open the Owner report form and verify **Late return** is selected.
4. On a separate case, submit the return and check that new booking eligibility
   returns. Re-run scheduled tasks and ensure no new overdue reminders appear.

Use controlled clocks in automated tests for deadline boundaries; do not change
the phone clock or rewrite live rental dates to speed up the walkthrough. Physical
email inbox/push delivery and real-device checks remain manual observations.

Commit message:

```text
feat(rentals): add overdue reminders and Owner protection

- send tracked overdue emails and 24-hour follow-ups through existing providers
- alert administrators without automatically opening disputes or moving money
- block new bookings and unpaid authorization until overdue returns are handled
- add clear contact, return and issue actions to rental details
- preserve recovery, privacy, services and existing approved booking workflows
- cover deadlines, concurrent workers, delivery failures and responsive layouts
```
