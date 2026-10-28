# Rental-length pricing fix

28 October 2026, Malaysia time.

The [subsequent suitability/evaluation result](AI_PRICING_QUALITY_AND_EVALUATION_RESULT.md)
fixes the R50's unsuitable model-family comparisons while preserving this daily
baseline behaviour. It also fixes native export projections for rate basis and
parser version, and adds the `pricing-suitability-v1` launcher/API capability.
All 22 domain baseline tests still pass; unsupported packages remain unavailable.

The shared evidence filter previously treated a quote expressed per day as an
exactly-one-day package. Most current camera, phone and computer references were
therefore removed when an Owner requested two or more days. The form and fitted
model already accepted longer durations; the filtering was the blocker.

## Implemented behaviour

`pricingPeriods.js` is shared by live reference selection, comparable ranking and
offline feature preparation. It distinguishes:

| Rate basis | Behaviour |
|---|---|
| `daily_rate` | Advertised daily amount. Outside its quoted one-day observation, may supply a qualified daily-price baseline for a 2–365-day estimate. |
| `fixed_period` | A fixed package, including a seven-day average or a one-day-only reference. Usable only for its recorded period. |
| `duration_band` | A tariff explicitly applicable to a range of rental lengths. Usable only within that range. |
| `unknown` / absent | No extrapolation from unknown units. Existing strict period matching remains. |

An applicable tariff wins over a daily baseline for the same originating offer,
even when the baseline was refreshed later. A quoted three-day package is not
quarantined merely because its daily equivalent differs from the separate daily
tariff. Genuine conflicting observations remain excluded. Source deduplication,
enabled-source checks, product/package compatibility, freshness and clean
provenance still apply.

At the selected tier, use applicable-period observations alone when they meet
that tier's minimum; otherwise qualified baselines may support a rough estimate.
Baseline references do not count as exact product-and-period price evidence.
Counts expose `durationBaselineCount` and the actual `requestedRentalDays`.
No longer-rental discount rule, price cap or duration multiplier was added.
The original requested length reaches FastAPI and its fitted feature row. The
existing learned duration feature can still affect the model estimate; it does
not establish an advertised discount.

Original amounts, observation dates, quoted periods and daily equivalents remain
unchanged. Completed rentals keep their actual duration and cannot become daily
asking rates. No fake rental history is introduced.

## Source parsers and existing records

Parser version 2 persists the quote's explicit `rateBasis` in optional reference
metadata. RENTISM /day, ITPA /unit/day, Cilt Daily, Alquiler MYR/day, Ecocana Daily,
PC Rent Daily and JomRent /24 Hours are daily-rate forms. Their multi-day package
forms remain fixed. DRIVOR's ranges are duration bands; Partymix/Futago packages
and The Rental Guy's explicitly one-day references remain fixed-period records.

Existing accepted automatic records from those seven installed version-1 daily
parsers can use a read-only compatibility classification, only when the recorded
period/min/max are all one day. Unknown versions, other sources, missing validation,
multi-day packages and manual CSV rows are not silently reclassified. Declared
fixed/unknown metadata is respected. Source approval/enablement is still required.
There is no migration, bulk update, automatic import or forced source refresh.

Advanced CSV imports accept an optional `rateBasis` column. Omission retains
`fixed_period` behaviour. `daily_rate` requires `rentalDays = 1` and an explicitly
published daily rate reviewed by the administrator. CSV duration bands are not
introduced. Import validation, authorization, preview-without-writes, complete
file validation and duplicate/conflict handling remain intact; changing this
meaning is not treated as an identical duplicate observation.

Exports preserve `rate_basis` as provenance, not a new fitted feature. Offline
selection applies the same period policy and existing observation/availability
cutoffs. Older exports without the metadata remain conservative.

## Owner interface

Daily-baseline suggestions remain **Rough daily estimate**, with this visible
notice: “Daily rates are used as a guide for your selected rental length. A price
or discount for this length has not been confirmed.” Expanded details distinguish
the baseline count from compatible fixed packages and duration-specific quotes.
The synthetic-heavy training notice remains. Entered prices stay unchanged until
**Use this price** is pressed; requesting a suggestion needs no daily-price input.
No request creates a listing, booking or payment.

## Verification

- Policy fixtures cover all **22 specific categories** at 1, 2, 3, 7, 14, 30 and
  365 days. These fixtures establish code coverage, not external data coverage.
- Negative cases retain fixed-week/one-day packages, out-of-band tariffs,
  unknown legacy CSVs, disabled sources, invalid units/durations and actual
  completed-rental periods. Legacy classification is tested without mutation.
- API tests exercise CSV validation and 1/2/3/7/30-day price requests, prove the
  actual requested length reaches inference and preserve quote/history values.
- Flutter checks use 360/390-pixel widths with 1.4 text scaling, baseline warnings,
  explicit price acceptance and empty-price requests at 2/3/7/30 days.
- AI regression verifies longer durations reach the unchanged fitted feature
  order. No weights are fitted or deployed.

| Command/check | Result |
|---|---|
| Focused API parser/import/period/export tests | 107 passed |
| Full API suite | 542 passed, 3 existing skips |
| Full Flutter suite | 489 passed, 3 existing skips |
| Relevant AI pricing/evaluation tests | 30 passed |
| Flutter analysis | No issues found |
| Web / Android debug builds | Both passed |
| Read-only current-data check | 78 scenarios; 58 previously empty longer requests recovered |
| Existing model smoke check | 77/78 suggestions available; artifact unchanged |

The read-only check used the twelve existing demo identities plus an R50
diagnostic, each at 1/2/3/7/14/30 days, using existing external asking evidence.
Example condition/age and neutral Owner inputs are test scenarios. No demo prices
became clean evidence. Aggregate listing/booking/payment/reference/user counts
were unchanged. The 30-day Camry case remains unavailable because no eligible
stored tariff covers that period; a different tariff was not stretched to fill it.

This is a functional check, not independently validated real-world accuracy.
Fixed-only sources and domains without price observations still require manual
pricing. In particular, the previously documented EOS R50 camera-class/family
comparison defect remains separate and open; this duration fix does not resolve
its unsuitable higher-priced camera comparisons.

Private reports:

- `services/api/.data/evidence/duration-pricing-2026-10-28/audit.json`
- `services/ai/.data/evaluation/duration-pricing-2026-10-28.json`

Artifact SHA-256 remains
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
`git diff --check` passed. Existing nonblocking Wasm/Socket.IO, optional Cupertino
font and Kotlin migration warnings remain. No new analyzer/Auth0 errors occurred.

## Testing in RentHub

The launcher now watches API source by default. Use `-NoApiReload` only for an
intentionally stable process; environment changes still require restart. Open an
existing Samsung/Dell/Canon demo listing, keep its package unchanged, enter 2, 3
or 7 expected days, and request a fresh suggestion. Look for the daily-baseline
notice when no applicable multi-day tariff exists. Exact quoted lengths retain
their normal explanation. No draft save or active-listing resubmission is needed
to test suggestions. Real-device UAT remains to be performed.

### Follow-up: stale running API corrected

The user still saw unavailable for longer rentals after the source fix. The
running API on port 3000 was confirmed to predate the changed code. The launcher
had started `node src/server.js` without watching; its earlier readiness checks
did not distinguish a server missing this pricing policy.

Only the verified stale RentHub API was restarted. The replacement now watches
`src`, while AI, MongoDB and the other services remain running. Live API readiness
confirms `pricing-daily-baseline-v1`. Through the configured HTTP AI client,
Samsung requests with compatible evidence succeeded at 1/2/3/7 days. This is live
service verification, not an authenticated tap in the user's Windows app.

The API advertises the new capability, and launcher readiness requires it. An
occupied outdated/unknown listener is reported rather than killed automatically.
New launcher-owned Node watch supervisors and children are cleaned up together,
with start-time checks preventing PID-reuse mistakes. `-NoApiReload` preserves
the previous non-watching mode explicitly. Source watching excludes private data,
uploads, training outputs and logs.

Verification: API health/period checks 29 passed; launcher parser, readiness,
argument and guarded-cleanup tests passed, including disposable Python/Node
parent/child integration fixtures. The real API remained ready after those tests.
No Flutter source, fitted model or authentication rules changed in this follow-up.
Existing full-suite/build results above are retained; they were not rerun for
this launcher/health-only change.

The one-time repair's supervisor/start-time receipt is private at
`services/api/.data/pricing-api-restart-2026-10-28.json`; startup logs are under
the API `.data/logs/pricing-restart-api-2026-10-28*` paths. This background API can
be reused by the launcher; a launcher that did not start it will leave it running.
Normal configured background schedulers resume with the service. No direct
listing, price-reference, booking or payment mutation was used to test pricing.

Follow-up commit message: `fix(launcher): reload API source and reject stale pricing servers`.

## Commit message

```text
fix(pricing): support multi-day estimates from published daily rates

- distinguish daily baselines, fixed packages and duration-specific tariffs
- prefer applicable quoted periods without inventing discounts or changing quotes
- classify installed legacy daily parsers without rewriting stored records
- preserve rate-basis provenance through imports, exports and offline features
- qualify longer-rental baselines visibly and keep explicit price acceptance
- test all 22 domains, period restrictions, inference and mobile form recovery
```
