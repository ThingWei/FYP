# RentHub recommendation and comparison scope/UI result

Updated: 15 October 2026

## Implemented comparison rules

- Compare at most **three physical items** from the same canonical main category
  **and specific category**. Cameras cannot be mixed with Smartphones merely
  because both are Devices. Brands/models may differ; a catalogue product ID is
  not required for a manually entered product with a valid specific category.
- All 22 existing physical subcategories are eligible groups. Services and missing
  or unknown specific categories are ineligible. No taxonomy changes were made.
- The first selection establishes the group. A different group's Add action offers
  **Keep current comparison** or **Start a new comparison**. Only explicit
  confirmation replaces the current selection. An over-limit addition does not
  write or alter the selection.
- Flutter guards and Express validation/service rules both enforce the limit and
  category relationship. Existing `/users/me/comparison` paths/payloads remain.
  The schema enforces three on changed/new selections while allowing unrelated
  saves of an unchanged legacy four-item array.
- Existing invalid/mixed selections remain readable in saved order and open a
  recovery screen, not a misleading comparison. Keep a compatible group (up to
  three) or explicitly clear it. Reads never clean up or migrate saved selections.

## Layout and actions

The live fixed-width horizontal cards have been replaced by stacked full-width
mobile cards, following the reference prototype's structure. At widths of at
least 900 pixels a constrained table aligns each fact row across items. Table
rows grow for long text, including titles and increased system text size; there
are no fixed text-heavy card heights.

Cards use actual public listing photos with a neutral fallback, product title and
brand/model, MYR daily price, deposit, condition, approximate area, listing
rating/review count, Owner rating if supplied, fulfilment and verification.
Unavailable Owner rating is explicitly **Not available**; listing rating and trust
score are not substituted for it. Exact distances, private addresses and pickup
coordinates are not displayed or fetched for comparison.

Each item has **Remove**, **View Details** and **Choose Dates**. Details opens the
existing live listing/booking page. Choose Dates uses that same flow and opens its
existing start-date picker once availability has loaded and a selectable date is
available. These actions do not create bookings or payments. Existing identity,
availability, agreement, checkout and Owner-approval guards remain authoritative.
Clear comparison retains its confirmation dialog.

## Recommendation integration

Home now exposes Recommended For You, Trending Near You and Recently Viewed;
listing details expose You Might Also Need. Compare controls work on Home
suggestions and existing marketplace results. Five-tab navigation is unchanged.

See [recommendation AI result](RECOMMENDATION_AI_RESULT.md) for real browsing,
trending/co-rental windows, score weights, generic-use rules, independent failure
handling, location privacy and accuracy limitations. No prices, product identities,
completed rentals or popularity statistics were fabricated for this work.

## Verification

- API suite: **330 passed / 3 skipped** using temporary isolated MongoDB. Checks
  include category/limit bypass attempts, unchanged selections after failed writes,
  ordered legacy reads, explicit recovery, unrelated legacy profile saves, private
  feed serialization, history deduplication/TTL, soft holds and section-only retry.
- AI suite: **384 passed**, two existing dependency deprecation warnings.
- New recommendation/comparison Flutter suite: **17 passed**. Covers three-item
  guards, incompatible-group confirmation, legacy recovery, long titles, larger
  text, 360/390/1100-pixel layouts, callbacks and real date-picker navigation.
- Full Flutter suite: **332 passed / 3 skipped**. Application-only analyzer is clean; full
  analyzer retains `test/auth0_persistence_test.dart:41/43` undefined constructor
  parameters `latestLinkProvider` and `mobileLinkPollInterval`. They were not changed.
- Web and Android debug builds passed. Existing socket/Wasm/font and Kotlin
  plugin migration warnings remain separate from these changes.
- Launcher regression passed, checking actual Python contracts and rejecting
  older API/AI processes missing the new feed/profile support.
- No real-user database cleanup, production data import, secret changes, new
  production dependencies or training runs were performed.

These are render/interaction tests, not an assertion that the new GPS workflow
has been physically tested on the user's Android device.

## Restart and demonstration checklist

1. Restart API, AI and Flutter through `run-renthub.ps1`. If an older independently
   launched process occupies a port, stop its original terminal before relaunching;
   the launcher explains the missing contracts rather than reusing stale code.
2. Open a few eligible listings. Return Home and verify Recently Viewed, then
   compare two Cameras with different brands/models.
3. Try adding a Smartphone: Keep must preserve the camera selection; Start a new
   comparison must replace it only after confirmation. Try a fourth Camera and a
   service: neither may silently join the comparison.
4. Confirm stacked mobile cards, aligned wide rows and larger-text readability.
   View Details and Choose Dates must not create a pending booking/payment.
5. Try GPS permission denial, manual area selection and a coarse reading. Check
   displayed accuracy, radius controls and approximate-area labels. Verify
   pull-to-refresh and app foreground return on the actual Android device.
6. A new area with no activity should show an honest empty Trending section.
   Sparse co-rentals use reviewed generic complements only; unsupported domains
   may have none. Do not add fake completed rentals to populate the demonstration.
7. Clear history with confirmation. Saved listings/rental records must remain;
   a newly opened listing can legitimately create a new browsing signal afterward.

## Complete commit message

```text
feat(discovery): align recommendations and comparison with RentHub scope

- add personalised, trending, recently viewed and complementary sections
- record bounded daily browsing signals with private account-scoped clearing
- preserve history profiles outside filtered candidate pages
- rerank hybrid recommendations by approximate proximity and availability
- derive trending and co-rental evidence from real marketplace activity
- retain honest cold-start and reviewed generic-complement fallbacks
- isolate section retries and discard stale location/account responses
- restrict comparison to three physical items in one specific category
- add explicit legacy recovery and responsive aligned comparison layouts
- route date selection through existing booking and identity guards
- align API/AI launcher readiness and add regression coverage/results
```
