# Multi-account booking acceptance: automated results and device handoff

Verified 22 October 2026.

## Result and boundaries

**107 API tests and 104 Flutter tests passed; zero failures or skips in these
focused runs.** No implementation defect was reproduced in these suites, so no
application code was changed for this acceptance pass.

This is automated regression verification, **not completed live-device UAT**.
API suites create isolated temporary MongoDB instances and exercise Express with
Supertest and dedicated mock identities. Flutter suites use controlled
repositories/clients. The runs did not create bookings in the user's live
database, send notifications/email, make real payments, change account status,
load live environment credentials or write blockchain transactions.

## Executed suites

From `services/api`, process-local environment settings were used (not `.env`
edits): `DOTENV_CONFIG_PATH=NUL`, `NODE_ENV=test`, `AUTH_MODE=mock`,
`STORAGE_MODE=local`, `FCM_MODE=disabled`, `EMAIL_MODE=disabled`,
`BLOCKCHAIN_MODE=disabled`, `LIFECYCLE_JOBS_ENABLED=false`,
`PRICE_SYNC_JOBS_ENABLED=false`, `AI_SERVICE_URL=http://127.0.0.1:1`.
Each MongoDB test explicitly supplies its temporary database URI.

```powershell
node --test --test-reporter=spec test/booking_rental.test.js test/checkout_agreement.test.js test/payment.test.js test/financial-recovery.test.js test/dispute.test.js test/lifecycle_jobs.test.js test/precise-locations.test.js test/notification-target.test.js
```

Result: **107 passed / 107**, zero failures/skips.

From `apps/renthub_flutter`:

```powershell
flutter test --no-pub test/booking_role_isolation_test.dart test/duplicate_booking_request_test.dart test/live_booking_payment_contract_test.dart test/live_checkout_agreement_test.dart test/live_extension_checkout_test.dart test/home_notification_recovery_test.dart test/precise_location_test.dart
```

Result: **104 passed / 104**, zero failures/skips. The local invocation used the
installed Flutter tools snapshot directly to avoid the shell-wrapper issue.

## Checked behaviour

| Area | Automated verification |
| --- | --- |
| Role isolation | Outgoing renter records do not gain Owner controls; delayed loads/account switches cannot mix workspaces; actual Owner authorization remains authoritative. |
| Booking creation | Server-calculated charges, agreement acceptance, Malaysian calendar dates, ownership and required identity/licence checks. |
| Duplicate requests | Same-renter overlapping pending requests, including legacy paid pending requests, are blocked; different renters retain soft holds. |
| Checkout | Demo authorization is distinct from approval; decline/retry, ownership/session restrictions, duplicate/concurrent attempts and partial-write recovery. |
| Owner approval | Only actual Owners decide; competing overlapping pending requests expire on approval and their authorizations are released. |
| Physical lifecycle | Approval, handover, paid original-rate extension, return and settlement; duplicate actions and concurrent decisions are covered. |
| Services | Approval/delivery/completion without physical-item return/claim semantics. |
| Disputes/claims | Participant restrictions, remaining-held-funds allocation, refund/recovery limits and claims awaiting funding rather than invented payouts. |
| Notifications | Typed server targets, foreign/deleted-target restrictions and Flutter navigation/read-failure recovery; not actual FCM transport. |
| Location privacy | Pinned destinations, immutable snapshots, pending counterpart privacy, nearby filters and private-data exclusions. |

## Device UAT: still to execute

Use consenting dedicated demonstration accounts, simulated payments and permitted
sample photos. Do not use somebody else's identity documents or describe staged
bookings as real marketplace activity. Prefer a dedicated demonstration database.
Use the normal `run-renthub.ps1` configuration; do not start a second API on 3000.

Participants: account A (renter + Owner), B (actual listing Owner), C (another
renter), D (administrator). Use fresh eligible physical/service listings and
future dates; record booking references privately, never full IC numbers.

| Case | Steps and expected result | Device result |
| --- | --- | --- |
| Physical happy path | A accepts agreement, requests B's item, reviews saved checkout charges, completes demo payment. It remains pending until B approves; then handover, return, confirmation and one settlement. | Not run |
| Role switching | A switches to Owner after renting B's item. The outgoing request is absent from incoming requests and cannot be approved/rejected by A. Switch back and verify it remains available to A as renter. | Not run |
| Soft holds | A and C request B's item on overlapping dates. Both may be pending. A cannot create another overlapping pending request for that item. After B approves one eligible paid request, the competing pending one expires. | Not run |
| Unpaid/declined/cancel | Close checkout and resume payment from Bookings. Test decline and cancel: no Owner approval before success. Reject/cancel a separate request and verify its demo hold is released. | Not run |
| Extension | For an active physical rental, A requests extra days. Verify original effective daily rate, no repeated deposit/delivery/waiver, demo payment before B's approval and updated dates after approval. | Not run |
| Recovery | Interrupt a payment response, reopen and retrieve saved status before retrying. Repeated taps must not create a second successful authorization. | Not run |
| Service happy path | Request/pay/approve a service, perform delivery/completion and review. No physical handover/return or item-condition controls appear. | Not run |
| Reviews | Eligible participants publish reviews after completion; check listing and Owner ratings are not substituted for one another. | Not run |
| Dispute/claim | On a separate eligible rental open/respond to a dispute, allocate only held funds as D, and verify a claim without funding remains payout-pending. | Not run |
| Privacy/session | Check pending versus approved pickup visibility; unrelated account cannot access private records. Logout/account switch removes protected checkout and cached records. | Not run |
| Real integrations | Test Android camera/batch uploads, public pin autofill, GPS permission/accuracy, KYC rescan/pair/duplicate identity, FCM foreground/background/cold-start tap and the configured Ganache supporting record. | Not run |

For each case record pass/fail, device/app version, date, safe screenshot and
expected/actual outcome. Redact private addresses, identities, credentials and
notification tokens. A failed case remains open until reproduced, fixed and
retested. These checks do not certify AI accuracy, legal validity, real financial
processing or production readiness.

## Related verification

The immediately preceding map change had a full Flutter run of 425 passes with
three existing skips, clean Dart analysis and successful web/Android debug
builds. Those are separately recorded in `MAPS_AND_PUSH_NOTIFICATIONS_RESULT.md`;
they were not rerun or counted as new results in this documentation-only pass.
AI code/models, production data, deployed services and environment files remain
unchanged. Existing uncommitted work is preserved.
