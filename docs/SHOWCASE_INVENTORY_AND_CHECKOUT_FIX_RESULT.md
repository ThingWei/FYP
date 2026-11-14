# Showcase inventory and checkout fixes

## User-facing changes

- Removed trust scores and the trust action from administrator Users/Verification details. Public renter/Owner trust remains available.
- Booking details now show Appointments, booking progress, then Handover for both participants. Unpaid bookings retain their existing hidden-progress behaviour.
- Fixed rewards leaving checkout permanently disabled. The payment route now owns the reward operation and clears its busy state even if refreshing the saved charges rebuilds the reward card. Applying/removing a reward never authorizes payment.
- Removed bracketed Demo/Sample title labels and Sample card badges. Promoted labels remain. This is presentation, not evidence reclassification.

## Showcase records actually saved

- Refreshed **64 existing active generated listings**, across **two existing verified Owners**. No new account or approval was created.
- Retained every listing's price, category, model, Owner, status and private location. Titles are clean and descriptions concise.
- Uploaded **65 original photo assets**: 64 initial Owner-associated assets and one tutoring-specific correction. Final listings use 64 assets for 52 distinct products/services; equivalent products held by different Owners retain separate uploads.
- Visually checked all downloaded candidates. Replaced a wrong book and wrong Canon model before publication. The mathematics service uses a tutoring image; the photography service uses a photographer image.
- Photo credits appear in descriptions and [the credits list](SHOWCASE_PHOTO_CREDITS.md). Photos are catalogue/representative images, not actual handover or condition evidence.
- Added **six completed generated showcase bookings**, six linked rental records and **17 simulated ledger entries** (29 documents total). They cover speaker, camera, smartphone, book, clothing and tutoring examples. Each capture equals its Owner settlement plus deposit release, where applicable.
- No reviews, agreement acceptances, receipt acknowledgements, handover/return evidence or blockchain receipts were invented. Historical details without evidence remain unavailable.
- Stored an EJSON backup of the 64 original listings before modification. Old photo assets remain for existing references. The preparation, backup, receipts and verification report are private under `services/api/.data/evidence/regular-owner-batch-2026-11-14/`.

The user clarified these records are generated **project-showcase** activity. Their existing internal `demo_seed` compatibility marker and simulated-payment flag remain. They are not test-run records and carry no per-card Sample badge. They remain excluded from clean pricing evidence and independent accuracy evaluation. Creating showcase completions cannot establish market accuracy or genuine achieved rental prices.

## Implementation safeguards

`src/scripts/showcaseInventory.js` supports reviewed-photo updates and deterministic, recoverable generated completions. It accepts only already-active showcase listings from verified Owners, and a different verified renter. It cannot publish a genuine listing, grant verification, create signatures or convert source markers. Preview is read-only; replay checks every existing record for conflicts and never overwrites changed history.

The private one-off runner additionally uses a fixed inspected-ID allowlist, prevalidates every record, records a backup, verifies uploaded hashes and checks fresh `updatedAt` values before replacing images. It performs no ordinary moderation action and impersonates no administrator. The previously submitted regular JBL Go 4 listing remains subject to genuine administrator review; this separate showcase refresh does not approve it.

## Verification

- Full isolated API suite: **779 passed, 3 skipped**. Includes showcase-only guards, dry-run/replay/collision behaviour, valid account relationships and balanced ledgers.
- Full Flutter suite: **859 passed, 3 skipped**. Final Flutter analysis is clean. The earlier single brace-style lint in a test was corrected and analysis rerun successfully.
- Focused checkout tests pass at 360/390 pixels, including apply, remove, charge-review checkbox, explicit payment and response recovery.
- Both booking-detail layouts pass ordering and increased-text-size checks at 360/390 pixels. Admin detail tests assert the absence of trust controls.
- Main web, administrator web and Android debug builds passed.
- Model artifact checksums remained unchanged. No retraining, dependency or schema migration was introduced.
- Read-only post-write verification confirmed 64 listings, all **22 physical subcategories**, two services and six generated completions. All **64 current public photo responses** returned successfully and matched their stored SHA-256 hashes. Every generated ledger reconciled; no verification issue remained.
- Android device interaction was not performed; automated widget results are not reported as device observations.

Private test logs: `.data/testing/20261114-125824-4975df16/checkout-showcase-final-flutter.log`, `showcase-full-api.log`, `checkout-final-analysis.log` and `.data/testing/20261114-233936-646085fa/` for builds/artifact hashes. The latter pack retains its original analysis failure as an accurate historical result; the successful rerun is recorded separately rather than changing earlier results.

Restart/rebuild the app for UI changes, then refresh Home/Owner listings and booking history to load shared saved records.

## Commit message

```text
fix: restore reward checkout and polish showcase rental records

- keep reward loading and recovery owned by the checkout route
- preserve payment access after applying or removing loyalty rewards
- remove trust controls from admin verification and user details
- place booking progress between appointments and handover evidence
- simplify generated listing labels while preserving private provenance
- add guarded, repeatable showcase inventory and completion preparation
- refresh showcase photos with source credits and balanced simulated history
- cover checkout, responsive section order and showcase safety regressions
```
