# Podium, trust and clearer listing details

Updated 14 November 2026. This supersedes the earlier text-summary comparison and three-completion trust display in [the previous handoff](TRUST_COMPARISON_AND_REVIEW_EVIDENCE_RESULT.md).

Later copy cleanup: repeated money-transfer notices were removed from checkout, booking estimates, transaction details, trust, agreement summary and admin dialogs. Payment screens use a short **Simulated payment** label; saved accepted terms remain unchanged. The appointment explanatory sentence and repeated time-zone captions are absent from live screens. The affected checkout/notification/trust/agreement widget run passed **86 tests**; analysis remained clean. The full-suite/build results below precede this final copy-only cleanup.

## Live interface

- **Comparison:** a compact podium shows 1st/2nd for two items and adds 3rd for three. The first item has a trophy; short badges show factors such as Lowest price, Lowest deposit, Top rated or Best condition. The long explanation is removed. Full item facts/actions remain below.
- **Trust:** Owner trust score and Renter trust score use percentage circles. Completed-rental/partner counts and the Building trust wording are removed from ordinary screens. Published received reviews remain independently paginated. No qualifying completions shows a neutral dash, not invented earned reputation; a failed calculation remains unavailable.
- **Photos:** listing details now show all saved photos in a swipe carousel with previous/next arrows, position counter and dots. Tapping uses the existing enlargement viewer. Replacing the photo set resets the page. Photos are capped at 420 pixels high on wide screens.
- **Details:** Condition and Description have separate icon-labelled cards. Services do not receive an item-condition card. Public-location approximation labels and necessary form/payment warnings remain.
- **Copy:** live payment labels are Card, FPX and Wallet; progress and buttons use ordinary payment wording. Repeated time-zone captions, development-upload descriptions and prototype/backend explanations are removed or shortened. Dates still use the same Malaysia-time conversion; rental dates/deadlines are unchanged.

Sample badges replace Demo badges. The presentation adapter displays existing `[Demo]` listing-title markers as `[Sample]`, including related booking/notification titles, without bulk-renaming records. Internal source/simulation markers, developer diagnostics and AI-evidence restrictions remain intact. Brief simulation notices remain where necessary: no real money is transferred. Historical accepted agreement terms keep their original version/wording/hash rather than silently changing an accepted record.

## Comparison ranking

Price and refundable deposit rank lower values first. Published listing ratings and recorded Owner-stated condition rank higher values first. Each usable factor contributes equal ordinal rank points; lowest total ranks first. A factor missing from any item is omitted for all items, so an unreviewed item is not given an invented rating. Lower daily price breaks a total-points tie; an exact remaining tie shares a place. The calculation is deterministic and does not assert that the first item is objectively higher quality or more authentic. A tap-to-read explanation keeps this rule available without a paragraph on the page.

## Trust policy

The policy is now `recorded-rentals-v3`, requiring **one qualifying completed rental with a counterparty** before a role score appears. Cached older policies refresh through the existing on-demand/activity mechanism. No historical records are rewritten.

The existing 365-day window, participant/payment-evidence requirements, deduplication, smoothing, review weights, timeliness and confirmed-responsibility rules remain. Overall, Owner and renter scores are calculated separately. The displayed percentage is reputation under this policy, not a probability of safety. Simulation/source cohorts remain separate internally and do not become clean pricing or recommendation evidence.

## Blockchain check

Read-only inspection of the named JBL Go 4 Speaker bookings found saved contract/transaction references on approved, active and completed rentals. Pending requests and an expired unpaid request had no rental record, consistent with recording after approval. The user subsequently confirmed that proof is visible. No repair, new transaction, account impersonation or historical data change was performed.

The existing collapsed proof panel remains; its local-network label now reads Local test network. Saved references are not fresh verification of a currently running chain, and the entire agreement text is not claimed to be on-chain.

## Verification

- Full serial API suite: **760 passed, 3 skipped, 0 failed**. Private log: `.data/testing/20261114-125824-4975df16/ui-podium-trust-final-api.log`.
- Full Flutter suite: **835 passed, 3 skipped, 0 failed**. Analysis: **No issues found**. Main web, administrator web and Android debug builds all succeeded. Private final run: `.data/testing/20261114-142715-dee6ebaf`; deployed model/metrics checksums were unchanged.
- Added 12 focused tests cover two/three-item ranking and ties, omitted missing factors, podium widths 360/390/1024/1440 with increased text size, carousel navigation/reset, separate detail cells, role percentages without counts and safe sample-label presentation.
- Readable-font podium previews were inspected at mobile and desktop widths. Real phone swiping, screen-reader behaviour and live-network image loading remain manual checks.
- No dependencies, payment rules, booking dates, stored provenance, AI models, accounts or live transactions were changed. The trust maturity rule is the explicit policy change in this follow-up.

Existing optional WebAssembly dry-run, Cupertino font and plugin Kotlin migration notices are separate from the requested JavaScript web/Android builds. No unrelated Auth0 analyzer errors were observed.

## Try it

Restart the API and reopen the rebuilt app. Compare two or three compatible items; open Trust for Owner/Renter scores; open a listing with several photos and swipe. Existing accepted agreement wording remains historical. New trust scores appear after qualifying completions, without manually editing any score.

## Commit message

```text
feat: simplify comparisons, trust scores and listing details

- rank compatible items on a compact podium with short factor badges
- show Owner and Renter trust percentages from qualifying completions
- retain scoring safeguards and refresh older trust-policy caches
- add swipeable listing photos and separate condition/description cards
- replace developer-facing labels with concise marketplace wording
- preserve simulation disclosures, provenance and agreement history
- test ranking ties, responsive layouts, photo navigation and trust display
```
