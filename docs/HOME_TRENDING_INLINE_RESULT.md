# Home trending and nearby results

Implemented on 10 November 2026. Home can display listings before an area is chosen, and choosing an area refreshes cards in the same section. It does not automatically request GPS permission or navigate to a results page.

## Behaviour

- **With a selected pin and qualifying activity:** **Trending Near You**, using the existing 30-day activity rules and approximate public listing points.
- **Without a selected area:** general activity can appear as **Trending Now**, labelled **All areas**. No device location is guessed.
- **When there is not enough activity:** show eligible listings under **Rentals Near You** or **Explore Rentals**, with explicit non-trending provenance. This is a discovery fallback, not fabricated popularity.
- Demo listings can appear in those discovery picks with a **Demo** badge. They still cannot acquire organic trending status through seeded bookings or promotion.
- **Choose area**, **Use current location** and radius/clear controls are available beside the section. The map retains its normal final confirmation. GPS is foreground-only and only requested after tapping. Permission failure, timeout and stale readings retain existing recovery protections.
- Radius choices remain 5/10/25/50 km, default 10. The selected area/radius are also retained in Home's filter draft. Approximate-location and unpinned-exclusion guidance stays visible.
- **See all** is an explicit action to open the fuller collection. It is no longer the route required to see any cards.
- Applying Home discovery filters with the default recommendation sort and no text search retains the recommendation sections. Explicit text searches and alternate result sorts retain the existing results-list flow. Explore keeps its own state and pagination.
- Genuine zero matches remain an honest empty state with wider-radius, area or filter guidance. Failures still offer retry; no listings are invented to fill an empty database.

## Eligibility, privacy and ranking

The recommendation service and trending/picks query now share the same category, item/service type, public locality, price, verification and promotion filters. Selected-date availability uses the existing confirmed-booking/manual-unavailability rules; pending requests remain soft holds.

Own listings, inactive listings, blocked Owners and restricted accounts remain excluded. Nearby queries still exclude unpinned records and filter on approximate public GeoJSON points. Public serialization remains responsible for removing exact listing locations. General discovery can include unpinned listings because it makes no radius claim.

Genuine trending still ranks activity first, then proximity. Cold-start picks use proximity, current availability and stable recency ordering, with no promotion-based popularity boost. Services are not labelled available merely because their listing is active. Existing personalized ranking weights, models and activity retention are unchanged.

The existing recommendation-feed endpoint gains additive, allowlisted `scope` (`nearby`, `area`, `marketplace`) and `basis` (`activity`, `highlights`) metadata for the trending section. Older response shapes remain readable. Unknown metadata never becomes visible copy. No new endpoint, dependency, database migration, activity seed or automatic background tracking was added.

## Verification

- API: new coverage checks general picks without GPS, genuine activity precedence, demo separation, category/price/date/blocked-account filtering, approximate location privacy, text-area scope, empty results and invalid partial coordinates.
- Flutter: tests at 360/390/1200 logical pixels with 140% text cover immediate cards, no automatic GPS, inline updates after GPS, radius persistence, Home filters keeping sections visible, and explicit See all navigation. Existing independent failures, stale responses, account/location changes, GPS recovery, comparison and search-state tests remain in place.
- Existing contract tests were updated from the former results-list-only Home behavior to the inline feed and retain their recommendation-reason assertions.
- No live accounts, bookings or manual P0 results were changed during verification.

| Check | Result |
|---|---|
| Full API suite | **708 passed, 3 existing skips** |
| Full Flutter suite | **726 passed, 3 existing skips** |
| Final Flutter analysis | **No issues found** |
| Main web / admin web / Android debug builds | Passed |
| Fixture rendering | 3 cases, 6 images at 360/390/1200 pixels, 130% text |
| Model checksums | Unchanged |

Private API execution: `.data/testing/20261110-134251-16de06db/`. Flutter tests/builds: `.data/testing/20261110-134650-5bca10f8/`. That Flutter pack recorded an analyzer style warning in the updated test fixture; it was corrected and final analysis passed separately in `apps/renthub_flutter/.data/home-trending-analysis.log`. The earlier results-list-only contract assertion was updated without removing its reason/filter checks. No functional failures remain in the final results.

Mobile general/nearby and desktop nearby renders were inspected. Images are private test fixtures under `apps/renthub_flutter/build/ui-checks/home-inline-trending-*.png`. Actual Android GPS, device permission prompts and final user walkthrough were not exercised in this task. Queries remain bounded to 1,000 eligible candidates and 10,000 recent activity records; Home is a limited overview, not an exhaustive popularity report.

## Walkthrough

1. Open renter Home. General trends or clearly labelled marketplace picks should already show cards.
2. Tap **Choose area** and confirm a pin, or tap the location icon on Android. Cards should update on Home without opening the collection page.
3. Change the radius or clear the area. Reopen Filters to check the retained selection.
4. Apply a category filter with recommendation sorting. Home sections remain visible. Tap **See all** only when you want the fuller list.
5. In a sparse area, expect nearby picks or a truthful zero-match message—not invented trends. Real-device GPS and final UAT remain separate from fixture passes.

## Commit message

```text
fix(home): display trending and nearby listings inline

- retain Home recommendation sections when applying discovery filters
- add direct area, GPS and radius controls with retained filter state
- show labelled marketplace/nearby picks when organic trends are sparse
- preserve eligibility, date availability, privacy and genuine activity ranking
- label demo listings and add API/widget regression coverage
```
