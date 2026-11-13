# Renter-confirmed handover

Implemented 12 November 2026 for physical rentals. Service bookings retain their
existing start/delivery/completion flow. No live bookings, payments or protected
photos were changed for verification.

## What participants do

1. The Owner approves the paid request. It remains scheduled until the booked day.
2. On the booked day, the Owner records the actual condition, notes and private
   photos, then selects **Send handover for confirmation**. The record is saved
   and immutable; submitting it does not start the rental or capture payment.
3. The renter opens **Handover photos & condition**, directly below the booking
   status, and selects **Review handover**. Photos have a carousel, enlargement,
   condition notes and the Owner submission time in Malaysia time.
4. After physically receiving the item, the renter confirms they received it and
   reviewed the record, then explicitly confirms receipt. Only then does the
   rental start and the existing demo authorization become captured. Confirmation
   does not waive the right to report a problem during the rental.

Both parties keep access to the condition evidence during return inspection,
disputes and completed history. The progress rail no longer contains a second
handover gallery. Old records without acknowledgement metadata say **Renter
confirmation was not recorded**; no historical acceptance or timestamp is inferred.

## Disagreements and deadlines

- **Report an issue** uses the existing dispute workflow. An issue opened while
  receipt is pending prevents acknowledgement and does not automatically capture,
  cancel or release payment. The handover stage remains selected during that case.
- Ordinary cancellation is available before handover submission. After a new
  handover is submitted, both Flutter and Express direct cancellation attempts
  to the issue workflow. No new penalty or automatic refund is introduced.
- A new confirmation must fall within the inclusive Malaysian booked dates.
  When those dates end without confirmation, the saved handover becomes
  **Handover needs review**. Participants and up to 100 active administrators are
  notified once. The booking remains approved and its hold is retained; nothing
  assumes the item was collected or automatically declares it uncollected.
- Bookings with no handover keep their existing uncollected-expiry policy.
  Active/overdue rentals and existing completed records are not reclassified.

## API and recovery

- Existing `POST /api/v1/rentals/:id/handover` still accepts condition, notes and
  evidence. It now creates a version-2 record with a server-generated UUID and
  `receiptStatus=pending`, leaving rental/booking states scheduled/approved.
  An identical retry returns the same record; changed content is rejected.
- New `POST /api/v1/rentals/:id/handover/acknowledge` accepts `handoverId` and is
  restricted to the actual renter. Fresh ownership, states, authorization,
  calendar dates and applicable driving credentials are checked under the shared
  listing lifecycle lock. Client-supplied receipt timestamps/statuses are ignored.
- A durable lifecycle operation records valid acceptance before capture. Its
  preparation phase marks `processing`, reuses the existing capture idempotency
  key, and checks successful capture before applying revision-fenced active
  booking/rental states and `acknowledged` metadata. Notifications are deduplicated
  recoverable follow-ups.
- An interrupted timely acceptance may finish during status recovery after the
  dates end. This resumes an existing acceptance intent; it is not a new late
  acknowledgement. The client retrieves status after an uncertain result before
  enabling an explicit retry, retaining the photos and avoiding blind writes.
- The API advertises `renter-handover-ack-v1`; launcher readiness rejects older
  APIs without this capability. Restart the API and updated app together.
- Existing participant/admin upload protections and booking-location privacy
  remain. There is no new dependency, migration, real payment provider or
  blockchain-contract change. Receipt and condition records remain application
  records; blockchain storage of those photos is not claimed.

## Verification

- Full isolated API suite: **718 passed, 3 existing skips** (721 total), private
  `.data/testing/20261112-130533-3e8c18de`. Coverage includes Owner-only submission,
  real-renter authorization, stale identifiers, immutable evidence, duplicate and
  concurrent acknowledgements, cancellation/dispute races, missing authorization,
  failure before capture and interruption after capture, recovery after the date
  window, late-confirmation refusal, expiry escalation and protected uploads.
- Full Flutter suite: **765 passed, 3 existing skips**, private
  `.data/testing/20261112-130058-2b2a3e59`. Main web, administrator web and Android
  debug builds, all four launcher suites and ten platform-pack tests passed.
  That pack's initial analysis found two new brace-style warnings; both were
  fixed, and final `.data/handover-analysis-final.log` in the Flutter app reports
  **No issues found**. Existing web font/WASM warnings remain non-failing warnings.
- UI regressions cover explicit review/consent, cancelled confirmation, preserved
  evidence and retry, recovered uncertain success, account changes, stale records,
  Owner-only viewing, legacy records, late handover and service exclusion.
  Four private render tests at 360/390/1024/1440 pixels and 130% text passed;
  mobile photos and desktop receipt controls were visually inspected. Focused
  widget interactions also use 150% text. Render images are test fixtures.
- During verification, two fixed-date fixtures were updated to use controlled
  clocks, and the newly added test teardown timeout was corrected so temporary
  MongoDB processes close normally. Earlier stalled runs were interrupted; the
  final full API run above completed normally, including concurrent race cases.
- Model/metrics inventories are unchanged. No AI or Solidity implementation was
  changed, so those suites were not rerun. No live account, booking, payment or
  protected photo was used for this test run.
- P0-16's catalogue and generated plan, testing README and current private guides
  now include renter receipt. Existing case IDs and recorded manual results are
  unchanged. A physical two-account Android walkthrough remains **Not run**.

For the device walkthrough, use a fresh current-day approved physical booking:
submit Owner photos, verify that it still awaits receipt, sign into the renter,
review the photos and confirm receipt, then check both accounts show active.
Use a separate booking for the issue/late-confirmation paths. Do not change the
phone clock or modify shared records to accelerate the deadline test.

## Commit message

```text
feat(rentals): require renter receipt confirmation before starting rentals

- save immutable Owner handover evidence while retaining the demo payment hold
- add renter-only receipt confirmation with recoverable single-capture activation
- route handover disagreements through disputes and block ordinary cancellation
- flag unconfirmed handovers for review after the booked dates end
- show condition photos and receipt status prominently in booking details
- preserve legacy/service flows and require the new API handover capability
- update lifecycle, privacy, UI and launcher tests and P0 guidance
```
