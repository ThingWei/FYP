# AI pricing: real-world evidence and feedback-loop improvement

Latest follow-up: [pricing suitability, recovered source observations and frozen evaluation](AI_PRICING_QUALITY_AND_EVALUATION_RESULT.md).
The R50 cannot inherit higher-spec EOS R prices solely from its name. A new
read-only audit reports 313 currently eligible asking observations, 249 offers
and no verified completed rentals; all eligible references lack condition/age.
The deployed-model forward-time check reports insufficient data (0/24 predictions)
and an unchanged artifact checksum. Recovered kit quotes and two new-source
candidates remain private previews, without imports or permission declarations.

28 October follow-up: [similar-item pricing selection and clarity](SIMILAR_ITEM_PRICING_RESULT.md).
This changes comparable retrieval and disclosure without relaxing provenance or
claiming independently measured accuracy gains.

Functional test data: [12 source-based demo drafts](MARKET_BASED_DEMO_LISTINGS_RESULT.md)
were subsequently created at the user's request. They remain excluded from clean
evidence; no historical transactions were generated.

Latest: [source cleanup and one-command frozen review](PRICING_SOURCE_CLEANUP_AND_READINESS_RESULT.md).
The old source onboarding state below is retained as audit history.

Audit and implementation: **27 October 2026, Malaysia time**. No live listings,
bookings, rentals, payment histories, source settings or deployed model artifacts
were changed. This work improves evidence hygiene; it does not establish better
real-world numerical accuracy.

Later follow-up: [source diagnostics, transaction collection and frozen evaluation](PRICING_EVIDENCE_FOLLOWUP_RESULT.md).
The older product audit now also uses the strict clean-evidence export policy.

## 1. Confirmed implementation and feedback risk

The existing flow is Flutter → Express catalogue identity/comparable selection →
FastAPI fitted XGBoost/category pipeline → an advisory suggestion. Product
recognition is separate from rental-price evidence. Existing fallback statistics,
MYR limits and manual pricing remain available.

Before this change, Flutter's **Use this price** only copied the amount. Listings
had no price-origin metadata. Live selection read active physical listings and
labelled them marketplace listings; the export labelled active prices `real`
unless marked `demo_seed`. The completed-rental path relied on booking/payment
status and current listing metadata rather than independent price provenance,
actual payment mode and immutable historical product details. Consequently an
accepted AI price could influence later suggestions and future training.

This is a confirmed code-path risk, not proof that every existing price was
AI-generated. Amount equality cannot establish origin, and no old record was
relabelled. The user's description of their test activity is not converted into
fabricated transaction verification.

Read-only inspection found:

| Item | Finding |
|---|---|
| Physical listings | 14; 3 active; all 14 have unknown price origin |
| Booking records | 25; 2 completed |
| Payment records | 25; all explicitly simulated |
| Completed-booking payment evidence | One has simulated payments; one has no payment evidence |
| Independently verified achieved rental evidence | None established by this audit |
| External asking-price observations | 334 active/technically eligible, covering 16/22 subcategories |
| External age/condition coverage | Zero observations with either field |
| Database commands used | `find` and `getMore`; zero writes/index or collection creation |

## 2. Implemented evidence policy

Optional `priceProvenance` is saved on future physical-listing writes. Origins are
unknown, owner-entered, AI-suggested, AI-edited and server-reserved
external-reference-derived. Flutter records explicit acceptance and later edits;
reopening preserves origin. Unrelated edits preserve existing provenance.

Declarations remain **unverified**. The API rejects attempts to submit review
status/reviewer metadata, and price edits cannot wash AI lineage into an
independent owner-entered price. Existing clients can omit the declaration; no
default grants independence. Existing records remain unknown without a migration.
Review status is bound to price/product context; relevant changes invalidate it.
Ordinary listing approval does not independently verify a price. No bulk-review
or retrospective relabelling operation was added.

One shared policy now gates live evidence and exports:

- AI-derived, unknown, unreviewed owner prices, demonstration records and known
  external-derived listing copies are excluded from clean evidence.
- A genuine historical observation requires a saved independently reviewed item
  profile and explicit successful nonsimulated payment evidence. Legacy status
  markers, missing payments and demo checkout do not satisfy this requirement.
- Future physical bookings save a server-created immutable pricing/item-profile
  snapshot, including provenance and available catalogue type. Later listing
  edits do not change that booking's evidence meaning. Snapshots/reviewer details
  are excluded from ordinary booking/public listing responses.
- Explicit staged exports can retain labelled demo diagnostics, but they cannot
  supply clean comparable features or become real training/evaluation targets.
- Future Python training excludes legacy `real` rows without affirmative origin/
  independence metadata, AI lineage and simulated rows. Synthetic generation
  was not expanded or executed by this task.

The database's existing values and statuses remain unchanged. When this code is
deployed, some suggestions will become unavailable or broader because their old
evidence was unknown/AI-derived. Manual pricing remains available. This is the
chosen strict policy, not a source outage to hide by restoring contaminated rows.

## 3. Matching, periods and deduplication

All comparable tiers/counts now require compatible category, subcategory and
product type, with existing edition/variant/package rules. Canonical IDs cannot
override incompatible domains. Broader incompatible category context does not
increase product-comparable counts. Mice, keyboards, monitors, laptops, consoles
and controllers have separate pricing routes; server catalogue metadata is used
where available, with bounded joins rather than external manufacturer calls.

Unknown age/duration is no longer converted into zero for evidence ranking.
External missing condition/age remains null in exports. No depreciation rule,
invented age, price table or artificial historical observation was introduced.
Original quoted amounts and rental periods are retained; multi-day averages are
not described as advertised one-day prices. Historical base amounts use original
booked days where saved, so extensions do not dilute the original daily rate.

Automatic and manual observations share originating-offer identity. Duplicate
unchanged quotes cannot increase exported sample counts, and a derived listing
cannot duplicate its source quotation. Conflicting same-time observations still
fail closed. Disabled/deactivated/stale source observations retain existing
exclusion and failed-refresh behaviour. Nothing was newly enabled.

## 4. Coverage and source research

Counts below are **technical eligibility under existing source controls**, not
proof of reuse permission, exact-model coverage or achieved transaction prices.
Every populated domain except Event equipment has observations from only one
website. Different duration bands are not independent product offers.

| Category | Specific category | Observations | Distinct offers |
|---|---|---:|---:|
| Devices | Smartphones | 2 | 2 |
| Devices | Cameras | 181 | 181 |
| Devices | Computers | 3 | 3 |
| Devices | Audio | 8 | 8 |
| Devices | Gaming | 6 | 2 |
| Devices | Other devices | 6 | 6 |
| Vehicles | Cars | 73 | 13 |
| Vehicles | Motorcycles | 15 | 15 |
| Vehicles | Bicycles | 10 | 10 |
| Vehicles | Other vehicles | 0 | 0 |
| Equipment | Event equipment | 16 | 16 |
| Equipment | Tools | 1 | 1 |
| Equipment | Sports equipment | 0 | 0 |
| Equipment | Other equipment | 5 | 5 |
| Books | Textbooks | 0 | 0 |
| Books | Reference books | 0 | 0 |
| Books | Fiction | 0 | 0 |
| Books | Other books | 0 | 0 |
| Clothing | Formal wear | 1 | 1 |
| Clothing | Costumes | 3 | 3 |
| Clothing | Traditional wear | 3 | 3 |
| Clothing | Other clothing | 1 | 1 |

The existing registry/adapters and stored source state were inspected. Parser
regressions use fixtures; they do not prove every live page still parses today.
Source controls, parser availability and reuse clearance are distinct:

| Sources | Existing state | Research/remaining requirement |
|---|---|---|
| RENTISM | Enabled adapter, stored observations | [October price list](https://www.rentism.com.my/price-list/) is readable; package/promotional distinctions remain important. No new reuse approval recorded. |
| ITPA, Cilt Tech, DRIVOR, Alquiler, Ecocana | Enabled adapters, stored observations | Existing parser tests retained; no new collection or independent reuse verification performed. |
| The Rental Guy, PC Rent | Enabled Event adapters | Specification-only rates must not become named-model evidence. |
| JomRentPro, Partymix, Futago | Enabled adapters | Preserve bundles, garment types, duration periods and missing brand/condition information. |
| iRent | Parser implemented, not newly enabled | Terms-page retrieval timed out during this research pass. Access/reuse review remains unresolved. |
| RentSmart | No usable adapter | [Direct electronics page](https://rentsmartasia.com/product-category/rent-equipment/electronics/) still exposes no product quotations. Search snippets are not evidence. |
| 12RENT | Parser implemented, not newly enabled | Public robots-policy retrieval was unavailable; do not bypass the unresolved restriction. |
| Goritta | Written-permission gate | No written reuse evidence supplied; remain blocked. |
| AVM | Optional disabled candidate | No new onboarding or collection. |

The Rental Guy's [camping page](https://therentalguy.com.my/camping-equipment-2/)
publishes individual one-day reference rates, separate bundles, date-specific
final pricing and tax/delivery distinctions. A **research-only parser** is prepared
for individual camping tents under the existing Sports equipment domain. It is
not registered in the live allowlist/scheduler and was tested with invented
parser-fixture values, not imported market data. Unknown maker/model remains
specification-only. New page collection still needs access/reuse clearance.

No compatible Malaysian per-title book dataset was established. Library
memberships, overdue fines and retail prices must not fill those rental gaps.

## 5. Review preview and why additional listings are not the priority

The read-only audit saved three new private files under
`services/api/.data/evidence/pricing-real-world-2026-10-27-v1/`:

- `summary.json`: bounded aggregate audit and all-22 coverage.
- `observations.json`: 334 existing stored asking observations for internal
  diagnostics, explicitly marked as not independently reuse-cleared by this audit.
  No emails, private addresses/coordinates, reviewer IDs or identity documents
  are exported.
- `preview.json`: **zero cleared observations**, shortfall 100. No explicit
  reuse-review evidence was supplied. Enabled sources and CSV review were not
  promoted into permission declarations. No placeholder observations were added.

The preview generator accepts an explicit local reuse-review file containing
source ID (or manual-source hostname), status, reviewer, checked date and evidence
reference. These must reflect an actual review. It selects up to 100 distinct
offers, prioritizing sparse domains, retaining source URL/date/period/provenance,
and leaving unknown age/condition/brand null. It never inserts listings or quotes.

Creating another 50–100 listings from these quotations would mostly duplicate
existing evidence and risk reinforcing price feedback. Direct independent price
observations offer more benefit. Demonstration listings remain presentation data,
not additional transactions or independent price observations.

## 6. Existing model and frozen evaluation

The configured local bundle is `renthub-price-v2-66aad34c4295`, trained
6 October 2026. Its saved metrics match the artifact. It contains 5,000 synthetic
rows and 19 legacy `real`-labelled rows (13 asking, 4 accepted, 2 completed), but
those labels do not establish genuine transactions or independent price origin.
It retains no row-level training manifest. The previously high mixed-data scores
must not be presented as validated Malaysian rental-market accuracy.

The existing evaluator now defaults to **frozen deployed-artifact evaluation**.
Candidate fitting is an explicit separate `--mode candidate` operation; none was
run on this live export. Fitted feature order, model version and weights remain
unchanged. Features are rebuilt using earlier available history, excluding future,
late-known, same-product/originating-offer and demo/unknown evidence.

Actual default chronological diagnostic: 334 asking observations; 310 earlier
history rows; 24 later asking targets. All 24 lack compatible earlier evidence
under the strict rules, so prediction coverage is **0/24** and MAE/RMSE/R² and
baseline errors are **not evaluable**. No number was manufactured to replace
abstention. This is a cold-start/evidence limitation, not a successful accuracy
result. No completed-rental holdout is independently established.

The evaluator reports source/category/subcategory cohorts, denominators,
abstentions and null errors for insufficient cohorts. R² is null for too few or
constant targets. Even a numerically populated future report remains diagnostic
where training overlap cannot be verified against the old bundle's missing
manifest. Future candidates need explicit retained training manifests and the
same defensible held-out targets for comparison.

Private evaluation reports are under `services/ai/.data/evaluation/`, prefixed
`pricing-real-world-2026-10-27`. Model SHA-256 remains:
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
The running services were not restarted or deployed during this work.

## 7. Commands and prioritized next work

From `services/api`:

```powershell
npm.cmd run audit:pricing-real-world -- --output .data/evidence/NEW-REVIEW-DIRECTORY
# Add --reuse-reviews <local-reviewed-JSON> only after actual source review.
```

From `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/evidence/NEW-REVIEW-DIRECTORY/observations.json `
  --mode deployed --report .data/evaluation/NEW-REPORT.json
```

Existing output directories/files are never overwritten. No audit command starts
the application, source jobs, model training or an import. New booking/listing
metadata is written only through future normal user actions after code deployment.

Priority: (1) deploy the reviewed hygiene fixes; (2) obtain and record actual
source-use clearance; (3) add independent offers in sparse domains, retaining
time/period/package details; (4) collect permissioned genuine transaction evidence
separately from demo checkout; (5) evaluate meaningful held-out cohorts before
considering a separately trained candidate. Retraining is **not justified by this
audit alone**, and no candidate was automatically trained or deployed.

## Verification

Regression coverage includes price acceptance/edit/reopen/failure, forged review
metadata, missing legacy origin, immutable snapshots, simulated/missing payments,
cross-type matching, null ages, duplicate offers, duration bands, temporal leakage,
source restrictions and read-only exports. Mobile form tests cover 360/390 pixels
with increased text size and desktop widths. Final results are recorded below.

| Check | Actual result |
|---|---|
| Full API suite | 496 passed, 3 existing skips, 0 failed |
| Full AI suite | 603 passed; existing dependency/controlled-fixture warnings only |
| Full Flutter suite | 477 passed, 3 existing skips |
| Flutter analysis | No issues found; no Auth0 analysis errors in this run |
| Flutter web build | Passed |
| Android debug APK build | Passed |
| OpenAPI YAML parsing and `git diff --check` | Passed |
| Final database preservation check | Aggregate counts and source settings unchanged; only `find`/`getMore` used |
| Final deployed model SHA-256 | Matches the original checksum above |

Nonblocking build warnings remain in existing dependencies: Socket.IO's optional
Wasm compatibility check, an optional Cupertino icon font reference, and future
Kotlin Gradle plugin migration for Firebase/preferences plugins. The standard web
and Android builds both succeeded. No unrelated dependency upgrade was made.

Read-only/private deliverables:

- `services/api/.data/evidence/pricing-real-world-2026-10-27-v1/summary.json`:
  bounded aggregate audit, including all 22 domains and existing source states.
- The adjacent `observations.json`: 334 existing stored asking-price rows for
  diagnostic evaluation, explicitly not newly permission-cleared observations.
- The adjacent `preview.json`: zero cleared rows and a documented shortfall of
  100 pending explicit reuse-review evidence.
- `services/ai/.data/evaluation/pricing-real-world-2026-10-27-v2.json`: frozen
  artifact evaluation, 24 holdout abstentions and no independently validated
  numerical accuracy result.

These private files are excluded from version control. No service restart,
source collection, live import, historical cleanup, candidate training or model
deployment was performed. Physical-device retesting can follow deployment;
automated checks do not claim an Android on-device review occurred.

## Follow-up: safeguard verification and source-review preparation

The follow-up check added persisted draft reopening to the API regression: apply
an AI price, save, read through Owner listings, edit the price, make an unrelated
edit and reopen again. The saved price remains AI-edited and unverified. Forged
review metadata is rejected without changing the saved amount. All **27 focused
API tests passed**, using an isolated temporary database. All **28 focused
Flutter tests passed**, with one existing skipped visual test, including price
acceptance, failed-save/retry preservation and mobile/desktop form layouts.
No live marketplace write or service restart was used for these checks.

A private follow-up pack was prepared under
`services/api/.data/evidence/pricing-source-review-followup-v1/`:

- `reuse-reviews.pending.json`: 16 source-review tasks, all explicitly pending;
  reviewer, approval date and permission/evidence reference remain empty.
- `coverage-priorities.json`: all 22 subcategories ordered by distinct offers,
  using the earlier bounded audit. This is a task list, not refreshed quotes.

The pending review file is compatible with the audit's review input. Pending
entries cannot clear observations. A real review must record its outcome,
applicable conditions and evidence before any entry becomes approved. Written
publisher permission is required where the applicable source conditions demand
it; the file does not assert that every public price fact requires a new licence.
Do not fill empty fields with invented approvals or use environment flags as
review evidence. Keep source collection/enablement as a separate deliberate step.

Bounded web checks found:

- [RENTISM terms](https://www.rentism.com.my/terms-conditions/) describe rental
  procedures; no explicit automated collection/reuse clearance was established
  from that page. The earlier guessed `/terms-and-conditions/` URL did not resolve
  through the research tool; the correct published route is `/terms-conditions/`.
- [iRent terms](https://irent.my/terms-of-service/) timed out. This is unresolved
  access, not evidence of a prohibition or permission.
- [The Rental Guy camping page](https://therentalguy.com.my/camping-equipment-2/)
  remains readable with individual one-day references, before-tax treatment and
  separate bundles. Access and quote semantics do not establish reuse clearance.
- The Alquiler `llms.txt` and a guessed Rental Guy terms URL were unavailable
  through this research tool; no source-wide access or policy conclusion follows.

No observations were cleared or imported by this follow-up. The next evidence
work is actual source-review completion, prioritizing missing domains and scarce
distinct offers. No new accuracy result or retraining recommendation follows.

## Commit message

```text
fix(pricing): prevent AI price feedback and enforce clean evidence provenance

- track declared price origin and retain AI lineage through listing edits
- gate live comparisons, exports and future training on independent evidence
- exclude simulated/unverified rentals and snapshot future booked item profiles
- constrain comparables by product type, period, edition and package
- deduplicate originating offers and preserve unknown age/condition
- add read-only evidence audits, permission-gated previews and frozen evaluation
- prepare a disabled camping-source research parser and document real-data gaps
- preserve live records, source settings and deployed model artifacts
```
