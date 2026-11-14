# Trust, comparison and rental review improvements

Implemented 14 November 2026. Restart the API and rebuild/reopen Flutter together. No shared records, existing approvals, credentials or deployed AI artifacts were changed.

**Later update:** the text comparison and three-completion display described below are superseded by the [podium, compact trust and listing UI follow-up](PODIUM_TRUST_AND_LISTING_UI_RESULT.md). That follow-up shows a role score after the first qualifying completion and removes visible count breakdowns. Earlier verification below remains a historical run.

## What users see

| Area | Updated behaviour |
| --- | --- |
| Trust | The existing 0–100 calculation is displayed as a percentage in a circular indicator: **80–100 green**, **50–79 yellow**, **0–49 red**. Before the existing three-completion/two-partner threshold, it stays neutral and says **Building trust**. Unavailable scores are not shown as 0%. |
| Comparison | A balance/scales icon replaces the arrow icon. **Comparison at a glance** identifies the lowest daily price, lowest refundable deposit, highest published listing rating and best Owner-stated condition. Ties are explicit. Missing reviews/condition do not produce invented winners. There is no weighted overall winner or claim of product quality. Existing same-category/subcategory and three-item rules remain. |
| Listing details | **You might also need** is removed from the live details page. Its stored data and API remain available. |
| List cards | The photo information overlay is removed from list rows. Swipe/grid cards retain their accessible explanation control. |
| New dispute | The steps/checkmark panel is removed from the new-dispute form. The important case-review notice and existing-case progress/history remain. |
| Extensions | The date picker fetches current rental/availability data and disables reserved days **and dates beyond a reservation that the extension would cross**. Failed checks offer retry without opening an unchecked calendar. Server conflict checks remain authoritative. |
| Agreement | **Blockchain proof** is collapsed by default. Physical agreements can reveal saved contract/transaction references, saved state and recorded time. Missing references remain unavailable. Services do not imply physical blockchain coverage. |

Trust uses the same recorded-rentals scoring policy, roles, maturity threshold and simulated-payment disclosure. This is presentation of reputation, not a percentage probability of safety or authenticity. Original provenance and clean AI-evidence eligibility are unchanged.

## Pickup/delivery and return appointments

New physical bookings require both appointment times, stored as `pickupTime` and `returnTime` in strict **HH:mm**, with `appointmentTimezone = Asia/Kuala_Lumpur`. A same-day return must be later than pickup. Times join the booking idempotency fingerprint and are copied into the approved rental; changed times cannot replay a different booking under the same key.

The times appear with charges/checkout, agreements, rental progress and handover/return evidence. Historical date-only records show **Time not specified**. Services keep their existing scheduling. An extension preserves the original return appointment time.

These are coordination appointments. Charges still use inclusive rental days; availability still reserves whole days. Handover eligibility and Malaysian return/overdue deadlines are unchanged. No hourly billing, partial-day availability, time-based late fees or automatic changes to existing bookings were added.

## Private review documents

### Vehicle registration photo

- Required when submitting **Vehicles → Cars** or **Motorcycles**. Bicycles and Other vehicles do not require it. A missing/unknown specific vehicle category cannot bypass submission checks.
- Drafts may omit the photo. The shared camera/gallery picker allows one JPEG, PNG or WebP photo, using the existing private-document size limit (20 MB by default).
- `vehicleGrantRef` references an owned private upload with purpose `vehicle_grant`. It is separate from public item photos and is excluded from public listing responses by default.
- Only its uploader and authorized administrators can open it, including when an unrelated participant record happens to contain the reference. It is not a renter booking attachment.
- Admin details and approval show the registration photo. Approval requires explicit manual review; the saved review records the actual reference, administrator and time. Concurrent/stale moderation cannot approve a changed record. Replacing the photo/category invalidates its previous review.

### Person holding their MyKad

- New MyKad submissions require a separate `holderPhotoRef`, with private purpose `verification_holder_photo`, in addition to the two ordered front/back images.
- The photo should show the person's face and card together. It goes to **manual administrator review only**. It is not sent as a third card image to OCR, number matching or screen-copy screening. No face recognition, liveness model or government verification was added.
- Front/back readability, current-pair matching, duplicate-identity binding and all existing mandatory checks remain. Adding the holder photo cannot override a failed card check.
- Admin details/approval show this photo separately and require an explicit review confirmation. Review metadata is bound to the current pending attempt and retained by the atomic identity-approval operation.
- Only uploader/admin access is allowed. Attached current/history evidence is protected from deletion through the existing in-use checks. Failed uploads/submissions retain drafts; late holder selections cannot populate another document flow.

Existing approved identities and published vehicles are **not automatically revoked**. Existing pending submissions missing the newly required photo cannot be approved: administrators must reject/request resubmission, and the Owner/user supplies the missing document through the normal workflow. No bulk migration or historical acceptance was invented. Driving-licence processing remains separate.

## Interface and rollout notes

Existing endpoint paths remain. Additions are:

- Physical `POST /api/v1/bookings`: required `pickupTime` and `returnTime` for new requests; both are optional in stored historical models.
- Listing create/update: optional `vehicleGrantRef`; final Cars/Motorcycles submission requires it. Admin moderation adds `vehicleGrantReviewed: true` for approval.
- MyKad verification: separate `holderPhotoRef`; admin approval adds `holderPhotoReviewed: true` with the existing attempt identifier. Clients cannot supply the server-generated review actor/time.
- Uploads accept the two new private, image-only purposes. Limits and owner/purpose checks apply on both client and server; PDF and oversized uploads are rejected.
- Agreement retrieval adds an allowlisted `record.proof`. It contains stored hashes/addresses only, never RPC URLs, signing keys or raw provider errors.
- API health advertises `review-evidence-appointments-v1`. The launcher requires it so an older backend cannot silently skip these requirements. No AI/scanner contract change is needed for a manually reviewed holder photo.

The proof panel identifies a local demonstration blockchain when recorded as such. It is a display of saved references, **not a fresh receipt verification**, legal certification, wallet-ownership proof or protection of the entire agreement text. Use the existing developer blockchain checks for live receipt/state verification.

## Verification

- Full Flutter suite: **823 passed, 3 skipped, 0 failed**. Analysis: **No issues found**. Main web, administrator web and Android debug builds all succeeded. Private run: `.data/testing/20261114-132948-99f7d63b`.
- New focused widget checks: **21 passed**; an additional opt-in preview test also passed. They cover trust boundaries/semantics, comparison factors/ties/missing values, appointments/legacy dates, fresh extension constraints, missing/late holder photos, vehicle applicability and collapsed proof.
- Full serial API suite: **760 passed, 3 skipped, 0 failed** (763 total). Private log: `.data/testing/20261114-125824-4975df16/api-serial-final-privacy.log`. It covers appointment validation/idempotency/snapshots, legacy/service compatibility, all-category regression fixtures, grant ownership/purpose/applicability, manual review, replacement, protected deletion, holder separation from OCR, binding review persistence and safe proof output. Private-purpose upload tests also cover image-only enforcement, independent size limits and foreign/public access.
- All four launcher regression suites passed, including the readiness-capability check. Private run: `.data/testing/20261114-131918-1fa15fde`.
- Readable-font previews at 360/390/1024/1440 pixels and increased text size were generated and inspected. Holder/grant forms were also inspected at 390 pixels. Preview files stay in ignored app `.data/compact-trust-previews`; generation is opt-in with `RENTHUB_CAPTURE_TEST_UI=true` and the focused widget test.
- Deployed model/metrics checksums remained unchanged in the regression runner. No dependency, database migration, training, source enablement or live data cleanup was performed.

Existing non-blocking build notices remain: the socket.io dependency's WebAssembly dry-run compatibility warning, an optional Cupertino font reference and plugin Kotlin migration guidance. The requested JavaScript web builds and Android debug build succeeded. WebAssembly/plugin upgrades are outside this change.

The parallel full API runner intermittently waits during process cleanup on this machine; serial execution is used for the handoff. Earlier fixture failures were corrected to supply newly mandatory appointment/document inputs without weakening production checks. No unrelated Auth0 analyzer failures occurred in this run.

Real Android camera/gallery permissions, live protected storage, actual participant review, screen-reader interaction and receipt lookup remain device walkthrough checks. Successful builds and widget previews are not recorded as manual UAT passes.

## Short walkthrough

1. Restart using the normal launcher. Open an established Trust history and a new account: check coloured percentages versus neutral Building trust.
2. Compare compatible items with different prices, deposits, reviews and conditions. Check separate winners/ties. Open Home list view and a listing: no photo info overlay in list rows and no complementary section at the bottom.
3. Create a physical booking: choose dates plus both appointment times. A same-day return earlier than pickup must fail; daily charges remain unchanged. Confirm times in checkout/agreement. Check reserved-day/range blocking when extending an eligible rental.
4. Save an incomplete car draft. Submission requires its private registration photo. Admin must open it and confirm review before approval; another renter must not see it.
5. As an unverified test account, complete the existing MyKad front/back checks, add the holder photo, then submit. Admin reviews all three photos; only front/back go through card AI. Older pending records missing the holder photo need resubmission.
6. Open a physical agreement and expand Blockchain proof. Verify it shows saved references or an honest unavailable state. A service agreement must not imply physical-contract coverage.

## Commit message

```text
feat: improve trust, comparison and rental review evidence

- show trust percentages with accessible colour-coded circular indicators
- add factor-based comparison highlights and clearer comparison icons
- simplify listing and dispute screens and remove list-row info overlays
- require Malaysia pickup/return appointments without changing daily billing
- disable reserved and crossing date ranges in extension calendars
- reveal saved blockchain proof in a collapsed physical agreement section
- require private vehicle registration and MyKad holder review photos
- enforce upload ownership, manual review and stale-approval protection
- gate launcher readiness on the new API capability
- cover compatibility, privacy and presentation with regression tests
```
