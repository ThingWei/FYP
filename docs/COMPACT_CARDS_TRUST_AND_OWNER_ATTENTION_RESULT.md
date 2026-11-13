# Compact cards, unified trust and clear Owner actions

Implemented 13 November 2026.

## What changed

### Smaller marketplace cards

Home swipe sections show two complete cards at 360/390-pixel widths. Grid and collection pages share the same compact card; list rows use a 72-pixel square thumbnail. Photos remain square and cropped consistently, with a safe placeholder when unavailable. Listing-detail galleries are unchanged.

Price appears above a two-line title, followed by a one-line approximate area and applicable availability. Promoted/demo labels and selected wishlist/comparison colours remain. **Why this item?** is an accessible information button over the photo; it opens the existing explanation without navigating to the listing. Card controls have 48-pixel minimum tap targets. Heights use actual available width, text scaling and measured content rather than reserving an extra explanation row.

### One application trust score

The application now uses `recorded-rentals-v2`, retaining the compatible `renthub-trust-v1` response structure. The new `recorded` summary combines eligible marketplace and demonstration completions, deduplicated by booking and rental. Overall, Owner and renter scores remain role-specific.

The existing rules remain: a 365-day window; three qualifying completions with at least two different people before a numeric score; consistent participants and listing type; recorded completion; successful MYR capture evidence covering the booked base rental charge; published counterparty reviews; and explicit administrator responsibility findings for dispute penalties. Existing weights and smoothing are unchanged. Unsupported/unpaid/mismatched records do not become earned reputation.

Users see one **Rental history** and **Trust score**. Before the threshold, **Building trust** shows actual completion and partner counts. The short explanation states that demonstration payments are simulated. There is no separate demo activity card in the normal interface.

Profile, listing Owner badges/snapshots, chat, administrator displays, trust sorting and the existing Owner-trust feature use the application summary. Older cached calculations refresh on demand when their scoring policy is outdated, as well as under the existing 60-second/activity refresh rules. Existing listing snapshots can lag until their Owner is refreshed; opening that Owner's trust page triggers the current calculation. There is no bulk migration.

**Simulation and provenance:** original source markers and payment simulation flags are retained. Marketplace/demo cohorts remain available for compatibility and diagnostics. This is demonstration-platform reputation, not evidence of real-money transactions. Clean pricing evidence, training/evaluation/export eligibility and deployed models are not relaxed by this change.

### Reviews about a user

The trust/history page includes **Reviews about this user**, with published author names, ratings, text, reviewed role, listing title and Malaysia-readable dates. Reviews load and retry independently of the trust calculation. Pagination defaults to 20, with the existing 10/20/50 controls and dot navigation. A refresh failure retains successfully loaded rows; stale account/subject/role responses cannot replace the current view.

Authenticated endpoint:

```text
GET /api/v1/reviews/subjects/:subjectId?role=overall&page=1&limit=20
```

`role` accepts `overall`, `owner` or `renter`; limits are 1–100. Filtering and stable ordering happen before pagination/counting. The endpoint shares trust-profile visibility/blocking rules, excludes self/hidden reviews and returns approved fields only. It exposes no private booking/rental IDs, author account IDs, moderation metadata, identity evidence or coordinates. Reviews displayed here can be older than the 365-day score window; only eligible recent completions contribute to the score.

### Approved driving licences

An approved, valid, fully reviewed licence opens its saved summary: status, classes, expiry and review notes. Capture/upload/submission controls stay hidden. **Update licence** deliberately opens the existing update form. **Cancel licence update** discards only that draft; existing approval remains. Failed submissions retain the draft and existing recovery behaviour. Pending reviews show their review status; unverified, rejected, expired and resubmission-required licences retain the upload form. Existing MyKad and driving authorization requirements are unchanged.

### Owner attention

Owner Home now has **Needs attention**, with distinct **Awaiting approval** and **Overdue returns** entries. Approval counts still include only eligible paid pending requests. Overdue orders never receive Approve/Reject controls.

`GET /api/v1/bookings/owner` adds database-wide `overdueReturns` and `attentionNeeded` to its existing summary. Counts do not depend on loaded pages or active list filters. The overdue definition reuses the Malaysian inclusive return deadline and configured grace period, so an active/disputed unreturned physical rental can need attention before the scheduler changes its display status. Returned, scheduled, service and terminal linked-booking records are excluded.

```text
GET /api/v1/rentals/owner?attention=overdue&page=1&limit=20
```

The optional filter applies before pagination/counting, sorts by oldest return date with a stable ID tie-break, and scopes records to the actual Owner. The new view reuses existing order details and **Message renter**, **Report item not returned** / **View case** actions. Separate caches and account guards preserve renter/Owner isolation. Callers omitting `attention` retain existing behaviour.

## Verification

- Isolated full API suite: **751 passed, 3 skipped, 0 failed** (754 total), private run `.data/testing/20261113-225110-07fb95de`. The earlier unprivileged full run stalled during process cleanup; the isolated rerun completed in 28 seconds. New trust-policy assertions also passed after that run.
- Focused API checks cover safe review projections, session/block/restricted access, role filters, pagination, hidden/self reviews, outdated cache refresh, unchanged simulation/source flags, 26 overdue orders across pages and independent approval counts.
- Widget checks cover swipe/grid/list layouts at 360/390/1024/1440 widths, 1.0/1.8 text scaling, two complete mobile cards, square/failed photos, long titles, card actions, information help, review pagination/retry/account changes, approved-licence updates/cancellation and Owner overdue navigation.
- Private readable-font layout previews were inspected for compact cards, received reviews, approved licences and Owner attention. Preview generation is opt-in: `RENTHUB_CAPTURE_TEST_UI=true` with `flutter test test/compact_trust_owner_test.dart`; files stay under the ignored app `.data/compact-trust-previews` folder. Default tests do not require Windows fonts or create previews.
- Final Flutter suite: **802 passed, 3 skipped, 0 failed**. Analyzer: **No issues found**. Private run `.data/testing/20261113-225715-d30cc753`.
- Final main web, administrator web and Android debug builds: **all succeeded**, in the same final Flutter run above. Existing build notices concern optional Cupertino font references and plugin Kotlin migration; neither prevented those builds. No Auth0 analyzer errors occurred in this run.

No live rentals, reviews, payments or licence approvals were fabricated or rewritten. Test databases and API integrations were isolated. Deployed AI model/metrics checksums remained unchanged. No new dependency, secret, migration or payment/rental lifecycle rule was added.

## Walkthrough

1. Restart the API and rebuild/reopen Flutter through the normal launcher.
2. Check Home, Explore and a saved collection: two compact mobile cards, working heart/comparison controls and information help.
3. Open Profile → Trust. Eligible demo completions now contribute to Rental history; fewer than three completions/two partners still shows Building trust. Published reviews appear below it. Missing historical capture evidence still excludes a record.
4. Open an approved driving licence: upload controls are hidden until Update licence. Cancel an update to retain the saved approval.
5. In Owner Home, open Overdue returns. Counts include all matching records, not only the first page. Messaging/reporting remains explicit; merely viewing does not approve, capture, refund or deduct anything.

Real Android interaction, live storage/network behaviour and screen-reader/device verification remain walkthrough checks; widget previews and successful builds are not a claim that these device checks were performed.

## Commit message

```text
feat: compact marketplace cards and unify rental trust with Owner attention

- fit two compact square-photo cards per mobile swipe section
- move recommendation explanations over photos and keep accessible controls
- combine eligible recorded completions in versioned application trust
- retain simulation provenance and existing clean AI-evidence rules
- add safe paginated participant reviews to trust profiles
- show approved driving licences read-only with explicit update/cancel
- add database-wide overdue counts and paginated Owner attention orders
- cover trust privacy, pagination, role isolation and responsive layouts
```
