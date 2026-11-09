# Booking expiry, locations, related items and dashboard insights

Implemented 9 November 2026. Existing uncommitted work is preserved. No live accounts, bookings, addresses or payments were manually changed during this work. Deployed AI models and source settings are unchanged.

## Physical rentals without handover

- Approval schedules a rental. Passing its start day alone does not expire it or establish handover.
- After the inclusive final booked day ends in Malaysia, a physical rental still scheduled without handover evidence becomes **Expired — item not collected**. The linked approved booking also expires.
- The uncaptured demo authorization is voided in full, including the deposit. No capture, Owner settlement, completion reward or penalty is created. Both participants receive deduplicated notifications.
- Active/overdue, disputed, returned, completed, cancelled and service rentals are excluded. Existing condition evidence prevents an inconsistent scheduled row being treated as an uncomplicated no-show.
- Captured payments, missing authorization evidence and mismatched payment ownership/amounts require review; they are not automatically refunded or allocated.
- Early and late handover are rejected. Expired records cannot be reopened through a new dispute; historical case access remains unchanged.
- Expiry uses the existing per-listing lock and write-ahead recovery, processing at most 100 candidate records per invocation. It runs through scheduled lifecycle work and participant booking/rental reads. Previously due records can therefore be processed when the updated API is used; this is ordinary lifecycle processing, not deletion or a cleanup script.
- No grace period or blame assignment was added. Missing handover evidence is not independent proof that no physical exchange occurred. An unrecorded exchange or inconsistent payment needs support review. Service lifecycle rules are unchanged.

## Booking locations

The old dialog used an empty-location message for both privacy-hidden points and genuinely missing snapshots. The existing authenticated locations endpoint now adds `locationStates`:

| State | User experience |
| --- | --- |
| `available` | Open the saved exact pin/address. |
| `hidden_until_approval` | Explain that the other person's exact point is shared after approval. |
| `missing_pin` | Explain that no pin was saved; arrange the meeting point in Messages. |
| `not_required` | Omit irrelevant pickup/delivery entries; explain online bookings need no physical meeting point. |

Ownership and approved/active/completed/disputed unlock rules remain unchanged. No exact coordinates were added to public responses. Current listing coordinates are never substituted into historical booking snapshots. Late responses after account/booking changes are ignored. Older APIs retain conservative wording.

New bookings from pinned listings already save location snapshots correctly; API tests verify that path. An unpinned listing or older booking without a snapshot cannot acquire a truthful historical pickup point automatically. These records remain usable with an explicit meeting arrangement. This change does not backfill private coordinates or republish listings.

A bounded aggregate-only live audit was attempted, but this session could not connect to a running local API/configured database. The actual proportion of the user's records missing pins is therefore **not verified**. Regression tests use isolated databases.

## Related items

**You Might Also Need** is the final section of the item page, after availability and booking/agreement inputs. The lookup no longer inherits Home's category/search/type/price filters, which could exclude accessories from other categories. Flutter and Express retain only location/date context.

Reviewed relationships cover camera supports/lights/recording microphones, peripherals for laptops/desktops, displays for consoles, camping sleeping equipment and bicycle helmets/pumps. Alternative computers/cameras are not substituted as accessories. Unsupported uses or absent eligible stock return an empty state. Generic suggestions do not establish exact connector/mount/size compatibility. Eligibility restrictions, ranking weights, model artifacts and real co-rental thresholds are preserved; no activity was fabricated.

## Admin insights

- Database-derived booking counts offer **Bar chart** and **Pie chart** views with matching text/count legends. Whole-number numeric responses and an optional zero Other bucket are supported. Invalid/missing data is not silently changed into zero activity.
- A six-month **Owner payouts** chart shows successful `owner_settlement` records and **This month: RM …**, using Malaysia month boundaries. Failed payments, authorizations and captures do not become earned payouts.
- These are explicitly labelled demo payouts, not real sales or RentHub revenue. Prior payouts are not recalculated into net refund/clawback accounting.
- The existing admin-only summary response adds `ownerPayouts`: currency, simulation disclosure and six month/amount/count entries. Aggregations run in parallel, independently of loaded table pages.
- Charts sit side by side on wide screens and stack on narrow screens. Loading, empty, unavailable and refresh states remain distinct. No production dependency was added.

## Verification and demonstration

- Final full isolated API: **696 passed, 3 existing opt-in skips**. Logs: `.data/testing/20261109-184035-318ee152/`.
- Final full Flutter: **687 passed, 3 existing skips**; analysis clean; main web, administrator web and Android debug builds passed. Logs: `.data/testing/20261109-183606-7a4cd813/`.
- Focused recovery/location API tests: **19 passed**. Final follow-up widgets: **11 passed**. Existing web/font and Kotlin build warnings remain.
- Desktop/mobile chart previews rendered with synthetic fixtures were inspected. Larger-text layout tests cover 360/390/1024/1440 widths. Rendered fixture amounts are not real platform earnings.
- Deployed artifact checksums are unchanged. Manual Android testing remains **Not run**. No automatic pass was copied into the manual sheets.

The earlier complete run retained its two style-only analyzer messages; braces were corrected and the final Flutter run is clean. Existing test clocks were made explicit for lifecycle cases that had used historical dates, rather than weakening the production handover cutoff.

Restart the API and reopen/hot-restart the app. Check pending versus approved pinned bookings, an older unpinned booking, related items at the page bottom and the admin insights. Use controlled automated clocks for expiry tests; do not rewrite live booking dates or change the phone clock. Eligible old scheduled rentals may expire when normal lifecycle processing runs.

Suggested commit:

```text
feat(bookings): expire uncollected rentals and add clearer marketplace insights

- release uncaptured demo holds after the full booked period without handover
- preserve lifecycle locking, recovery and payment-review safeguards
- block late handover and reopening expired rentals through new disputes
- distinguish hidden, missing and unnecessary booking locations
- move related items below booking details and isolate accessory filters
- add monthly Owner payout bars and booking-status pie charts
- cover privacy, calendar boundaries, concurrent expiry and responsive layouts
```
