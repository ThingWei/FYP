# Regular inventory preparation and booking usability

Updated 14 November 2026.

Later update: a separate regular JBL Go 4 listing has now been submitted with four catalogue photos and is awaiting actual Admin approval. The original 50 remain preparation. See [the latest cleanup and inventory result](CHECKOUT_REWARDS_AND_UI_CLEANUP_RESULT.md) for current status; the read-only preparation statements below describe the earlier phase.

## Delivered application changes

- Booking dates and pickup/return times now use separate padded selection cells. Rental dates, collection/return and fulfilment have distinct spacing. Existing calendar availability, inclusive rental days, charges and appointment payloads are unchanged.
- The listing Owner's name opens a full profile with a profile photo, name, identity status, trust and received reviews. Incoming Owner requests also offer **Renter profile**. Chat retains its existing profile entry point.
- Added authenticated `GET /api/v1/users/:id/profile`, including encoded Auth0 identifiers. It uses the existing account/block visibility policy and an explicit safe projection. It does not return phone numbers, emails, addresses, identity documents or fingerprints.
- Late profile responses are discarded after account changes or a new profile request. Profile/review failures retain their own recovery states.
- Both participants now see a separate **Return photos & condition** card when return evidence exists. It uses the renter's actual saved return photographs, condition, notes and submission time. Handover photos stay in their own section; appointments are not duplicated inside that gallery.
- Service duration is selected using presets and days/hours/minutes controls. Deposit and delivery charges use amount presets and bounded adjustments, including cents. All three fields are read-only; existing values and validation/payload rules remain authoritative. Closing a picker does not change the form.

## Inventory: prepared, not published

The Owner authorized 50 regular listings, a Good condition default and the most recent confirmed private listing pin. Preparation is stored privately under:

`services/api/.data/evidence/regular-owner-batch-2026-11-14/`

Files include `source-candidates.json`, `regular-batch-preview.json`, `INVENTORY-REVIEW.md`, photo metadata and a read-only preparation utility. These ignored files contain the detailed review data and are not committed.

The prepared selection contains 50 named product offers, using existing stored advertised one-day amounts of RM40–RM230 from RENTISM, Cilt Tech and ITPA. Coverage is 42 Cameras, 3 Computers, 2 Smartphones, 2 Gaming and 1 Other devices. This is a camera-heavy preparation batch, not coverage of all 22 subcategories. Prices describe those particular advertised packages; they do not establish a universal student-market price.

Condition is a provisional Owner-requested default, not an inspected condition finding. Item ages remain unknown. The confirmed pickup pin stays private. No public address is copied into this document.

### Remaining publication blocker

Bounded Wikimedia collection could not prepare a complete, model-matched photo set. Image requests were rejected/rate-limited, including after waiting and retrying. Two partially downloaded files are not a completed reviewed photo set. They have not been uploaded or used to publish listings. No access restriction was bypassed and no unrelated images were substituted.

**No live listings were inserted, removed, archived or published by this preparation.** The 64 active sample-source records identified by the read-only audit remain intact until replacements are ready. Existing bookings, rentals, reviews, payments and protected assets remain unchanged. The utility blocks `--apply` while photo/publication requirements are outstanding; it must not be used to archive the old inventory before usable replacements exist.

Completion requires usable model-matched photographs, confirmed item details and the normal listing submission/moderation workflow. The preview is not a claim that those steps have passed. New listings must retain external-reference price lineage and originating-offer identity: copying an existing quotation into an Owner listing does not create another independent pricing observation or real rental history.

## Verification

Final isolated automated run:

| Check | Result |
|---|---|
| Full Flutter suite | 843 passed, 3 skipped |
| Flutter analysis | No issues |
| Main web build | Passed |
| Administrator web build | Passed |
| Android debug build | Passed |
| Full API suite, serial, temporary databases | 763 passed, 3 skipped |
| Focused picker/profile/return tests with opt-in rendering | 9 passed, including rendering test |
| Whitespace validation | Passed; existing Git line-ending notices only |

Private logs: `.data/testing/20261114-183437-63ecef41/` and `.data/testing/20261114-125824-4975df16/api-profile-full-serial.log`.

Regression checks cover cancellation/value preservation, cents, zero/maximum bounds, duration selection, actual return-photo references, safe/encoded profile retrieval, authorization/blocking, stale-account responses, and the existing same-day/blocked-range date selection tests. The date tests now scroll to the spaced controls before tapping. No date restrictions were relaxed to make them pass.

Readable-font picker previews were rendered at 360, 390, 1024 and 1440 pixels with 1.4x text. Mobile duration labels were shortened to fit. Preview files are private under `apps/renthub_flutter/.data/compact-trust-previews/`. Real-device interaction and actual return-image loading remain walkthrough checks, not automated passes. Deployed model checksums are unchanged; there was no retraining or database migration.

## Commit message for this change

```text
feat: improve booking controls, participant profiles and return evidence

- space rental dates, appointments and fulfilment controls
- add safe authenticated marketplace profiles with avatars and received reviews
- show renter return photos separately from Owner handover evidence
- replace service duration, deposit and delivery-fee typing with bounded pickers
- guard profile loading against stale account and target responses
- cover picker boundaries, privacy, return evidence and responsive layouts
- document the private 50-item preparation and remaining photo/publication blocker
```
