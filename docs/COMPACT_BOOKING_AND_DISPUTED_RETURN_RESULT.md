# Compact booking screens and disputed returns

Follow-up: [Item details, photos and form polish](ITEM_DETAIL_AND_FORM_POLISH_RESULT.md) records the newer item-summary, role-labelled trust, full-screen gallery, shorter handover wording and transparent pagination changes.

Implemented 15 November 2026. Existing uncommitted work was preserved.

## Screens and wording

- All six Owner dashboard metrics use the same card and grid: left-aligned icon, value and label, 14-pixel padding and 12-pixel gaps. Narrow screens or larger text stack the cards when necessary. Approval and overdue destinations remain separate.
- Booking shortcuts are **Location**, **Owner/Renter** and **Agreement**, in a shared compact, centred, wrapping group. Smaller visual buttons retain 48-pixel touch targets. Continue payment remains a separate primary action.
- The case page no longer shows an otherwise empty **Case details** disclosure containing only the internal ID. The identifier remains available internally.
- Condition evidence has separate **Handover** and **Return** cards. Each includes condition, recorded time, a compact photo carousel, enlargement/retry and expandable notes. Desktop uses two columns when space permits; mobile uses stacked cards. Missing historical dates/photos are not invented.
- Case photos use the latest cached rental. Successful return responses are retained before refreshing lists, so photos are not lost if a paginated response omits the record. Account changes still clear the data.
- Listing cards omit the area row and its measured height. Maps, public approximate-location disclosures, nearby queries and private booking locations are unchanged.

## Saved places and checkout

The original delivery dropdown used `UserAddress` objects as values. After booking creation, the remembered-location refresh reconstructed the profile and its address objects. The dropdown could retain a selected object that no longer matched any menu item, causing Flutter's dropdown assertion under checkout.

The new shared selector uses stable saved/recent identifiers, with a deterministic UI-only fallback for legacy addresses without IDs. It deduplicates equivalent keys and tolerates profile refreshes or removed entries without changing the confirmed destination. No UI key is used as a catalogue or database identity.

The selector reads **Saved places (optional)**, displays the actual address, and calls automatically remembered entries **Recent place** instead of presenting “Pickup” as a delivery destination. A 20-pixel gap separates it from the delivery-address field. Existing map/pin validation, destination snapshots and ownership rules remain authoritative.

## Return while a case is open

The existing `POST /api/v1/rentals/:id/return` now accepts the actual renter's evidence for an eligible physical rental during a dispute. Eligibility is checked with fresh records under the same listing lifecycle lock used by dispute decisions.

- The case must remain open, the linked booking must be disputed with captured/partly refunded/settled payment state, and the saved pre-dispute rental state must establish that the rental had started. Pending renter receipt cannot qualify.
- Unchanged active/overdue return access remains available. Services, completed/cancelled/expired bookings and never-received disputed items cannot use this flow.
- A disputed return saves immutable evidence while both records remain disputed. **Return submitted. Case under review** replaces any implication of normal completion.
- No capture, compensation checkout, extra fee, automatic settlement, refund or deposit deduction occurs. Ordinary Owner completion stays blocked while the case is open.
- Identical retry requests return the original saved record; conflicting replacements are rejected. A recoverable lifecycle operation and deduplicated Owner notification prevent duplicate records/alerts.
- Dismissing the case after return submission restores **Return awaiting inspection**, rather than the earlier active/overdue state. Final administrator settlement keeps its existing remaining-held-funds policy.
- Existing overdue policies already stop reminders/restrictions after a recorded return; opening the dispute alone does not remove those restrictions.

Rental responses add a boolean `returnAllowed` for consistent controls. Disputed eligibility is derived in bounded batch queries for list responses and fresh checks for individual reads/submission; it is not a new persistent database field. Older responses without it conservatively hide disputed-return submission. Existing endpoint paths and payloads are preserved.

## Typography

Inter is bundled locally from the official `rsms/inter` repository, with its SIL Open Font License 1.1. There is no font package or runtime download. Shared sizes are 14-pixel body text, 12-pixel secondary text, 13-pixel action labels and 18–22-pixel main headings. Important large values retain their hierarchy; system text scaling and platform Unicode fallback remain enabled.

Font SHA-256: `4989b125924991b90d05b2d16e0e388c48f7d5bb8b30539bbf9c755278d0ccaf`. The APK was inspected to confirm that both font and licence assets are packaged.

## Verification

- Full isolated API suite: **787 passed, 3 skipped, 0 failed**. Skips are the existing opt-in live vehicle/smartphone provider and Mongo-to-XGBoost integration checks.
- Focused dispute suite: **25 passed**. Coverage includes protected participant access, pending-receipt/unpaid/service rejection, immutable repeated returns, notification deduplication, dismissal after return, and concurrent return/dismissal/final-settlement transitions. Ledger comparisons verify no money moves merely because return evidence is submitted.
- Full Flutter suite: **893 passed, 3 existing skips, 0 failed**. Final analysis: **No issues found**. Main web, administrator web and Android debug builds passed from the final application sources.
- Private Inter-font fixture previews rendered at **360/390/1024/1440 pixels**, with 1.3x text; representative mobile/desktop Owner and case views were inspected. Widget tests also exercise 1.6x text, actual refreshed address instances, removed/duplicate entries, missing history, new return photos and preserved data outside the loaded page.
- No live account, booking, payment, source configuration or model artifact was changed. No database migration or production dependency was added.
- Existing build warnings remain: web Wasm compatibility/Cupertino icon-font warnings and Android Gradle/Kotlin migration notices. They did not prevent any build; no unrelated failing check remains in this run.

Private validation logs: `.data/testing/20261115-compact-return/`. Private fixture previews: `apps/renthub_flutter/.data/compact-return-previews/`. These are test observations, not real participant evidence.

## Short device walkthrough

Restart the API and rebuild/reopen the app so the return capability and font assets are current.

1. Check the six Owner cards, compact booking links and listing cards.
2. Choose Owner delivery, select a saved place, continue to checkout, and return. Confirm the address remains and no red error screen appears.
3. On a received physical rental with an open dispute, sign in as the renter and submit return photos. Both participants should see the photos; the case remains open and no settlement occurs.
4. Dismiss that case as administrator, then inspect the return as Owner. Separately verify that an unreceived disputed booking offers no return action.

Real-device touch, TalkBack, Android keyboard and live participant return tests were not performed in this task. Build/widget results do not replace that walkthrough. Submitted photos record a participant's account of the return; they do not independently prove physical delivery or condition.

## Commit message

```text
fix: simplify booking screens and support returns during disputes

- align Owner attention cards with dashboard metrics
- shorten booking links and separate handover/return photo galleries
- prevent saved-address dropdown crashes during checkout refresh
- preserve returned evidence across pagination and account-safe refreshes
- allow eligible disputed returns without closing cases or moving funds
- restore return inspection after case dismissal and protect lifecycle races
- bundle Inter locally and compact shared typography and listing cards
- add API/widget regressions and document verification and device checks
```
