# Android two-account booking walkthrough

Prepared and executed 2 November 2026. The two-account Android lifecycle reached
completion. This was a staged demonstration, not a genuine physical rental.

## Current results

| Check | Actual result |
| --- | --- |
| Android connected | Device detected; RentHub was open on Owner Home |
| API readiness | Ready; database connected |
| Local demonstration blockchain | Four successful receipts; on-chain state read as Completed |
| Focused booking/payment/lifecycle API regressions | 67 passed in isolated temporary databases |
| Full API suite after fixes | 626 passed, three existing opt-in skips |
| Focused Flutter checkout/agreement/payment/role regressions | 56 passed |
| Booking creation/pagination and duplicate-request regressions | Six passed |
| Full Flutter suite after fixes | 560 passed, three existing opt-in skips |
| Flutter analysis | No issues found |
| Web build | Passed; existing Socket.IO WASM/Cupertino-font warnings |
| Android debug APK build | Passed; not installed over the configured device app |
| New two-account Android booking/payment | Created one pending demo request; closed and resumed checkout; completed one Demo Card authorization |
| Android Owner approval, handover and return | Approved by actual Owner; handover uploaded; renter submitted return; Owner confirmed zero deduction |
| Android agreement access | Opened from new paid checkout and again from Owner's completed rental |

The initial preparation made no booking/payment. In the subsequent authorized
walkthrough, the user signed into each account normally at the required points;
no credentials/tokens were extracted and no authentication rules were bypassed.
All lifecycle writes used the Android interface. Database queries and chain
receipt/state checks were read-only. No dates, statuses or ledger values were
edited directly.

Automated tests use mock authentication and disabled external effects in separate
processes. Their results are separate from the actual Android/Ganache checks.
No launcher environment settings, model weights or historical records were
rewritten.

Private test output is under `services/api/.data/device-check-2026-11-02/`:
`lifecycle-api-final-tests.log`, `lifecycle-full-api.log`,
`lifecycle-flutter-fixes-final2.log`, `lifecycle-pagination-tests.log`,
`lifecycle-full-flutter.log` and `lifecycle-analysis.log`. Screenshots stay
private and must not be committed or reused as AI training examples. Private
`lifecycle-final-state.json` records safe charge/status observations;
`lifecycle-chain-proof.json` contains demonstration transaction receipts and the
contract address for technical presentation, without credentials or identity data.

## Actual staged record

The renter was a different authenticated, already-verified account from the
listing Owner. The selected active Canon R6 demonstration listing was checked
read-only for `sourceType = demo_seed`, a pickup pin and no blocking bookings.
The requested dates were **2 November 2026 to 2 November 2026**, one inclusive
calendar day. A note explicitly identified the session as a staged test without
a physical rental.

Server-saved charges were RM350 rental, RM600 deposit, RM0 delivery, no selected
waiver/platform charge and RM950 total. Closing the initial checkout left the
same pending/unpaid request with zero payment records. Continue payment reopened
that request. A single successful Demo Card authorization still left it pending
until the actual Owner approved it.

Handover produced one capture. Renter return submission remained pending Owner
inspection. Owner confirmation completed both records, with RM0 deduction,
RM600 simulated deposit release and RM350 simulated Owner settlement. The four
payment records are authorization, capture, deposit release and Owner settlement;
all have `simulated = true`. The clean-evidence policy returns `demonstration`.

For upload testing, an existing CC0 public camera sample was copied unchanged
to the phone as `Download/RentHub_DEMO_camera_upload_test.jpg` and uploaded once
under each participant's appropriate handover/return purpose. It is illustrative
and is not the listed Canon model or evidence of a real handover/condition.
Source: [12 MP digital camera - red, Packer1028](https://commons.wikimedia.org/wiki/File:12_MP_digital_camera_-_red.jpg),
[CC0](https://creativecommons.org/publicdomain/zero/1.0/).
The booking source marker and staged note remain intact. Existing private phone
photos and identity documents were not selected for upload.

## Issues found and corrected

- Returning from a newly created checkout could show a record beside a stale
  `0–0 of 0` footer. The listing flow now reloads the renter's first booking page
  and its server count after checkout, with account checks before and after the
  refresh. Reload failure retains the created record and existing retry state;
  it does not repeat booking creation/payment.
- Owner rental cards displayed an internal listing ID. They now prefer the
  saved booking title, then an available listing title, then a neutral fallback.
  The supporting-record label/action wraps instead of overflowing at narrow
  widths. Tests cover 360/390 widths with increased text size.
- The running scheduled job marked the one-day rental overdue during its final
  day. It treated stored UTC-midnight calendar dates as return-time instants.
  Overdue processing now compares completed Malaysia calendar days after grace;
  return reminders use the next Malaysia midnight as the deadline. Regression
  tests cover 23:59:59 versus midnight, grace boundaries, reminder windows,
  legacy non-midnight stored dates, leap/year boundaries and unchanged service
  timestamp behavior. The already-issued staged overdue notification was not
  deleted and history was not rewritten. Return/completion still succeeded.

The Flutter corrections are source/test verified; the configured phone APK was
not replaced during the walkthrough. Rebuild/run through the existing launcher
to display those corrections. The API uses its normal watcher/restart behavior.
The final API readiness check returned ready. The phone was left on Owner Home
showing the completed staged order. The test image remains in Downloads with
its explicit demo filename; no existing phone files were deleted.

## Accounts and test record

Use two separately authenticated, active, already-verified dedicated test
accounts: one actual listing Owner and one renter. Switching a dual-role
account's role does not create a second participant. Each person signs in
normally; do not share passwords, extract tokens, bypass KYC or change Auth0.

Choose an existing active **labelled demo physical listing** belonging to the
Owner account, with a usable pickup pin and available dates. Use a nonvehicle
item so a driving licence is not an unrelated prerequisite. Confirm the listing
is marked as demonstration data, not merely named "Demo": bookings copy the
listing's source marker. Do not create an ordinary marketplace listing to make
this staged session look like natural activity.

Prefer a one-day rental on the current Malaysia calendar date if available;
otherwise select valid available dates and record them as staged. Never change
the device clock or rewrite booking timestamps/statuses to accelerate the test.
Use pickup to keep delivery/address entry separate from this baseline test.
Read the actual saved charge breakdown rather than assuming any fixed price.

Handover and return require privately uploaded condition-photo evidence. Prepare
appropriate permissioned test photos, clearly identified as staged/demo evidence;
never substitute identity documents or claim an illustrative image proves a real
handover. No photo has been uploaded for this walkthrough.

## Walkthrough and expected states

| Step | Account / action | Expected result |
| --- | --- | --- |
| 1 | Renter opens the other account's demo listing and chooses available dates | Correct listing, dates and pickup; no self-booking |
| 2 | Review and accept the agreement, then create request | Pending and unpaid; dates remain soft holds |
| 3 | Open checkout | Server-saved itemized MYR total; entering creates no transaction |
| 4 | Close checkout, then reopen using Continue payment | Same pending request; no duplicate booking or authorization |
| 5 | Explicit successful Demo Card/FPX/Wallet payment | Demo payment complete; awaiting Owner approval, not confirmed |
| 6 | Open View agreement from the payment result | Correct record, saved charges and acceptance; pending exact-location privacy preserved |
| 7 | Sign into actual Owner account; open Requests | Request is visible only as an incoming Owner record |
| 8 | Review and approve | Approved booking and scheduled rental; confirmed availability blocks conflicting dates |
| 9 | Inspect supporting record | Record saved if integration succeeds; failure is separate from booking approval |
| 10 | Owner confirms handover with test evidence | Rental active; existing authorization captured once |
| 11 | Sign into renter account and submit return with test evidence | Return submitted; Owner inspection still required |
| 12 | Owner confirms inspected return with zero deduction for this baseline | Completed; deposit/Owner settlement follows saved charges without duplicate payouts |
| 13 | Both accounts reopen the agreement and history | Correct participant access, saved statuses and available recorded timestamps |

After a lost response, retrieve the record before retrying a write. Record the
actual booking reference privately so account switches find the same record.
Do not operate on an unrelated existing request or approve a past-dated request
just to obtain a demonstration result.

## Blockchain explanation for the demonstration

Show the in-app agreement's supporting-record state. For supervisor-facing
technical proof, separately inspect the local Ganache deployment/transaction
receipt and contract lifecycle using the existing development tools. Distinguish
the creation transaction from the completion transaction and verify receipts
before calling either successful. This walkthrough verified the deployment,
both test-wallet signing receipts and the completion receipt, all with successful
status. A direct contract state read returned Completed (enum value 2).

This is a local EVM demonstration network with test funds and backend-managed
test wallets. It does not transfer real MYR, prove a user's wallet ownership or
protect the entire agreement text. Services do not use the physical-rental
contract. A chain-ID response establishes reachability only.

## Evidence and remaining work

This staged session can demonstrate workflow and access controls. Its demo
payments and bookings must remain excluded from independently verified
completed-rental pricing evidence; it cannot establish real-world AI accuracy.
Real-device GPS, camera quality and push delivery remain separate checks.

The baseline staged lifecycle is complete. A separate post-build phone check
should confirm the revised count/title layout. The overdue boundary correction
was verified in isolated controlled-time tests; it was not re-demonstrated by
changing the phone clock or creating another live rental. Demo listing images
showed an existing placeholder on this device; local selected-upload previews
worked. Camera capture, precise GPS and actual push delivery were not tested in
this lifecycle. No reviews, disputes or extensions were created.

## Commit message

```text
fix(bookings): correct calendar deadlines and checkout record display

- keep physical rentals active through their final Malaysia calendar day
- align return reminders and overdue grace with inclusive rental dates
- refresh server booking counts after leaving newly created checkout
- show saved item titles and wrap Owner agreement actions on narrow screens
- add calendar-boundary, role-safe title and checkout-pagination regressions
- record the two-account Android demo lifecycle and verified Ganache receipts
- keep staged payments and rentals excluded from clean pricing evidence
```
