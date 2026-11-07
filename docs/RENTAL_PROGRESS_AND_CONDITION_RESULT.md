# Rental progress, condition photos and clearer dispute handling

Implemented on 7 November 2026 for the live Renter and Owner flows. Previous
uncommitted Atlas/launcher work is preserved. No live bookings or payments were
created to test this change.

Follow-up: new disputes now close at final return/service completion for both
participants. Existing case history remains accessible; see
[Dispute completion cutoff](DISPUTE_COMPLETION_CUTOFF_RESULT.md) for the rule,
stale-form protection and current verification results.

## What happens after approval?

For a physical item booked for a future day:

1. The renter reviews the agreement, creates a request and completes demo payment.
2. The Owner approves the booked dates. The rental is **scheduled**, not active.
3. Both parties wait until the booked day and arrange collection or Owner delivery.
   The Owner prepares the item. Approval and the passing of time alone never
   confirm that the item was handed over.
4. On the booked start day, the Owner records the actual condition, notes and
   photos, then explicitly confirms handover when giving the item to the renter.
   This activates the rental and captures the existing demo payment.
5. The renter uses the item and submits a return record with actual condition,
   notes and photos when returning it.
6. The Owner inspects the returned item and confirms return through the existing
   return/settlement workflow, or either party reports a problem for review.

The progress panel appears on renter booking cards, Owner requests and Owner
rental orders. It shows the next action and an expandable lifecycle timeline.
Pending/unpaid, approved/scheduled, active, overdue, return-submitted, completed,
cancelled/rejected/expired and disputed states remain distinct. An old or missing
condition record is explicitly missing; no historical photos or timestamps are
invented. When a linked rental is unavailable, the booking state is used
conservatively. Services retain service-specific progress and no item-condition
or return-photo sections.

This is **recorded rental progress**, not a live parcel-tracking integration.
Collection/delivery events come from existing rental actions. There are no
invented courier dispatch, transit or proof-of-receipt events. Owner delivery fees,
booking-location privacy, approval rules and pending soft holds are unchanged.

## Owner handover and renter return records

The prior handover action uploaded a file then automatically submitted
`Excellent` and a generic note. The prior renter return action automatically
submitted `Good`. Both now open a dedicated condition form:

- No condition is preselected. The submitting party chooses the actual condition.
- Notes describe scratches, damage or missing accessories; no generic condition
  claims are injected.
- At least one distinct photo is required, with up to ten photos. Several angles,
  accessories and close-ups are encouraged; the app does not pretend that one
  photo proves the whole item is undamaged.
- The existing camera/batch selection and preview/retry components are reused.
  Camera capture remains device-dependent; choosing files remains available.
- Photos upload with their private handover/return purpose, never as public
  listing photos. The confirmation explains that the record will be shared with
  the other party and the rental state will change.
- The party confirms that the photos and notes reflect their observation. The
  handover action cannot be submitted before the booked start day in Malaysia;
  the API independently enforces this, including direct requests.
- Vehicle-licence checks, ownership and lifecycle locking remain authoritative.
- Failed submissions retain the current form's notes/photos. Uncertain network
  outcomes require checking the latest server status before retrying the write.
- Uploaded preview bytes retain their existing retry behavior. Removing a photo
  from an unfinished form removes its selection, not a committed record.

The API checks upload ownership/purpose and image content type. Empty photo sets,
PDFs and repeated references are rejected. Once handover is recorded, the existing
state guard prevents replacing it. The existing upload-in-use protection prevents
deleting photos attached to handover/return records. The renter, Owner and
administrators retain protected access; unrelated users do not.

Recorded times are server event times, shown in Malaysia time. They are not
verified camera capture times. Gallery photos, altered images and off-platform
behavior cannot be proved genuine by this feature. Photos support fair review
for both parties; they do not automatically identify who caused damage or prevent
all false claims. No new renter receipt-signature, liveness, insurer or courier
integration is implied. Condition-form drafts remain local to the open page;
there is no new server-side draft storage or retroactive evidence for old rentals.

## Dispute experience

The live case page now explains the process before submission and while tracking:

**Report the issue -> Both parties respond -> Administrator reviews -> Decision
and payment update.**

Known case states use plain labels, including waiting for a response, more
information needed and administrator reviewing. The administrator's note is
explicitly identified. The page shows report attachments, responses with readable
Malaysia timestamps and viewable attachments, plus expandable saved handover and
return records for physical rentals. Services omit those physical sections.

The response form uses its own validation key and a normal text keyboard. Invalid
responses remain open; relevant loading buttons are disabled during operations.
The claim action is now **Request damage-waiver review**. Existing coverage,
funding and administrator decision rules are unchanged.

Outcome copy identifies demonstration payment allocations. Ordinary participants
see a plain supporting-record status, never contract addresses, transaction
hashes, blockchain references or raw infrastructure diagnostics. The decision
remains visible when its supporting record is unavailable. Administrative
blockchain diagnostics and the existing agreement/network disclosures remain
available in their existing places. A copyable business case reference is retained.

## Verification

- Full Flutter suite: **615 passed, 3 existing optional skips**.
- Flutter analysis: **no issues**.
- New focused suite: **12 tests**, covering scheduled waiting without automatic
  activation, Malaysia-midnight boundaries, lifecycle distinctions, typed condition
  parsing, timestamps, missing legacy evidence, service separation, dispute copy,
  invalid form/no write, retained notes, future-date disablement and account access.
- Layouts: widget checks at **360, 390 and 1024 pixels**, including 1.5x text for
  progress views; existing role-isolation tests check narrow renter/Owner cards.
- Relevant API booking/dispute/upload run: **48 passed** with one separately
  recorded existing failing test explicitly excluded by name. New API regressions
  cover future handover/no capture, reached start day, image requirements,
  ownership/purpose, duplicate references, actual condition preservation,
  participant-only photo access, committed-photo deletion protection and repeat
  handover rejection.
- Unfiltered booking/dispute run: **41 passed, 1 failed**. Existing test
  `legacy paid pending requests block duplicates after their payment timer,
  ahead of newer unpaid duplicates` expects 409 but receives 201. Existing
  pending-expiry code expires paid pending requests when `expiresAt` has elapsed;
  this expiry/duplicate policy inconsistency is outside this presentation/condition
  change and was not silently repaired or hidden. No booking-expiry policy changed.
- The first restricted API test run could not start its disposable MongoDB
  process. Rerunning with normal local process access resolved that environment
  failure; tests use temporary databases, not Atlas.
- Web build: **passed** (`build/web`). Existing third-party WebAssembly dry-run
  warnings from `socket_io_common` and a Cupertino icon-font warning remain;
  the normal web build succeeds. No WebAssembly support is claimed.
- Android debug build: **passed** (`build/app/outputs/flutter-apk/app-debug.apk`).
  Existing future Kotlin Gradle Plugin migration warnings for `firebase_core` and
  `shared_preferences_android` remain. No plugin upgrades were made in this task.
- `git diff --check`: **passed**. Existing launcher/Atlas work remains uncommitted
  and was not reset, staged or included in a commit.
- No AI/model changes or dependencies, schema migrations, historical rewrites or
  production data mutations were required.

## Demonstration checklist

1. Create a demo request for future dates and complete demo payment with a renter.
2. Approve with the actual Owner. Show the scheduled date and the next-step text;
   expand the progress panel. It must not say the rental is already active.
3. Open **Prepare handover**. Before the start day, final confirmation is disabled.
4. For a booking whose start day has arrived, open **Record handover**, choose the
   actual condition, enter existing marks, add camera/gallery photos and review
   them. Confirm only at actual handover.
5. As the renter, expand the record and inspect the Owner's photos. Submit return
   with your own condition/photos, then inspect and confirm using the Owner account.
6. Use a separate staged case to demonstrate reporting an issue, both parties'
   attachments, the administrator's information request and the final decision.
   The participant view must contain no blockchain hash or contract address.
7. Check real Android camera/gallery, protected photo viewing and reconnection.
   These device interactions have not been performed in this work; automated
   widget/API checks do not replace the walkthrough.

These actions create demonstration activity; they are not independent real rental
or AI evaluation evidence. Do not modify existing real records just to demonstrate
the timeline.

## Commit message

```text
feat(rentals): clarify progress and record actual handover conditions

- show role-aware rental timelines and next steps for future approved bookings
- prevent physical handover before the booked Malaysian start day
- replace automatic condition claims with reviewed condition and photo forms
- reuse camera/batch previews and enforce private owned image evidence
- retain condition records for participant viewing and dispute review
- simplify case progress, decisions and supporting-record wording
- cover timing, evidence privacy, role isolation and responsive layouts
- document the flow, verification results and existing expiry-test inconsistency
```
