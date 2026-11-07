# RentHub full-platform test plan

Generated from `tests/platform/case_catalogue.py`. Run the pack checker after editing that catalogue.

**82 flow groups, 584 independently recorded variants, ten modules, 22 physical subcategories.**

This is executable test intent, not proof of completed testing. Every new manual execution starts **Not run**.

Start with [the operating instructions](README.md). Actual results belong in a new private `.data/testing` run, not this source document.

## Priority order

| Priority | Variants | Rule |
| --- | ---: | --- |
| P0 | 161 | Critical access, privacy, money and rental integrity; run first |
| P1 | 300 | Complete functional module coverage |
| P2 | 123 | Device, resilience, evaluation and presentation |

## Ten-module coverage

| Module | Flow groups |
| --- | --- |
| User Management | P0-01, P0-02, P0-03, P0-04, P0-05, P0-06, P0-07, P1-U01, P1-U02, P1-U03, P1-U04, P1-U05, P1-U06, P1-U07, P2-02, P2-03, P2-05 |
| Listing Management | P0-08, P1-L01, P1-L02, P1-L03, P1-L04, P1-L05, P1-L06, P1-L07, P1-L08, P1-L09, P1-L10, P1-L11, P1-L12, P2-04, P2-06, P2-07, P2-08 |
| Booking Management | P0-09, P0-10, P0-13, P0-14, P0-25, P1-B01, P1-B02 |
| Payment Management | P0-11, P0-12, P0-19, P0-24, P1-B04 |
| Rental Management | P0-15, P0-16, P0-17, P0-18, P0-20, P0-26, P1-B03 |
| Communication Management | P1-C01, P1-C02, P1-C03, P1-C04, P1-C05, P1-C06, P2-09 |
| Review Management | P1-V01, P1-V02, P1-V03 |
| Dispute Management | P0-21, P0-22, P0-23, P1-D01, P1-D02 |
| Loyalty and Referral Management | P1-Y01, P1-Y02, P1-Y03, P1-Y04 |
| Admin Management | P1-A01, P1-A02, P1-A03, P1-A04, P1-A05, P1-A06, P1-A07, P1-A08, P2-01, P2-10 |

## Category matrix

| Category | Specific categories |
| --- | --- |
| Devices | Smartphones, Cameras, Computers, Audio, Gaming, Other devices |
| Vehicles | Cars, Motorcycles, Bicycles, Other vehicles |
| Equipment | Tools, Sports equipment, Event equipment, Other equipment |
| Books | Textbooks, Reference books, Fiction, Other books |
| Clothing | Formal wear, Costumes, Traditional wear, Other clothing |

Mice, keyboards, monitors and controllers have separate P1-L04 variants. Services have separate venue/lifecycle cases.

P2-07 references the existing private 198-slot recognition review kit. Its 66 evaluation batches are not 66 independent photos and do not complete that kit. Do not fabricate labels, boxes or results.

## Flow execution instructions

Use a separate result for each listed variant. Common steps describe the workflow; execute the branch named by the variant, using a fresh record. Never force an invalid variant through to the later success steps.

Regression references identify relevant suites, not an assertion that every listed manual branch is automated or passed. Real hardware, provider delivery, identity review and independent AI accuracy need their own evidence.

### P0-01 — Startup and safe service reuse

**Module:** User Management · **Actors:** Owner A, Admin M

**Preconditions:** Configured test laptop and app; no business action submitted.

**Steps**

1. Start the normal launcher.
2. Open Android and admin.
3. Repeat startup while the services are ready.
4. Record readiness and loaded photos/records.

**Expected:** Ready or actionable failure; no duplicate servers or unrelated process termination.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-01-01 | Cold start | Not run |
| P0-01-02 | Already running | Not run |
| P0-01-03 | Android retrieval | Not run |
| P0-01-04 | Admin retrieval | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-02 — Sign-in, persistence and logout

**Module:** User Management · **Actors:** Owner A, Renter B

**Preconditions:** Prepared local and Auth0 test accounts.

**Steps**

1. Choose the specified sign-in method.
2. Complete or cancel authentication.
3. Close and reopen the app.
4. Confirm or cancel logout.
5. Attempt protected navigation.

**Expected:** Correct session/account; cancelled login resets controls; logout revokes access; no unsolicited Auth0 redirect.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-02-01 | Local login | Not run |
| P0-02-02 | Auth0 login | Not run |
| P0-02-03 | Browser cancellation | Not run |
| P0-02-04 | Restart persistence | Not run |
| P0-02-05 | Cancel logout | Not run |
| P0-02-06 | Confirm logout | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-03 — Authorization and private record isolation

**Module:** User Management · **Actors:** Renter B, Admin M

**Preconditions:** A owns the target listing/booking/upload; B has no ownership.

**Steps**

1. Attempt the specified foreign operation in the UI.
2. Repeat using an authenticated isolated API test.
3. Read the record again as A.

**Expected:** Unauthorized response; unchanged record; no private information leaked.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-03-01 | Foreign listing edit | Not run |
| P0-03-02 | Foreign approval | Not run |
| P0-03-03 | Foreign upload | Not run |
| P0-03-04 | Admin endpoint | Not run |
| P0-03-05 | Forged role/status | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-04 — Mandatory identity gate

**Module:** User Management · **Actors:** User D

**Preconditions:** Unverified dedicated account; public listing available.

**Steps**

1. Browse a listing.
2. Save an incomplete draft.
3. Attempt final listing submission.
4. Attempt checkout.
5. Attempt forged approval in isolated API test.

**Expected:** Permitted browsing/drafts work; identity-required actions fail clearly; no forged approval.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-04-01 | Browse | Not run |
| P0-04-02 | Save draft | Not run |
| P0-04-03 | Submit listing | Not run |
| P0-04-04 | Checkout | Not run |
| P0-04-05 | Forged verification | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-05 — MyKad readability and pair validation

**Module:** User Management · **Actors:** User D, Admin M

**Preconditions:** Permissioned private document fixtures; scanner/OCR ready; no public identity screenshot.

**Steps**

1. Capture or upload the specified sides.
2. Inspect mandatory guidance.
3. Use Image only if enabled.
4. Replace/remove front after pair validation.
5. Attempt final submission.

**Expected:** Unreadable, wrong-side, mismatch and clear screen-copy cases require rescan; changed front invalidates pair; valid pair goes to review, not automatic authenticity approval.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-05-01 | Readable pair | Not run |
| P0-05-02 | Wrong side | Not run |
| P0-05-03 | Mismatched numbers | Not run |
| P0-05-04 | Covered name/address | Not run |
| P0-05-05 | Unreadable number | Not run |
| P0-05-06 | Screen copy | Not run |
| P0-05-07 | Front replaced | Not run |
| P0-05-08 | Front removed | Not run |
| P0-05-09 | Model unavailable | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-06 — One identity per verified account

**Module:** User Management · **Actors:** Owner A, User D, Admin M

**Preconditions:** A has a verified binding; use synthetic keyed fixtures for concurrency rather than approving new real identities.

**Steps**

1. Retry the same-account attempt.
2. Submit the bound identity from the other account.
3. Run competing pending approvals in temporary database.
4. Inspect safe error and binding count.

**Expected:** Same-account retries allowed; no second verified binding; pending does not reserve identity; no identifying details in duplicate error.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-06-01 | Same account | Not run |
| P0-06-02 | Already bound elsewhere | Not run |
| P0-06-03 | Concurrent approvals | Not run |
| P0-06-04 | Missing key/index | Not run |
| P0-06-05 | Legacy gap disclosed | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-07 — Vehicle driving eligibility

**Module:** User Management · **Actors:** Renter B, Owner A

**Preconditions:** Vehicle with explicit applicable licence rule; separate prepared licence states.

**Steps**

1. Choose vehicle dates.
2. Attempt request, approval, handover and extension with the specified eligibility.
3. Check identity status separately.

**Expected:** Applicable class and rental-date validity enforced; licence and MyKad statuses remain separate.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-07-01 | No approval | Not run |
| P0-07-02 | Expired licence | Not run |
| P0-07-03 | Wrong class | Not run |
| P0-07-04 | Valid approval | Not run |
| P0-07-05 | Expires during rental/extension | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P0-08 — Draft to final listing submission

**Module:** Listing Management · **Actors:** Owner A, User D, Admin M

**Preconditions:** Fresh physical and service drafts; permissioned photos; valid pins ready.

**Steps**

1. Save incomplete draft.
2. Reopen it.
3. Attempt submission incomplete.
4. Complete required fields.
5. Submit for moderation.
6. Inspect public feed before approval.

**Expected:** Missing values retained, not converted to invented defaults; drafts private; submission enforces conditional requirements; failed submission retains draft/photos.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-08-01 | Physical incomplete | Not run |
| P0-08-02 | Service incomplete | Not run |
| P0-08-03 | Reopen | Not run |
| P0-08-04 | Missing pin/photos | Not run |
| P0-08-05 | Complete submission | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P0-09 — Physical calendar dates and availability

**Module:** Booking Management · **Actors:** Renter B, Owner A

**Preconditions:** Available listing; known approved/manual unavailable range; dates chosen relative to test day.

**Steps**

1. Select start/end dates for the variant.
2. Review charges.
3. Submit where valid.
4. Reopen/restart and inspect dates.

**Expected:** Inclusive Malaysia days preserved; invalid or crossing confirmed ranges blocked; pending is not a confirmed unavailable range.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-09-01 | One day | Not run |
| P0-09-02 | Future dates | Not run |
| P0-09-03 | End before start | Not run |
| P0-09-04 | Cross blocked range | Not run |
| P0-09-05 | Malaysia midnight | Not run |
| P0-09-06 | Leap/year boundary | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P0-10 — Duplicate requests and soft holds

**Module:** Booking Management · **Actors:** Renter B, Renter C

**Preconditions:** Same listing; isolated same-renter and different-renter attempts.

**Steps**

1. B starts eligible checkout.
2. B retries same/overlapping dates with a fresh attempt.
3. C requests same dates.
4. Repeat using a legacy pending fixture.

**Expected:** B recovers existing eligible request; C may create a competing pending request; no confirmed reservation before approval.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-10-01 | Exact duplicate | Not run |
| P0-10-02 | Partial overlap | Not run |
| P0-10-03 | Different renter | Not run |
| P0-10-04 | Legacy pending | Not run |
| P0-10-05 | Expired request | Not run |
| P0-10-06 | Paid after payment window | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P0-11 — Explicit simulated checkout outcomes

**Module:** Payment Management · **Actors:** Renter B

**Preconditions:** Fresh unpaid booking per method/outcome; saved itemized charges.

**Steps**

1. Open checkout.
2. Check amount and simulation label.
3. Choose specified demo method.
4. Choose success, decline, cancel or close.
5. Read status and transactions.

**Expected:** Entering/closing creates no payment; only explicit success authorizes once; decline/cancel remain unpaid; Owner approval still required.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-11-01 | Card success | Not run |
| P0-11-02 | Card decline | Not run |
| P0-11-03 | Card cancel | Not run |
| P0-11-04 | Card close | Not run |
| P0-11-05 | FPX success | Not run |
| P0-11-06 | FPX decline | Not run |
| P0-11-07 | FPX cancel | Not run |
| P0-11-08 | FPX close | Not run |
| P0-11-09 | Wallet success | Not run |
| P0-11-10 | Wallet decline | Not run |
| P0-11-11 | Wallet cancel | Not run |
| P0-11-12 | Wallet close | Not run |

**Relevant regression suites:** [payment.test.js](../../services/api/test/payment.test.js), [checkout_agreement.test.js](../../services/api/test/checkout_agreement.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [payment_window_ui_test.dart](../../apps/renthub_flutter/test/payment_window_ui_test.dart).

### P0-12 — Fixed ten-minute initial payment window

**Module:** Payment Management · **Actors:** Renter B, Owner A

**Preconditions:** API/jobs online; fresh unpaid checkout; real device notification permission if testing delivery.

**Steps**

1. Note original deadline.
2. Leave and resume checkout.
3. Observe final-two-minute reminder.
4. Wait through expiry.
5. Attempt late payment.
6. Run boundary variants with controlled test time.

**Expected:** Awaiting payment and no steps before payment; no reset; one reminder/expiry notice; late writes rejected; timely payment reveals Owner approval steps.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-12-01 | Resume unchanged | Not run |
| P0-12-02 | Before deadline | Not run |
| P0-12-03 | At deadline | Not run |
| P0-12-04 | After deadline | Not run |
| P0-12-05 | Reminder dedupe | Not run |
| P0-12-06 | Paid before expiry | Not run |
| P0-12-07 | Legacy unpaid | Not run |
| P0-12-08 | Gateway crosses deadline | Not run |

**Relevant regression suites:** [payment.test.js](../../services/api/test/payment.test.js), [checkout_agreement.test.js](../../services/api/test/checkout_agreement.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [payment_window_ui_test.dart](../../apps/renthub_flutter/test/payment_window_ui_test.dart).

### P0-13 — Owner decisions and competing requests

**Module:** Booking Management · **Actors:** Owner A, Renter B, Renter C

**Preconditions:** Separate paid/unpaid pending requests and overlapping paid requests.

**Steps**

1. Open actual Owner requests.
2. Approve/reject specified record.
3. Test blank reason.
4. Approve competing records concurrently in isolated tests.
5. Inspect both renters.

**Expected:** Owner-only decisions; unpaid approval blocked; reason enforced; only one confirmed overlapping physical booking; competing pending records invalidated correctly.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-13-01 | Paid approval | Not run |
| P0-13-02 | Unpaid approval | Not run |
| P0-13-03 | Rejection | Not run |
| P0-13-04 | Blank reason | Not run |
| P0-13-05 | Concurrent overlap | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P0-14 — Account and active-role isolation

**Module:** Booking Management · **Actors:** Renter B, Owner A

**Preconditions:** B rents A listing; both marketplace interfaces available.

**Steps**

1. Open B bookings.
2. Switch B to Owner.
3. Rapidly switch roles/accounts during delayed loads.
4. Open focused notification.
5. Return to each collection.

**Expected:** Outgoing records never become incoming requests; no foreign decision buttons; correct role caches and guarded late responses.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-14-01 | Role switch | Not run |
| P0-14-02 | Rapid switch | Not run |
| P0-14-03 | Delayed response | Not run |
| P0-14-04 | Account replacement | Not run |
| P0-14-05 | Notification focus | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P0-15 — Future scheduled rental and handover date

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Paid approved future physical booking; no handover.

**Steps**

1. Inspect scheduled progress.
2. Attempt early handover.
3. Run controlled Malaysia start-day boundary test.
4. Inspect capture count.

**Expected:** Approval is scheduled, not delivered/active; early handover/capture blocked; correct next action on the booked day.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-15-01 | Before day | Not run |
| P0-15-02 | Malaysia day begins | Not run |
| P0-15-03 | Future reopen | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P0-16 — Condition evidence and single handover

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Approved current-day physical rental; owned condition photos.

**Steps**

1. Record actual condition and photos.
2. Test missing/foreign evidence separately.
3. Confirm handover twice.
4. Read both accounts and payment ledger.

**Expected:** Required owned evidence; saved actual condition; authorized participant access; one start and one capture.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-16-01 | Valid handover | Not run |
| P0-16-02 | Missing evidence | Not run |
| P0-16-03 | Foreign evidence | Not run |
| P0-16-04 | Double tap | Not run |
| P0-16-05 | Retry after lost response | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P0-17 — Return inspection and deposit settlement

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Active captured physical rental; separate booking for deduction branch.

**Steps**

1. B submits return photos.
2. Check still awaiting inspection.
3. A compares handover and return.
4. Confirm return with variant deduction.
5. Repeat confirmation and inspect ledger.

**Expected:** Submission alone is not completion; final return completes linked records; correct deposit/Owner allocation; no duplicate payouts.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-17-01 | Zero deduction | Not run |
| P0-17-02 | Permitted deduction | Not run |
| P0-17-03 | Excess deduction | Not run |
| P0-17-04 | Repeated confirmation | Not run |
| P0-17-05 | Insufficient remaining funds | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P0-18 — Separate service lifecycle

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Approved service booking with specified venue mode.

**Steps**

1. Book and pay service.
2. Approve.
3. Start.
4. Mark delivered.
5. Confirm completion.
6. Inspect agreement and charges.

**Expected:** Correct venue/service workflow; no physical condition/return/deposit or physical blockchain claims where inapplicable.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-18-01 | Online | Not run |
| P0-18-02 | Owner location | Not run |
| P0-18-03 | Renter location | Not run |
| P0-18-04 | Flexible venue | Not run |
| P0-18-05 | Completion confirmation | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P0-19 — Cancellation, rejection and refunds

**Module:** Payment Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Separate unpaid, authorized and captured fixtures; note held balances.

**Steps**

1. Cancel/reject eligible record with confirmation.
2. Inspect hold/capture.
3. Request partial/full/over-limit refund in staging.
4. Retry same intent.

**Expected:** Policy respected; uncaptured holds released; refunds bounded by capture and held balance; no double payout.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-19-01 | Unpaid cancel | Not run |
| P0-19-02 | Paid pending cancel | Not run |
| P0-19-03 | Approved cancellation | Not run |
| P0-19-04 | Owner rejection | Not run |
| P0-19-05 | Partial refund | Not run |
| P0-19-06 | Full refund | Not run |
| P0-19-07 | Over-limit refund | Not run |
| P0-19-08 | Repeated refund | Not run |

**Relevant regression suites:** [payment.test.js](../../services/api/test/payment.test.js), [checkout_agreement.test.js](../../services/api/test/checkout_agreement.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [payment_window_ui_test.dart](../../apps/renthub_flutter/test/payment_window_ui_test.dart).

### P0-20 — Paid extensions and quote identity

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Active physical rental with trustworthy original rate; separate extension branches.

**Steps**

1. Request extra days.
2. Inspect quote.
3. Cancel/decline/pay.
4. Owner approves/rejects.
5. Try conflicting dates and stale quote ID.
6. Return/open dispute with a pending extension.

**Expected:** Original effective daily rate; no repeated fixed fees; dates change only after payment and approval; stale/conflicting decisions blocked; holds released appropriately.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-20-01 | Cancel payment | Not run |
| P0-20-02 | Decline | Not run |
| P0-20-03 | Pay and approve | Not run |
| P0-20-04 | Pay and reject | Not run |
| P0-20-05 | Conflicting dates | Not run |
| P0-20-06 | Stale quote | Not run |
| P0-20-07 | Return/dispute closes hold | Not run |
| P0-20-08 | Legacy missing rate | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P0-21 — Issue reporting before final completion

**Module:** Dispute Management · **Actors:** Renter B, Owner A

**Preconditions:** Eligible unfinished records, including elapsed booked end dates.

**Steps**

1. Open the specified rental/service status.
2. Report issue and attach permitted evidence.
3. Other participant responds.
4. Try a duplicate case.

**Expected:** One authorized case; retained evidence/responses; booked end or capture alone does not close dispute window.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-21-01 | Active | Not run |
| P0-21-02 | Overdue | Not run |
| P0-21-03 | Return submitted | Not run |
| P0-21-04 | Service completion pending | Not run |
| P0-21-05 | Duplicate case | Not run |

**Relevant regression suites:** [dispute.test.js](../../services/api/test/dispute.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [dispute_completion_cutoff_test.dart](../../apps/renthub_flutter/test/dispute_completion_cutoff_test.dart).

### P0-22 — Final-completion dispute cutoff

**Module:** Dispute Management · **Actors:** Renter B, Owner A

**Preconditions:** Completed physical/service records and one open stale form.

**Steps**

1. Finish return/service.
2. Check both accounts.
3. Attempt direct new case.
4. Complete remotely while form is open.
5. Inspect existing case history.

**Expected:** No new dispute after either linked record completes; DISPUTE_WINDOW_CLOSED; no financial/chain/new-case side effect; draft retained; existing history accessible.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-22-01 | Physical completed | Not run |
| P0-22-02 | Service completed | Not run |
| P0-22-03 | Booking-only complete | Not run |
| P0-22-04 | Rental-only complete | Not run |
| P0-22-05 | Stale form | Not run |
| P0-22-06 | Existing resolved case | Not run |

**Relevant regression suites:** [dispute.test.js](../../services/api/test/dispute.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [dispute_completion_cutoff_test.dart](../../apps/renthub_flutter/test/dispute_completion_cutoff_test.dart).

### P0-23 — Case decisions, remaining funds and claims

**Module:** Dispute Management · **Actors:** Renter B, Owner A, Admin M

**Preconditions:** Separate open disputes; held balances recorded; waiver-enabled physical fixture.

**Steps**

1. Request evidence.
2. Respond.
3. Dismiss or allocate remaining funds.
4. Approve/reject claim.
5. Repeat same/conflicting decision.

**Expected:** Authorized decisions only; no clawback or double payout; matching retries stable; approved unfunded claim remains pending funding.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-23-01 | More evidence | Not run |
| P0-23-02 | Dismiss | Not run |
| P0-23-03 | Split balance | Not run |
| P0-23-04 | Release renter | Not run |
| P0-23-05 | Release Owner | Not run |
| P0-23-06 | Claim approved | Not run |
| P0-23-07 | Claim rejected | Not run |
| P0-23-08 | Repeated/conflicting resolution | Not run |

**Relevant regression suites:** [dispute.test.js](../../services/api/test/dispute.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [dispute_completion_cutoff_test.dart](../../apps/renthub_flutter/test/dispute_completion_cutoff_test.dart).

### P0-24 — Recovery after uncertain write outcomes

**Module:** Payment Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Isolated fault-injection fixtures; do not stop unrelated live services.

**Steps**

1. Interrupt response after specified durable operation.
2. Read booking/payment status.
3. Explicitly retry same intent only when appropriate.
4. Check counts and ledger.

**Expected:** Recover recorded outcome; no blind repeated writes or duplicate financial/status effects; controls recover.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-24-01 | Booking | Not run |
| P0-24-02 | Authorization | Not run |
| P0-24-03 | Approval | Not run |
| P0-24-04 | Handover | Not run |
| P0-24-05 | Return | Not run |
| P0-24-06 | Refund | Not run |
| P0-24-07 | Process restart | Not run |

**Relevant regression suites:** [payment.test.js](../../services/api/test/payment.test.js), [checkout_agreement.test.js](../../services/api/test/checkout_agreement.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [payment_window_ui_test.dart](../../apps/renthub_flutter/test/payment_window_ui_test.dart).

### P0-25 — Private locations and protected uploads

**Module:** Booking Management · **Actors:** Renter B, Renter C, Owner A, Admin M

**Preconditions:** Pinned listing and destination snapshots; unrelated C.

**Steps**

1. Read public listing/feed/wishlist/comparison.
2. Inspect pending and qualifying booking location endpoint.
3. Try foreign files.
4. Edit source address after creation.

**Expected:** Approximate public points only; counterpart exact snapshots unlock only as permitted; unchanged snapshots; owned/participant/admin access only.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-25-01 | Public | Not run |
| P0-25-02 | Pending | Not run |
| P0-25-03 | Approved/active | Not run |
| P0-25-04 | Completed/disputed | Not run |
| P0-25-05 | Cancelled/rejected/expired | Not run |
| P0-25-06 | Unrelated user | Not run |
| P0-25-07 | Address changed | Not run |
| P0-25-08 | Protected evidence | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P0-26 — Saved agreements and local-chain proof

**Module:** Rental Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Physical/service bookings with versioned terms; local demo chain.

**Steps**

1. Read agreement before and after approval and payment result.
2. Complete lifecycle.
3. Inspect receipts/state with read-only tools.
4. Simulate failed/disabled record integration in isolated tests.

**Expected:** Saved charges/history; no invented acceptance/signatures; physical successful receipt/state proof; record failure separate from approved booking; services no false chain coverage.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P0-26-01 | Before approval | Not run |
| P0-26-02 | Android payment result | Not run |
| P0-26-03 | After completion | Not run |
| P0-26-04 | Historical missing data | Not run |
| P0-26-05 | Chain confirmed | Not run |
| P0-26-06 | Chain unavailable | Not run |
| P0-26-07 | Service agreement | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P1-U01 — Registration and consistent validation

**Module:** User Management · **Actors:** User D

**Preconditions:** Fresh local registration form; duplicate dedicated email.

**Steps**

1. Enter valid or specified invalid data.
2. Submit.
3. Correct fields and retry.
4. Repeat bypass through API.

**Expected:** Inline and server validation agree; passwords never trimmed; no account on invalid input.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U01-01 | Valid | Not run |
| P1-U01-02 | Duplicate email | Not run |
| P1-U01-03 | Password bounds | Not run |
| P1-U01-04 | Confirmation mismatch | Not run |
| P1-U01-05 | Malaysian phone | Not run |
| P1-U01-06 | Numeric paste | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U02 — Password reset and provider routing

**Module:** User Management · **Actors:** User D

**Preconditions:** Dedicated local/Auth0 users; permitted email delivery test.

**Steps**

1. Request reset.
2. Use specified code state.
3. Complete valid reset.
4. Try reuse.
5. Inspect provider route.

**Expected:** Generic account-safe responses; six-digit string; cooldown/attempt/expiry/single-use rules; correct provider.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U02-01 | Local valid | Not run |
| P1-U02-02 | Wrong code | Not run |
| P1-U02-03 | Expired code | Not run |
| P1-U02-04 | Reused code | Not run |
| P1-U02-05 | Cooldown | Not run |
| P1-U02-06 | Auth0 reset | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U03 — Profile persistence and public privacy

**Module:** User Management · **Actors:** Owner A, Renter B

**Preconditions:** Prepared profile; second session.

**Steps**

1. Edit photo/name/bio/phone.
2. Save.
3. Reopen on other device.
4. Read public counterpart profile.

**Expected:** Saved authorized values; optional omissions; no private identity/address fields in public response.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U03-01 | Text edits | Not run |
| P1-U03-02 | Photo | Not run |
| P1-U03-03 | Optional empty phone | Not run |
| P1-U03-04 | Other device | Not run |
| P1-U03-05 | Public profile | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U04 — Saved address CRUD

**Module:** User Management · **Actors:** Renter B

**Preconditions:** Pinned and legacy unpinned dedicated addresses.

**Steps**

1. Add through picker.
2. Edit one address.
3. Cancel selection.
4. Delete with confirmation.
5. Use destination in booking.

**Expected:** Correct address and stable IDs; preserve other addresses; leading zeros; unpinned destination blocked until pinned.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U04-01 | Add | Not run |
| P1-U04-02 | Edit | Not run |
| P1-U04-03 | Cancel | Not run |
| P1-U04-04 | Delete | Not run |
| P1-U04-05 | Leading-zero postcode | Not run |
| P1-U04-06 | Legacy unpinned | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U05 — Sessions and account lifecycle

**Module:** User Management · **Actors:** Restricted user, Admin M

**Preconditions:** Dedicated expendable account; no unrelated business obligations.

**Steps**

1. Inspect/revoke local sessions.
2. Sign out others.
3. Deactivate through normal policy.
4. Reactivate as admin.
5. Attempt old-session access.

**Expected:** Correct restrictions and revocation; no claim local inventory revokes all Auth0 sessions.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U05-01 | Revoke one | Not run |
| P1-U05-02 | Revoke others | Not run |
| P1-U05-03 | Deactivate | Not run |
| P1-U05-04 | Blocked deactivation | Not run |
| P1-U05-05 | Reactivate | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U06 — Document review and unavailable analysis

**Module:** User Management · **Actors:** User D, Admin M

**Preconditions:** Private permissioned fixtures; separate pending attempts.

**Steps**

1. Submit supported document.
2. Review or request resubmission.
3. Reopen history.
4. Test unavailable model and invalid file.

**Expected:** Independent document statuses/history; targeted recovery; no automatic approval or green unverified chip.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U06-01 | Approve MyKad | Not run |
| P1-U06-02 | Reject | Not run |
| P1-U06-03 | Resubmit | Not run |
| P1-U06-04 | Driving review | Not run |
| P1-U06-05 | Unavailable OCR/model | Not run |
| P1-U06-06 | Large/invalid file | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-U07 — Role-specific trust and provenance

**Module:** User Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Separate demo/genuine fixtures; current maturity settings.

**Steps**

1. Read new-user trust.
2. Complete eligible fixture interactions.
3. Publish/moderate reviews.
4. Resolve responsibility.
5. Refresh role summaries.

**Expected:** Counts derived once; sufficient maturity required; no invented score; demo/genuine and roles separated.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-U07-01 | New account | Not run |
| P1-U07-02 | Completion | Not run |
| P1-U07-03 | Review update | Not run |
| P1-U07-04 | Responsible finding | Not run |
| P1-U07-05 | Demo separation | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P1-L01 — Listing lifecycle and Owner preview

**Module:** Listing Management · **Actors:** Owner A, Admin M

**Preconditions:** Separate physical/service drafts.

**Steps**

1. Create/edit.
2. Save draft.
3. Submit.
4. Approve/reject.
5. Activate/deactivate.
6. Preview as Owner and renter.

**Expected:** Conditional fields and guarded transitions; draft private; no accidental active-to-draft change; Owner cannot book own listing.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L01-01 | Physical | Not run |
| P1-L01-02 | Service | Not run |
| P1-L01-03 | Moderation approve | Not run |
| P1-L01-04 | Moderation reject | Not run |
| P1-L01-05 | Activate/deactivate | Not run |
| P1-L01-06 | Owner preview | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L02 — Camera, batch photos and retry

**Module:** Listing Management · **Actors:** Owner A

**Preconditions:** Permissioned item images and invalid files.

**Steps**

1. Take photo or choose multiple.
2. Inspect carousel.
3. Reorder/remove.
4. Cancel/retry failed upload.
5. Reopen draft.

**Expected:** Limits/types enforced; consistent references/previews; bytes retained for retry; no unintended upload.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L02-01 | Camera | Not run |
| P1-L02-02 | Multiple select | Not run |
| P1-L02-03 | Carousel | Not run |
| P1-L02-04 | Reorder/remove | Not run |
| P1-L02-05 | Cancel | Not run |
| P1-L02-06 | Upload failure | Not run |
| P1-L02-07 | Limits/type | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L03 — Evidence-led Brand and Model selection

**Module:** Listing Management · **Actors:** Owner A

**Preconditions:** Current category and reviewed local reference/cache suggestions.

**Steps**

1. Open Brand without typing.
2. Select brand and Model.
3. Search.
4. Enter manually.
5. Find more products explicitly.
6. Reopen saved selection.

**Expected:** Local browsing no automatic external refresh; correct brand/domain; optional canonical IDs; retained text and fallback.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L03-01 | Browse | Not run |
| P1-L03-02 | Brand to model | Not run |
| P1-L03-03 | Search | Not run |
| P1-L03-04 | Manual | Not run |
| P1-L03-05 | Explicit provider lookup | Not run |
| P1-L03-06 | Provider failure | Not run |
| P1-L03-07 | Reopen draft | Not run |
| P1-L03-08 | Stale response | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L04 — Every physical subcategory and peripherals

**Module:** Listing Management · **Actors:** Owner A, Admin M

**Preconditions:** Valid named product/example for selected domain; current taxonomy.

**Steps**

1. Select category/subcategory.
2. Browse/search identity or enter manually.
3. Complete listing requirements.
4. Submit and inspect domain mapping.

**Expected:** Correct type/category; plausible suggestions or honest manual fallback; no invented identity; recognition uncertainty remains reviewable.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L04-01 | Devices / Smartphones | Not run |
| P1-L04-02 | Devices / Cameras | Not run |
| P1-L04-03 | Devices / Computers | Not run |
| P1-L04-04 | Devices / Audio | Not run |
| P1-L04-05 | Devices / Gaming | Not run |
| P1-L04-06 | Devices / Other devices | Not run |
| P1-L04-07 | Vehicles / Cars | Not run |
| P1-L04-08 | Vehicles / Motorcycles | Not run |
| P1-L04-09 | Vehicles / Bicycles | Not run |
| P1-L04-10 | Vehicles / Other vehicles | Not run |
| P1-L04-11 | Equipment / Tools | Not run |
| P1-L04-12 | Equipment / Sports equipment | Not run |
| P1-L04-13 | Equipment / Event equipment | Not run |
| P1-L04-14 | Equipment / Other equipment | Not run |
| P1-L04-15 | Books / Textbooks | Not run |
| P1-L04-16 | Books / Reference books | Not run |
| P1-L04-17 | Books / Fiction | Not run |
| P1-L04-18 | Books / Other books | Not run |
| P1-L04-19 | Clothing / Formal wear | Not run |
| P1-L04-20 | Clothing / Costumes | Not run |
| P1-L04-21 | Clothing / Traditional wear | Not run |
| P1-L04-22 | Clothing / Other clothing | Not run |
| P1-L04-23 | Peripheral / mouse | Not run |
| P1-L04-24 | Peripheral / keyboard | Not run |
| P1-L04-25 | Peripheral / monitor | Not run |
| P1-L04-26 | Peripheral / controller | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L05 — Item-photo assistance

**Module:** Listing Management · **Actors:** Owner A, Admin M

**Preconditions:** Separate permissioned overview/detail/unrelated/quality fixtures; reviewed labels where available.

**Steps**

1. Upload the specified photo set.
2. Read warnings.
3. Submit through permitted review path.
4. Inspect admin result.

**Expected:** No guaranteed authenticity; uncertain type/risk visible and reviewable; actual false matches/misses recorded separately.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L05-01 | Overview | Not run |
| P1-L05-02 | Detail | Not run |
| P1-L05-03 | Unrelated object | Not run |
| P1-L05-04 | Screenshot | Not run |
| P1-L05-05 | Duplicate image | Not run |
| P1-L05-06 | Poor quality | Not run |
| P1-L05-07 | Unsupported class | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L06 — Pricing inputs, explicit application and lineage

**Module:** Listing Management · **Actors:** Owner A

**Preconditions:** Valid product profile; initially empty daily price.

**Steps**

1. Request suggestion.
2. Vary one input at a time.
3. Change product while request pending.
4. Apply price.
5. Edit it and reopen draft.

**Expected:** Compatible evidence; stale response ignored; no automatic overwrite; apply hides card; edited AI price retains lineage.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L06-01 | Empty price | Not run |
| P1-L06-02 | Brand/model change | Not run |
| P1-L06-03 | Condition | Not run |
| P1-L06-04 | Age 0/1/3/5/8 | Not run |
| P1-L06-05 | Duration 1/2/3/7 | Not run |
| P1-L06-06 | Package | Not run |
| P1-L06-07 | Apply | Not run |
| P1-L06-08 | Edit/reopen | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L07 — Pricing gaps and safe fallback

**Module:** Listing Management · **Actors:** Owner A

**Preconditions:** Isolated evidence/source/AI fixtures; preserve deployed artifact.

**Steps**

1. Request for specified evidence state.
2. Inspect explanation, counts, fallback and retry.
3. Enter manual price.

**Expected:** Honest rough/unavailable state; no contaminated clean counts; no unsupported exact-model claim.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L07-01 | No evidence | Not run |
| P1-L07-02 | Incompatible evidence | Not run |
| P1-L07-03 | Disabled source | Not run |
| P1-L07-04 | AI unavailable | Not run |
| P1-L07-05 | Demo/AI/unknown excluded | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L08 — Availability, delivery and promotions

**Module:** Listing Management · **Actors:** Owner A, Renter B

**Preconditions:** Physical/service examples and valid price; permitted metadata bundle.

**Steps**

1. Block availability.
2. Set fixed delivery fee.
3. Configure promotion dates/rate.
4. Inspect quotes.
5. Edit supported bundle metadata.

**Expected:** Availability respected; fee explicit before checkout; valid effective discount; no unsupported multi-item checkout.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L08-01 | Availability | Not run |
| P1-L08-02 | Delivery fee | Not run |
| P1-L08-03 | Promotion active | Not run |
| P1-L08-04 | Promotion outside dates | Not run |
| P1-L08-05 | Invalid discount | Not run |
| P1-L08-06 | Bundle metadata | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L09 — Search, filters and view state

**Module:** Listing Management · **Actors:** Renter B

**Preconditions:** Several result pages and known filter matches.

**Steps**

1. Type/select/clear search.
2. Filter and sort.
3. Change swipe/grid/list view and page.
4. Open details and return Home.

**Expected:** Correct retained query/context; accurate totals and pages; no past-date clutter or stale response replacement.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L09-01 | Suggestions | Not run |
| P1-L09-02 | Clear | Not run |
| P1-L09-03 | Combined filters | Not run |
| P1-L09-04 | Sorting | Not run |
| P1-L09-05 | View modes | Not run |
| P1-L09-06 | Later pages | Not run |
| P1-L09-07 | Back to Home | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L10 — Wishlist and restricted comparison

**Module:** Listing Management · **Actors:** Renter B

**Preconditions:** Three same-domain physical items plus incompatible/service examples.

**Steps**

1. Save/remove favourites.
2. Add compatible comparisons.
3. Try fourth and incompatible items.
4. Confirm/cancel replacement.
5. Open legacy invalid selection.

**Expected:** Selected controls; max three same category/subcategory physical items; explicit recovery; no silent write.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L10-01 | Wishlist | Not run |
| P1-L10-02 | Compatible three | Not run |
| P1-L10-03 | Fourth | Not run |
| P1-L10-04 | Wrong subcategory | Not run |
| P1-L10-05 | Service | Not run |
| P1-L10-06 | Manual product | Not run |
| P1-L10-07 | Replace/cancel | Not run |
| P1-L10-08 | Legacy recovery | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L11 — Four recommendation sections

**Module:** Listing Management · **Actors:** Renter B

**Preconditions:** Eligible listings and separate sparse-history/AI-error fixtures.

**Steps**

1. Open each section.
2. Open related details.
3. Test independent empty/loading/error and See all.
4. Inspect complementary eligibility.

**Expected:** Eligible honest recommendations; isolated section failures; no fake popularity/compatibility; fallback labelled.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L11-01 | Recommended For You | Not run |
| P1-L11-02 | Trending Near You | Not run |
| P1-L11-03 | Recently Viewed | Not run |
| P1-L11-04 | You Might Also Need | Not run |
| P1-L11-05 | Cold start | Not run |
| P1-L11-06 | AI unavailable | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-L12 — Behavior refresh and browsing privacy

**Module:** Listing Management · **Actors:** Renter B

**Preconditions:** Same-account successful feed; controlled delayed response.

**Steps**

1. View/save/book.
2. Return Home.
3. Pull refresh.
4. Resume after 60 seconds.
5. Clear history.
6. Change account/location during request.

**Expected:** Coalesced fresh results; genuine activity rules; deduped history; old private responses ignored.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-L12-01 | View/save/book | Not run |
| P1-L12-02 | Home return | Not run |
| P1-L12-03 | Foreground stale | Not run |
| P1-L12-04 | Clear history | Not run |
| P1-L12-05 | Account change | Not run |
| P1-L12-06 | Location change | Not run |
| P1-L12-07 | Failure retained data | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P1-B01 — Booking search and focused details

**Module:** Booking Management · **Actors:** Owner A, Renter B

**Preconditions:** Multiple pages per role; selected filters.

**Steps**

1. Search/filter/sort/page independently.
2. Open View details and focused notification.
3. Refresh and return.

**Expected:** Status first; correct actions and count; retained role-specific filters; focus does not contaminate lists.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-B01-01 | Renter | Not run |
| P1-B01-02 | Owner | Not run |
| P1-B01-03 | Pagination | Not run |
| P1-B01-04 | Focused notification | Not run |
| P1-B01-05 | Refresh failure | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P1-B02 — Pickup, delivery and service venue

**Module:** Booking Management · **Actors:** Owner A, Renter B

**Preconditions:** Pinned saved/new addresses and service venue modes.

**Steps**

1. Choose fulfilment/venue.
2. Confirm required destination.
3. Review server charges and location snapshots.
4. Cancel picker once.

**Expected:** Conditional location/pin rules; explicit delivery fee; online needs no physical destination; cancel preserves draft.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-B02-01 | Pickup | Not run |
| P1-B02-02 | Owner delivery saved | Not run |
| P1-B02-03 | Owner delivery new | Not run |
| P1-B02-04 | Owner venue | Not run |
| P1-B02-05 | Renter venue | Not run |
| P1-B02-06 | Flexible | Not run |
| P1-B02-07 | Online | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [precise-locations.test.js](../../services/api/test/precise-locations.test.js), [booking_role_isolation_test.dart](../../apps/renthub_flutter/test/booking_role_isolation_test.dart).

### P1-B03 — Independent lifecycle reminders and deadlines

**Module:** Rental Management · **Actors:** Owner A, Renter B

**Preconditions:** Controlled-time fixtures and enabled scheduler for device delivery.

**Steps**

1. Run due/overdue and expiry boundary variants.
2. Repeat jobs.
3. Read status/notifications.

**Expected:** Malaysia day boundaries; notices deduplicated; paid Owner deadline and extension quote not confused with ten-minute initial checkout.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-B03-01 | Return reminder | Not run |
| P1-B03-02 | Overdue | Not run |
| P1-B03-03 | Extension expiry | Not run |
| P1-B03-04 | Paid Owner expiry | Not run |
| P1-B03-05 | Job replay | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [live_extension_checkout_test.dart](../../apps/renthub_flutter/test/live_extension_checkout_test.dart), [RentalAgreement.test.js](../../blockchain/test/RentalAgreement.test.js).

### P1-B04 — Transactions and earnings history

**Module:** Payment Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Saved initial/extension/refund ledger fixtures.

**Steps**

1. Open as payer/recipient/admin.
2. Page/filter.
3. Read breakdown and reconciliation.
4. Check legacy missing facts.

**Expected:** Saved amounts and simulation labels; correct totals/held balance; no invented historical names or charges.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-B04-01 | Payer | Not run |
| P1-B04-02 | Recipient | Not run |
| P1-B04-03 | Admin | Not run |
| P1-B04-04 | Extension | Not run |
| P1-B04-05 | Partial refund | Not run |
| P1-B04-06 | Legacy missing data | Not run |

**Relevant regression suites:** [payment.test.js](../../services/api/test/payment.test.js), [checkout_agreement.test.js](../../services/api/test/checkout_agreement.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [payment_window_ui_test.dart](../../apps/renthub_flutter/test/payment_window_ui_test.dart).

### P1-C01 — One peer conversation across bookings

**Module:** Communication Management · **Actors:** Owner A, Renter B

**Preconditions:** Several historical booking threads for same pair.

**Steps**

1. Open Messages and each booking chat.
2. Inspect peer rows/history/unread.
3. Switch roles.

**Expected:** One authorized peer row; combined exact-pair history; preserved booking context and unread counts.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C01-01 | Several bookings | Not run |
| P1-C01-02 | Role switch | Not run |
| P1-C01-03 | Closed plus open thread | Not run |
| P1-C01-04 | Fully closed conversation | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-C02 — Chat sends and cursor history

**Module:** Communication Management · **Actors:** Owner A, Renter B

**Preconditions:** Two signed-in sessions; long chat; permissioned attachment.

**Steps**

1. Send specified message.
2. Load earlier history during incoming messages.
3. Disconnect/reconnect.
4. Retry explicitly after failure.

**Expected:** Correct recipient; no gaps/duplicate IDs; retained draft; protected files.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C02-01 | Text | Not run |
| P1-C02-02 | Photo | Not run |
| P1-C02-03 | Location | Not run |
| P1-C02-04 | Earlier history | Not run |
| P1-C02-05 | Concurrent incoming | Not run |
| P1-C02-06 | Network recovery | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-C03 — Timed message actions

**Module:** Communication Management · **Actors:** Owner A, Renter B

**Preconditions:** Own/received text and media; controlled 15-minute boundary.

**Steps**

1. Long press or right-click.
2. Edit/recall/delete as variant.
3. Replay older socket event.
4. Read other participant.

**Expected:** Own edit/recall within server window only; delete affects actor only; recalled placeholder; no restoration/leaked old content.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C03-01 | Edit timely | Not run |
| P1-C03-02 | Edit too late | Not run |
| P1-C03-03 | Recall timely | Not run |
| P1-C03-04 | Recall too late | Not run |
| P1-C03-05 | Delete for me | Not run |
| P1-C03-06 | Foreign action | Not run |
| P1-C03-07 | Old event replay | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-C04 — Profile, block and message report

**Module:** Communication Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Existing conversation and dedicated report target.

**Steps**

1. Tap header.
2. Block/unblock.
3. Try messaging via another thread.
4. Report message.
5. Review preserved evidence.

**Expected:** Safe correct profile; blocking cannot be bypassed; report snapshot retained; no interview feature.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C04-01 | Header profile | Not run |
| P1-C04-02 | Block | Not run |
| P1-C04-03 | Unblock | Not run |
| P1-C04-04 | Report | Not run |
| P1-C04-05 | Closed thread | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-C05 — Notification destinations and safe fallback

**Module:** Communication Management · **Actors:** Owner A, Renter B

**Preconditions:** Notifications for existing and inaccessible/deleted targets.

**Steps**

1. Tap type-specific notice.
2. Repeat tap.
3. Simulate failed mark-read.
4. Open inaccessible target.

**Expected:** Correct protected focused record or readable fallback; no business mutation; no duplicate navigation.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C05-01 | Booking | Not run |
| P1-C05-02 | Payment | Not run |
| P1-C05-03 | Chat | Not run |
| P1-C05-04 | Dispute/claim | Not run |
| P1-C05-05 | Reward | Not run |
| P1-C05-06 | Verification | Not run |
| P1-C05-07 | Repeated tap | Not run |
| P1-C05-08 | Missing target | Not run |
| P1-C05-09 | Read-update failure | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-C06 — Notification records and Android delivery

**Module:** Communication Management · **Actors:** Owner A, Renter B

**Preconditions:** Registered Android device and dedicated notices; permission variants.

**Steps**

1. Filter/page.
2. Read/remove/clear.
3. Receive foreground/background/cold-start push.
4. Tap after session change.

**Expected:** Correct unread/totals; safe confirmations; actual device delivery evidence kept separate from provider acceptance.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-C06-01 | Filters/pages | Not run |
| P1-C06-02 | Read | Not run |
| P1-C06-03 | Remove | Not run |
| P1-C06-04 | Clear | Not run |
| P1-C06-05 | Foreground | Not run |
| P1-C06-06 | Background | Not run |
| P1-C06-07 | Cold start | Not run |
| P1-C06-08 | Permission denied | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P1-V01 — Completion-gated participant reviews

**Module:** Review Management · **Actors:** Owner A, Renter B, Renter C

**Preconditions:** Unfinished/completed rentals and existing review.

**Steps**

1. Submit as specified actor/state.
2. Try duplicate and direct API bypass.
3. Read published review.

**Expected:** Only eligible completed participant; no duplicate or foreign review.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-V01-01 | Before completion | Not run |
| P1-V01-02 | After completion | Not run |
| P1-V01-03 | Unrelated user | Not run |
| P1-V01-04 | Duplicate | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [trust_service.test.js](../../services/api/test/trust_service.test.js).

### P1-V02 — Review edit window and validation

**Module:** Review Management · **Actors:** Owner A, Renter B

**Preconditions:** Own review and controlled 24-hour boundary; service review.

**Steps**

1. Edit timely/late.
2. Enter invalid ratings/text.
3. Review service-specific aspects.

**Expected:** Correct time/validation; no physical-only service aspects.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-V02-01 | Within 24 hours | Not run |
| P1-V02-02 | After 24 hours | Not run |
| P1-V02-03 | Invalid values | Not run |
| P1-V02-04 | Service aspects | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [trust_service.test.js](../../services/api/test/trust_service.test.js).

### P1-V03 — Review flag, moderation and aggregates

**Module:** Review Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Published review and recorded aggregate baseline.

**Steps**

1. Flag.
2. Moderate.
3. Refresh listing/Owner rating and trust.
4. Restore permitted visibility.

**Expected:** Correct visibility/derived updates; no substitution of listing rating for Owner rating.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-V03-01 | Flag | Not run |
| P1-V03-02 | Hide | Not run |
| P1-V03-03 | Restore | Not run |
| P1-V03-04 | Aggregate refresh | Not run |

**Relevant regression suites:** [booking_rental.test.js](../../services/api/test/booking_rental.test.js), [trust_service.test.js](../../services/api/test/trust_service.test.js).

### P1-D01 — Dispute evidence and readable history

**Module:** Dispute Management · **Actors:** Owner A, Renter B

**Preconditions:** Open case and owned evidence; no real identity attachments.

**Steps**

1. Upload/remove draft attachment.
2. Respond.
3. Reload as both sides.
4. Try foreign evidence.
5. Inspect history.

**Expected:** Ownership/access; retained responses; readable dates/copy; no user-facing internal chain IDs/errors.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-D01-01 | Evidence upload | Not run |
| P1-D01-02 | Remove draft evidence | Not run |
| P1-D01-03 | Participant response | Not run |
| P1-D01-04 | Foreign file | Not run |
| P1-D01-05 | History | Not run |

**Relevant regression suites:** [dispute.test.js](../../services/api/test/dispute.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [dispute_completion_cutoff_test.dart](../../apps/renthub_flutter/test/dispute_completion_cutoff_test.dart).

### P1-D02 — Closed case and dismissal history

**Module:** Dispute Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Separate resolved and dismissed fixtures.

**Steps**

1. Resolve/dismiss.
2. Reopen history.
3. Try prohibited response/new case.
4. Inspect ledger and evidence.

**Expected:** Saved decision and existing-state rules; no erased evidence, duplicate allocation or post-completion new case.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-D02-01 | Resolved | Not run |
| P1-D02-02 | Dismissed | Not run |
| P1-D02-03 | Repeated decision | Not run |
| P1-D02-04 | Closed response | Not run |
| P1-D02-05 | New-case attempt | Not run |

**Relevant regression suites:** [dispute.test.js](../../services/api/test/dispute.test.js), [financial-recovery.test.js](../../services/api/test/financial-recovery.test.js), [dispute_completion_cutoff_test.dart](../../apps/renthub_flutter/test/dispute_completion_cutoff_test.dart).

### P1-Y01 — Idempotent completion points

**Module:** Loyalty and Referral Management · **Actors:** Renter B

**Preconditions:** Eligible staged completion and known reward settings.

**Steps**

1. Complete fixture.
2. Read balance/history.
3. Repeat refresh/recovery/trigger.

**Expected:** Configured points once; ledger and balance agree.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-Y01-01 | First award | Not run |
| P1-Y01-02 | Repeated trigger | Not run |
| P1-Y01-03 | Recovery | Not run |

**Relevant regression suites:** [loyalty.test.js](../../services/api/test/loyalty.test.js), [live_role_referral_test.dart](../../apps/renthub_flutter/test/live_role_referral_test.dart).

### P1-Y02 — Configured redemption

**Module:** Loyalty and Referral Management · **Actors:** Renter B

**Preconditions:** Dedicated balance with sufficient/insufficient variants.

**Steps**

1. Choose permitted reward.
2. Submit valid/invalid amount.
3. Retry matching attempt.

**Expected:** No negative balance or duplicate redemption; configured choices only.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-Y02-01 | Valid | Not run |
| P1-Y02-02 | Invalid option | Not run |
| P1-Y02-03 | Insufficient points | Not run |
| P1-Y02-04 | Repeated request | Not run |

**Relevant regression suites:** [loyalty.test.js](../../services/api/test/loyalty.test.js), [live_role_referral_test.dart](../../apps/renthub_flutter/test/live_role_referral_test.dart).

### P1-Y03 — Referral qualification and first completion

**Module:** Loyalty and Referral Management · **Actors:** Owner A, User D

**Preconditions:** Fresh referee before first qualifying completion; separate accounts.

**Steps**

1. Apply specified code.
2. Inspect pending progress.
3. Complete first eligible booking.
4. Repeat trigger.

**Expected:** No self/repeated referral; correct progress; rewards once at configured completion trigger.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-Y03-01 | Valid | Not run |
| P1-Y03-02 | Invalid | Not run |
| P1-Y03-03 | Self | Not run |
| P1-Y03-04 | Already applied | Not run |
| P1-Y03-05 | First completion | Not run |
| P1-Y03-06 | Repeated completion | Not run |

**Relevant regression suites:** [loyalty.test.js](../../services/api/test/loyalty.test.js), [live_role_referral_test.dart](../../apps/renthub_flutter/test/live_role_referral_test.dart).

### P1-Y04 — Paused programme and admin reward history

**Module:** Loyalty and Referral Management · **Actors:** Admin M, User D

**Preconditions:** Pending referral and captured baseline settings in staging.

**Steps**

1. Pause programme.
2. Complete/read pending flow.
3. Resume.
4. Inspect ledger/referrals.
5. Restore test settings.

**Expected:** Pending retained; correct once-only eligibility; no invented retrospective rewards.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-Y04-01 | Pause | Not run |
| P1-Y04-02 | Resume | Not run |
| P1-Y04-03 | Admin ledger | Not run |
| P1-Y04-04 | Admin referral history | Not run |

**Relevant regression suites:** [loyalty.test.js](../../services/api/test/loyalty.test.js), [live_role_referral_test.dart](../../apps/renthub_flutter/test/live_role_referral_test.dart).

### P1-A01 — Independent administrator sections

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** All ten destinations with fixture data.

**Steps**

1. Open each destination.
2. Switch quickly between record types.
3. Delay/fail one request.

**Expected:** Independent retained records/loading/errors; no disappearing or wrong collection.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A01-01 | All destinations | Not run |
| P1-A01-02 | Rapid switch | Not run |
| P1-A01-03 | Section failure | Not run |
| P1-A01-04 | Account change | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A02 — Every administrator detail type

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** Safe representative record per registered type.

**Steps**

1. Open by primary label and View details.
2. Inspect facts/history/evidence.
3. Close without action.

**Expected:** Correct record and projection; missing facts explicit; viewing alone changes no business state.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A02-01 | users | Not run |
| P1-A02-02 | verification | Not run |
| P1-A02-03 | listings | Not run |
| P1-A02-04 | bookings | Not run |
| P1-A02-05 | rentals | Not run |
| P1-A02-06 | transactions | Not run |
| P1-A02-07 | disputes | Not run |
| P1-A02-08 | claims | Not run |
| P1-A02-09 | user reports | Not run |
| P1-A02-10 | listing reports | Not run |
| P1-A02-11 | review reports | Not run |
| P1-A02-12 | message reports | Not run |
| P1-A02-13 | reviews | Not run |
| P1-A02-14 | audit logs | Not run |
| P1-A02-15 | generated reports | Not run |
| P1-A02-16 | report schedules | Not run |
| P1-A02-17 | referrals | Not run |
| P1-A02-18 | reward history | Not run |
| P1-A02-19 | rental-price references | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A03 — Real server pagination and summary totals

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** More than 50 matching records; stable equal-sort fixtures.

**Steps**

1. Filter before paging.
2. Change 10/20/50 size.
3. Read later pages.
4. Remove/moderate final-page record.
5. Read dashboard.

**Expected:** Accurate filtered totals; stable no-gap order; nearest valid page; totals independent of page length.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A03-01 | Search/filter | Not run |
| P1-A03-02 | Page sizes | Not run |
| P1-A03-03 | Later page | Not run |
| P1-A03-04 | Equal sort | Not run |
| P1-A03-05 | Empty final page | Not run |
| P1-A03-06 | Dashboard totals | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A04 — Confirmed moderation and reasons

**Module:** Admin Management · **Actors:** Admin M, Restricted user

**Preconditions:** Expendable staging account/listing/review/reports.

**Steps**

1. Open action.
2. Cancel.
3. Retry without reason.
4. Confirm valid reason.
5. Reload list/detail/totals.

**Expected:** Permission/confirmation/reason enforced; correct state and retained filters.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A04-01 | Suspend | Not run |
| P1-A04-02 | Ban | Not run |
| P1-A04-03 | Reactivate | Not run |
| P1-A04-04 | Listing decision | Not run |
| P1-A04-05 | Review moderation | Not run |
| P1-A04-06 | Report decision | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A05 — Read-only system status versus task run

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** Controlled due jobs; baseline counts.

**Steps**

1. Refresh status.
2. Verify unchanged business data.
3. Confirm scheduled tasks.
4. Read actual result/partial failure.

**Expected:** Status refresh read-only; task run separately confirmed and affects eligible records only.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A05-01 | Refresh | Not run |
| P1-A05-02 | Task confirmation cancelled | Not run |
| P1-A05-03 | Task run | Not run |
| P1-A05-04 | Partial integration failure | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A06 — Price sources and advanced CSV fallback

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** Staging approved source fixtures and bounded explicit-MYR CSV; no new source permissions.

**Steps**

1. List references.
2. Refresh/toggle existing approved source.
3. Preview CSV.
4. Confirm valid/invalid import.
5. Repeat and deactivate.

**Expected:** No preview writes; whole-file validation; dedupe; prior valid rows preserved; disable/deactivation respected.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A06-01 | Saved prices | Not run |
| P1-A06-02 | Update | Not run |
| P1-A06-03 | Disable | Not run |
| P1-A06-04 | Enable eligible | Not run |
| P1-A06-05 | Source failure | Not run |
| P1-A06-06 | CSV preview | Not run |
| P1-A06-07 | Invalid file | Not run |
| P1-A06-08 | Confirm/repeat import | Not run |
| P1-A06-09 | Deactivate | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A07 — Reports and schedules

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** Dedicated report dataset and schedule; non-overwriting export path.

**Steps**

1. Generate filtered report.
2. Download.
3. Create/edit/disable schedule.
4. Run due job twice.
5. Inspect audit.

**Expected:** Correct authorized safe export; matching counts; no duplicate scheduled output.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A07-01 | Generate | Not run |
| P1-A07-02 | Download | Not run |
| P1-A07-03 | Create schedule | Not run |
| P1-A07-04 | Edit | Not run |
| P1-A07-05 | Disable | Not run |
| P1-A07-06 | Repeated job | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P1-A08 — Supported settings and append-only audit

**Module:** Admin Management · **Actors:** Admin M

**Preconditions:** Snapshot staging settings; no secrets in form.

**Steps**

1. Edit valid/invalid supported settings.
2. Inspect Malaysia dates and readable activity.
3. Try audit mutation/foreign access.
4. Restore settings.

**Expected:** Validation; no obsolete passport UI; private-safe append-only audit; no raw ISO dates.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P1-A08-01 | Valid settings | Not run |
| P1-A08-02 | Invalid settings | Not run |
| P1-A08-03 | Readable dates | Not run |
| P1-A08-04 | Audit read | Not run |
| P1-A08-05 | Audit mutation denied | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P2-01 — Responsive and accessible interfaces

**Module:** Admin Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Exact tested build and supported surfaces.

**Steps**

1. Run major forms/cards/dialogs at specified viewport/text scale.
2. Navigate keyboard/focus.
3. Try long content.

**Expected:** No overflow/inaccessible actions, stacked cramped buttons or inner scrolling cards; readable focus/status.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-01-01 | Android 360 | Not run |
| P2-01-02 | Android 390 | Not run |
| P2-01-03 | Windows | Not run |
| P2-01-04 | Admin 1024 | Not run |
| P2-01-05 | Admin 1440 | Not run |
| P2-01-06 | Text scale 1.5 | Not run |
| P2-01-07 | Keyboard | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

### P2-02 — Empty, loading and unavailable states

**Module:** User Management · **Actors:** All test actors

**Preconditions:** Controlled empty/error/deleted-record fixtures.

**Steps**

1. Open each collection under specified state.
2. Retry.
3. Inspect previously successful results and diagnostics.

**Expected:** Friendly recovery; no false empty success, raw exception/URL/path/ISO timestamp or private-cache leak.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-02-01 | Empty | Not run |
| P2-02-02 | Loading | Not run |
| P2-02-03 | Unavailable | Not run |
| P2-02-04 | Deleted | Not run |
| P2-02-05 | Retry | Not run |
| P2-02-06 | Retained result | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P2-03 — Cross-form input boundaries

**Module:** User Management · **Actors:** All test actors

**Preconditions:** Current UI/API authoritative validation limits.

**Steps**

1. Type and paste invalid numeric/text values.
2. Delete/compose Unicode.
3. Submit boundaries.
4. Bypass UI via API.

**Expected:** Invalid edit rejected without changing meaning; finite/range/precision rules; Unicode/model numbers and string codes preserved.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-03-01 | Letters in numeric | Not run |
| P2-03-02 | Scientific notation | Not run |
| P2-03-03 | Fractional whole | Not run |
| P2-03-04 | Money precision | Not run |
| P2-03-05 | Unicode | Not run |
| P2-03-06 | Leading zeros | Not run |
| P2-03-07 | Boundary range | Not run |
| P2-03-08 | Keyboard composition | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P2-04 — Map permission and precision recovery

**Module:** Listing Management · **Actors:** Owner A, Renter B

**Preconditions:** Android GPS and public search; private draft.

**Steps**

1. Request GPS only by tap.
2. Exercise denial/timeout/coarse reading.
3. Search and adjust pin.
4. Cancel/retry.

**Expected:** Clear accuracy/recovery; retained draft; no guessed private unit/postcode; explicit final pin confirmation.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-04-01 | Denied | Not run |
| P2-04-02 | Permanent denial | Not run |
| P2-04-03 | GPS off | Not run |
| P2-04-04 | Timeout | Not run |
| P2-04-05 | Approximate | Not run |
| P2-04-06 | Search failure | Not run |
| P2-04-07 | Pin adjustment | Not run |
| P2-04-08 | Cancel | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P2-05 — Launcher and two-device continuity

**Module:** User Management · **Actors:** Owner A, Renter B

**Preconditions:** Both configured laptops; same Atlas/storage; native credentials remain local.

**Steps**

1. Launch each independently.
2. Reconnect USB/wireless.
3. Change Wi-Fi and rerun.
4. Check shared records/photos and service ownership.

**Expected:** Documented recovery; no daily personal browser-login requirement for configured automation; no unrelated process termination.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-05-01 | USB reconnect | Not run |
| P2-05-02 | Wireless | Not run |
| P2-05-03 | Wi-Fi change | Not run |
| P2-05-04 | Second laptop | Not run |
| P2-05-05 | Services-only | Not run |
| P2-05-06 | Port conflict | Not run |

**Relevant regression suites:** [user.test.js](../../services/api/test/user.test.js), [identity_access.test.js](../../services/api/test/identity_access.test.js), [identity_binding.test.js](../../services/api/test/identity_binding.test.js), [mykad_readability.test.js](../../services/api/test/mykad_readability.test.js), [live_auth_contract_test.dart](../../apps/renthub_flutter/test/live_auth_contract_test.dart).

### P2-06 — Unavailable AI/catalogue and artifact preservation

**Module:** Listing Management · **Actors:** Owner A, Admin M

**Preconditions:** Isolated unavailable/stale responses; deployed checksum baseline.

**Steps**

1. Request assistance with missing model/provider/evidence.
2. Change context during response.
3. Inspect manual paths.
4. Compare artifact checksums.

**Expected:** Honest unavailable/advisory state; usable manual fallback; no invented confidence/product/price; artifacts unchanged.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-06-01 | Missing AI | Not run |
| P2-06-02 | Provider error | Not run |
| P2-06-03 | Stale response | Not run |
| P2-06-04 | No price evidence | Not run |
| P2-06-05 | Artifact check | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P2-07 — Reviewed all-category image evaluation

**Module:** Listing Management · **Actors:** Owner A, Admin M

**Preconditions:** Existing private 198-slot review kit; separate permissioned evaluation items; no fabricated boxes/labels.

**Steps**

1. Collect/review planned whole/alternate/detail/unrelated cases.
2. Run detector, World and hybrid evaluation.
3. Separate risk cohort only where labels exist.

**Expected:** Report misses/false matches/unavailable separately; incomplete cases remain incomplete; unknown manipulation accuracy stays Not evaluated.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-07-01 | Devices / Smartphones / whole and alternate views | Not run |
| P2-07-02 | Devices / Smartphones / detail views | Not run |
| P2-07-03 | Devices / Smartphones / unrelated views | Not run |
| P2-07-04 | Devices / Cameras / whole and alternate views | Not run |
| P2-07-05 | Devices / Cameras / detail views | Not run |
| P2-07-06 | Devices / Cameras / unrelated views | Not run |
| P2-07-07 | Devices / Computers / whole and alternate views | Not run |
| P2-07-08 | Devices / Computers / detail views | Not run |
| P2-07-09 | Devices / Computers / unrelated views | Not run |
| P2-07-10 | Devices / Audio / whole and alternate views | Not run |
| P2-07-11 | Devices / Audio / detail views | Not run |
| P2-07-12 | Devices / Audio / unrelated views | Not run |
| P2-07-13 | Devices / Gaming / whole and alternate views | Not run |
| P2-07-14 | Devices / Gaming / detail views | Not run |
| P2-07-15 | Devices / Gaming / unrelated views | Not run |
| P2-07-16 | Devices / Other devices / whole and alternate views | Not run |
| P2-07-17 | Devices / Other devices / detail views | Not run |
| P2-07-18 | Devices / Other devices / unrelated views | Not run |
| P2-07-19 | Vehicles / Cars / whole and alternate views | Not run |
| P2-07-20 | Vehicles / Cars / detail views | Not run |
| P2-07-21 | Vehicles / Cars / unrelated views | Not run |
| P2-07-22 | Vehicles / Motorcycles / whole and alternate views | Not run |
| P2-07-23 | Vehicles / Motorcycles / detail views | Not run |
| P2-07-24 | Vehicles / Motorcycles / unrelated views | Not run |
| P2-07-25 | Vehicles / Bicycles / whole and alternate views | Not run |
| P2-07-26 | Vehicles / Bicycles / detail views | Not run |
| P2-07-27 | Vehicles / Bicycles / unrelated views | Not run |
| P2-07-28 | Vehicles / Other vehicles / whole and alternate views | Not run |
| P2-07-29 | Vehicles / Other vehicles / detail views | Not run |
| P2-07-30 | Vehicles / Other vehicles / unrelated views | Not run |
| P2-07-31 | Equipment / Tools / whole and alternate views | Not run |
| P2-07-32 | Equipment / Tools / detail views | Not run |
| P2-07-33 | Equipment / Tools / unrelated views | Not run |
| P2-07-34 | Equipment / Sports equipment / whole and alternate views | Not run |
| P2-07-35 | Equipment / Sports equipment / detail views | Not run |
| P2-07-36 | Equipment / Sports equipment / unrelated views | Not run |
| P2-07-37 | Equipment / Event equipment / whole and alternate views | Not run |
| P2-07-38 | Equipment / Event equipment / detail views | Not run |
| P2-07-39 | Equipment / Event equipment / unrelated views | Not run |
| P2-07-40 | Equipment / Other equipment / whole and alternate views | Not run |
| P2-07-41 | Equipment / Other equipment / detail views | Not run |
| P2-07-42 | Equipment / Other equipment / unrelated views | Not run |
| P2-07-43 | Books / Textbooks / whole and alternate views | Not run |
| P2-07-44 | Books / Textbooks / detail views | Not run |
| P2-07-45 | Books / Textbooks / unrelated views | Not run |
| P2-07-46 | Books / Reference books / whole and alternate views | Not run |
| P2-07-47 | Books / Reference books / detail views | Not run |
| P2-07-48 | Books / Reference books / unrelated views | Not run |
| P2-07-49 | Books / Fiction / whole and alternate views | Not run |
| P2-07-50 | Books / Fiction / detail views | Not run |
| P2-07-51 | Books / Fiction / unrelated views | Not run |
| P2-07-52 | Books / Other books / whole and alternate views | Not run |
| P2-07-53 | Books / Other books / detail views | Not run |
| P2-07-54 | Books / Other books / unrelated views | Not run |
| P2-07-55 | Clothing / Formal wear / whole and alternate views | Not run |
| P2-07-56 | Clothing / Formal wear / detail views | Not run |
| P2-07-57 | Clothing / Formal wear / unrelated views | Not run |
| P2-07-58 | Clothing / Costumes / whole and alternate views | Not run |
| P2-07-59 | Clothing / Costumes / detail views | Not run |
| P2-07-60 | Clothing / Costumes / unrelated views | Not run |
| P2-07-61 | Clothing / Traditional wear / whole and alternate views | Not run |
| P2-07-62 | Clothing / Traditional wear / detail views | Not run |
| P2-07-63 | Clothing / Traditional wear / unrelated views | Not run |
| P2-07-64 | Clothing / Other clothing / whole and alternate views | Not run |
| P2-07-65 | Clothing / Other clothing / detail views | Not run |
| P2-07-66 | Clothing / Other clothing / unrelated views | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P2-08 — Independent price and recommendation evidence

**Module:** Listing Management · **Actors:** Consented testers

**Preconditions:** Reviewed prices, consent and provenance; frozen model baseline.

**Steps**

1. Collect testers' own activity/feedback.
2. Run non-deploying temporal evaluation.
3. Separate cohorts/baselines and sparse states.

**Expected:** Asking not achieved prices; staged not genuine activity; no data leakage or accuracy claim from function tests.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-08-01 | Reviewed asking prices | Not run |
| P2-08-02 | Genuine completed cohort | Not run |
| P2-08-03 | Staged cohort | Not run |
| P2-08-04 | Synthetic cohort | Not run |
| P2-08-05 | Cold start | Not run |
| P2-08-06 | Insufficient data | Not run |

**Relevant regression suites:** [listing.test.js](../../services/api/test/listing.test.js), [catalog-evidence.test.js](../../services/api/test/catalog-evidence.test.js), [pricing-suitability.test.js](../../services/api/test/pricing-suitability.test.js), [recommendation-scope.test.js](../../services/api/test/recommendation-scope.test.js), [evidence_product_selection_test.dart](../../apps/renthub_flutter/test/evidence_product_selection_test.dart).

### P2-09 — Long-record and performance observation

**Module:** Communication Management · **Actors:** All test actors

**Preconditions:** Long histories and known network conditions.

**Steps**

1. Repeat navigation/search/paging.
2. Measure warm/cold response times.
3. Exercise partial failure.
4. Inspect loading and stale-account behavior.

**Expected:** No stuck controls or wrong private data; timings/conditions reported; no invented speed threshold/pass.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-09-01 | Repeated navigation | Not run |
| P2-09-02 | Long chat | Not run |
| P2-09-03 | Search | Not run |
| P2-09-04 | Pagination | Not run |
| P2-09-05 | Cold start | Not run |
| P2-09-06 | Partial failure | Not run |

**Relevant regression suites:** [user_ui_messaging.test.js](../../services/api/test/user_ui_messaging.test.js), [notification-target.test.js](../../services/api/test/notification-target.test.js), [home_notification_recovery_test.dart](../../apps/renthub_flutter/test/home_notification_recovery_test.dart).

### P2-10 — Presentation rehearsal and restore

**Module:** Admin Management · **Actors:** Owner A, Renter B, Admin M

**Preconditions:** Dedicated backup/restore target and exact demo build; no restore over shared DB.

**Steps**

1. Rehearse isolated restore.
2. Verify records/photos/models.
3. Perform five-minute presentation and critical smoke sequence.
4. Record fallback.

**Expected:** Complete reproducible demo on intended equipment/network; explicit integration/AI limits; no fabricated results.

| Case ID | Independent variant | Initial status |
| --- | --- | --- |
| P2-10-01 | Isolated restore | Not run |
| P2-10-02 | Models/configuration | Not run |
| P2-10-03 | Five-minute rehearsal | Not run |
| P2-10-04 | Final smoke | Not run |
| P2-10-05 | Fallback | Not run |

**Relevant regression suites:** [admin_records.test.js](../../services/api/test/admin_records.test.js), [admin_reporting.test.js](../../services/api/test/admin_reporting.test.js), [pricing-references.test.js](../../services/api/test/pricing-references.test.js), [admin_usability_test.dart](../../apps/renthub_flutter/test/admin_usability_test.dart).

