# RentHub AI pricing and product catalog result

## 10 October 2026: searchable products and reviewed rental-price references

### Selection and administrator workflow

Brand/model now open searchable selection sheets with a first page before typing.
Books use Author/publisher and Title/edition. All 22 physical subcategories have
at least three starter brands/authors and two named products/titles per subcategory.
Manual entry remains available during loading, empty results and provider failures.
Identity changes invalidate obsolete IDs and estimates; applying a price is explicit.
See [coverage matrix](PRODUCT_CATALOG_COVERAGE_RESULT.md) for identity sources.

1. Open **Listings → Rental-price references** in the existing administrator portal.
2. Download the template, or review the [20-row starter CSV](data/rental_price_references_starter.csv).
3. Select a UTF-8 CSV, up to 1 MB / 500 observations. Preview shows errors,
   duplicates, daily equivalents and locally resolved product IDs; it writes nothing.
4. Check source links, rental periods and packages yourself. Confirm the review
   checkbox: explicit Malaysian rental quotes, not retail prices, ambiguous minimum
   prices or inseparable service/equipment bundles.
5. Click Confirm import and confirm the dialog. The server revalidates the entire
   original file. Invalid files write no references.
6. View references and explicitly confirm deactivation of incorrect records.

**The starter CSV has not been imported into the live database.** It was validated
in a temporary test database. No source URLs are fetched by the API. Semantic truth
requires administrator review: valid formatting cannot establish that a quote is
genuine, still available or package-comparable.

### CSV and endpoint contract

Required columns:
`category,subcategory,brand,model,quotedAmount,rentalDays,currency,sourceName,sourceUrl,observedDate`.

Optional: `location,state,condition,itemAgeYears,packageNotes`.

Quoted commas/newlines, escaped quotes, CRLF and UTF-8 BOM are supported.
Unknown/duplicate/missing headers, uneven rows, letters/exponents in numbers and
money precision above two decimals fail. Rental days are whole numbers 1–365;
daily equivalents must fit RM1–1,000,000 bounds. Categories must be supported
physical domains. MYR only; dates must be real, non-future YYYY-MM-DD calendar dates;
source links must be HTTPS without credentials/loopback hosts. Optional condition
uses the existing enum; age must be finite/non-negative and at most 100 years.
Obvious minimum-price/service-bundle terms in notes fail, but human review is essential.

Admin-only routes under `/api/v1/admin/pricing-references`:

| Method | Suffix | Purpose |
| --- | --- | --- |
| GET | /template | JSON filename and template CSV content |
| POST | /preview | `{csv}`; read-only rows/errors/counts |
| POST | /import | `{csv,confirmed:true}`; revalidate, import/duplicate counts |
| GET | ?page=1 | 50 references/page, active and inactive |
| PATCH | /:referenceId/deactivate | `{confirmed:true}`; deactivate and audit |

MongoDB `pricing_references` is separate from catalogue identities and bookings.
Records carry `sourceType=external_asking_price`, MY/MYR, source/date, original
amount/duration, normalized daily price, reviewer/time and deactivation details.
Successful import/deactivation writes existing administrator audit records.
Product IDs resolve from local cache or an exact curated identity; unmatched text
remains without an invented match or remote lookup.

A unique key covers domain, normalized brand/model, URL, date and duration.
Reimporting identical observations is idempotent; conflicting amount/package/
condition/location/age fails. Deactivated entries are not revived by reimport.
No transactions are required. Validation failures produce zero writes; a runtime
database failure can leave some validated rows saved on a standalone database.
Refresh and explicitly retry the unchanged file: idempotency prevents duplicates.
Do not assume rollback or automatic write retries.

### Starter provenance

Observations checked on **10 October 2026**, not inferred from retail prices:

| Source | Rows | Domain | Package/period |
| --- | --- | --- | --- |
| [RENTISM price list](https://www.rentism.com.my/price-list/) | 15 | Cameras | Explicit daily camera-body rates; body only |
| [AVMProjector rental page](https://www.avmprojector.com/rental) | 4 | Event equipment | Explicit daily projector tariffs; listed cables/bag/remote, screen/setup excluded |
| [DRIVOR Toyota Camry](https://drivor.my/vehicle/toyota-camry/) | 1 | Cars | Explicit 1–3-day band represented as one day; 400 km/day allowance, deposit/extras excluded |

The opened RENTISM page showed its October 2026 update, not older indexed prices.
AVM tariffs are indicative, subject to confirmation/availability. DRIVOR's minimum
advertised price was not used; the explicit short-period band was used. Unknown
condition, age and location remain empty. Package notes remain visible for review.

These are advertised asking prices, not achieved transactions. This is a small,
non-representative starter sample, not market proof for every product. The other
19 subcategories have no sourced observations in this file. Packages/accessories
can affect comparability; V1 does not learn package equivalence or price components.

### Inference integration and limitations

Only active, reviewed MY/MYR references within the existing 365-day window enter
asking-price evidence, constrained to the selected category **and subcategory**.
They use existing exact-product, same-brand and subcategory tiers. No external
observation from another subcategory enters broad category evidence. Existing
platform-listing broad fallback remains unchanged. Completed-rental queries,
medians, counts and demo provenance remain unchanged.

Existing `comparable_active_*` features now describe the selected combined
asking-price pool: platform listings plus reviewed external quotes. Metadata
separates `marketplace_active_listing_count` and `external_asking_price_count`.
These are selected-tier counts, not all stored records. Expanded owner details
distinguish listings, advertised prices and completed rentals and explain that
asking prices are not evidence of completed transaction prices.

The same fitted features, XGBoost artifact and statistical fallback are used.
No retraining, brand-price rules, fabricated history, new production dependency
or automated scraping was added. Imports can change evidence inputs, but cannot
repair synthetic-heavy training or guarantee different prices for every model.
The artifact/age results below remain the earlier verified baseline; no new
post-import market accuracy is claimed.

### Verification

- API: 56 passed, one optional live-AI E2E skipped. Temporary MongoDB tests cover
  all 22 browse/model domains, identity merge, book subjects, authorization,
  CSV precision/dates/quotes/conflicts/duplicates, preview without writes,
  explicit import, deactivation and asking-price inference. An existing completed
  booking keeps its count, median and provenance after import. Starter preview
  validates 20 rows without writes.
- AI: 16 passed; external counts survive disclosure and reach unchanged fitted
  features without becoming historical rentals.
- Flutter: 203 passed, three skipped; 12 dedicated selector/import tests cover
  manual mode, stale replies, provider errors, retained values and explicit actions.
  Layout tests cover 360/390 px picker and 390/1024/1440 px admin with larger text.
- Web build passed. Targeted analysis is clean. Full analysis retains two
  unrelated Auth0 persistence test parameter errors (`latestLinkProvider` and
  `mobileLinkPollInterval`).
- Administrator CSV selection passes Tab/Enter keyboard tests; generated 390 px
  picker and 1024 px admin previews were visually inspected. Android/iOS native
  file selection and complete keyboard traversal were not manually device-tested.
  Standard Material focusable controls are used;
  widget layout checks are not a substitute for final device/UAT checks.

## 10 October 2026: listing clarity and read-only pricing audit

### UI and recovery

The live Owner listing form is grouped into Details, Photos, Product, Pricing,
and Location/availability. Content is constrained to 680 logical pixels on wider
screens; age and rental length stack on narrow screens or with larger text.
All listing fields remain mounted while scrolling so validation covers the whole
form. Service forms do not show physical product, age, daily-price suggestion or
deposit controls. Existing validation and catalogue/manual-entry paths remain.

“Model”, “Expected rental length”, and “Product found” replace technical labels.
A catalogue match is explicitly not proof of authenticity. Suggestions display
the daily amount, estimated range and a short explanation. Supporting counts
and plain-language provenance are behind “How this estimate was calculated”.
Owners explicitly choose “Use this price”; fetching a suggestion never overwrites
their price. Broad, low-confidence, unseen-model or incomplete-metadata estimates
are labelled “Rough daily estimate”. Synthetic-heavy training is disclosed visibly,
not hidden in the expanded details. The existing confidence score is a heuristic,
not a measured probability of price accuracy, and is no longer shown as a percent.

Shared friendly-error presentation covers live flows and authentication. It
distinguishes connection problems, expired sessions, permissions, validation,
known verification requirements, catalogue failure and generic failures. Valid
API error status/code/details and original controller exceptions remain available
for debugging; raw messages, URLs and paths are not copied into ordinary UI.
Malformed JSON/HTML responses preserve HTTP failure status; successful malformed
responses become `INVALID_RESPONSE`. Valid empty HTTP 204 responses remain supported.
Existing endpoint paths, authentication behaviour and payloads are unchanged.

Failed form actions retain values and existing photo references. The upload preview
keeps selected bytes in memory and offers an explicit retry after failure, without
reopening the picker. It disables duplicate submission while uploading. Price
request failures offer manual entry/retry and clear loading state; stale replies
are discarded after pricing inputs change. No write is automatically retried.
Expired workspace sessions offer the existing local sign-out/sign-in path rather
than repeatedly reloading an unauthorized request.

### Artifact verification

Read-only audit: `services/ai/app/training/audit_pricing_clarity.py`.
The service at `http://127.0.0.1:8001` was reachable. Its reported artifact path,
model version, controlled prediction and evaluation source counts matched the
local configured artifact. Embedded artifact metrics exactly matched the saved
`price_metrics.json`.

- Model version: `renthub-price-v2-66aad34c4295`.
- Artifact SHA-256: `2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
- Training rows: 5,000 synthetic and 19 labelled `real`.
- Non-synthetic targets: 13 active asking prices, 4 accepted bookings,
  and only 2 completed rentals. These labels are not independent verification
  of real-world marketplace transactions.
- Held-out `real` subset: only 5 rows, MAE RM24.38 and R² -5.98. This small,
  mixed-target subset does not establish product-specific market accuracy.

### Controlled predictions

Category Devices, subcategory Smartphones, condition Excellent, Kuala Lumpur,
one-day duration, active median/mean RM85 (4 listings), historical median/mean
RM85 (1 rental), freshness 5 days, owner trust 80, rating 4.5, 20 completed
rentals and month 10 were held fixed. These are controlled inference inputs,
not newly created transactions or asserted market prices. They do not reproduce
every owner/evidence input from the RM71.44 screenshot.

| Brand/model, age 1 | Daily prediction | Training identity coverage |
| --- | ---: | --- |
| Apple / iPhone 17 Pro Max | RM65.30 | Brand represented; model unseen |
| Samsung / Galaxy S25 Ultra | RM65.30 | Brand represented; model unseen |
| Unseen brand A / Unseen model A | RM65.30 | Both unseen |
| Unseen brand B / Unseen model B | RM65.30 | Both unseen |

All used the existing global model with broader subcategory evidence. Identical
predictions are possible and must not be disguised with arbitrary brand offsets.

| iPhone 17 Pro Max age (years), all other inputs fixed | Daily prediction |
| ---: | ---: |
| 0 | RM67.14 |
| 1 | RM65.30 |
| 3 | RM58.50 |
| 5 | RM50.32 |
| 8 | RM38.77 |

Age genuinely reaches the fitted pipeline and affects these predictions.
Held-out permutation MAE increase: age 14.0210, brand 0.0590, product model 0.0.
Age sensitivity largely reflects synthetic training relationships; it is not
evidence of calibrated depreciation for this phone. No global monotonic rule or
manual depreciation formula was added.

Flutter serializes `itemProfile.item_age_years` and `rentalDurationDays`; Express
preserves them as FastAPI `item_profile.item_age_years` and
`rental_duration_days`; FastAPI places them in the ordered fitted feature row.
Existing Flutter/API contract tests and new AI controlled-input tests verify this
handoff and that identity changes reach inference with fixed evidence.

### MongoDB cold-start audit

`services/api/src/scripts/auditPricingEvidence.js` performs read-only inspection,
disables automatic collection/index creation, makes no provider calls and prints
aggregate counts only. The audit used the existing 365-day evidence window,
completed physical rentals with captured/settled payment, positive base price,
and the same tier selector. Demo seed inclusion was disabled.

| Query | Exact active / completed | Selected active evidence | Selected completed evidence |
| --- | --- | --- | --- |
| Devices / Smartphones / Apple / iPhone 17 Pro Max | 0 / 0 | 3 category-local listings, median RM85 | 1 category-wide rental, median RM85 |
| Vehicles / Cars / Toyota / Camry | 0 / 0 | 3 category-wide listings, median RM150.83 | 1 category-wide rental, median RM150.83 |

The phone had 4 total active candidates but only 3 in the selected tier. Candidate
counts are not the same as the records actually used. Both selected historical
rows were labelled marketplace; zero eligible demo-seed rows were found in these
categories. “Marketplace” is a provenance label, not independent transaction
verification. iPhone identity was cached; no exact Toyota/Camry canonical cache
record was found by this normalized audit query. This does not establish that a
live provider cannot return that model.

### Remaining accuracy work

The catalogue identifies products, not rental value. Reliable differentiation
needs reviewed Malaysian product-specific asking prices and, preferably,
completed rental observations, with canonical model, condition, item age,
location, duration, observation date and provenance. Asking and accepted prices
must remain distinct from completed rentals. Evaluation needs a sufficiently
large real-only held-out set with product grouping, reported separately from demo
and synthetic examples. No external ingestion, seeding, retraining, price rules,
database migration or new production dependency was performed in this task.

### Verification (this update)

- Full Flutter suite: 191 passed; 3 skipped (2 optional live tests and 1 opt-in
  screenshot capture). The screenshot capture was also run separately with a
  readable SDK font and passed. New pricing/error/upload/recovery tests: 17 passed.
- Relevant API tests: 28 passed; 1 optional live E2E skipped.
- AI pricing/audit tests: 15 passed.
- Application and new-test analysis: no issues.
- Full analysis still reports the two pre-existing undefined parameters in
  `test/auth0_persistence_test.dart:41,43` (`latestLinkProvider`,
  `mobileLinkPollInterval`); these unrelated Auth0 tests were not repaired here.
- Web build succeeds. Existing Socket.IO WebAssembly dry-run and Cupertino font
  warnings remain; the JavaScript build succeeds.
- Responsive widget checks cover 360, 390 and 1024 pixels with 1.4× text scaling.
  Readable test-rendered pricing/listing PNG previews were inspected. Physical
  Android keyboard/device testing was not performed.
- Dart formatting and `git diff --check` passed. No credentials or personal
  document contents were added to logs, test captures or documentation.

Test-only preview files (ignored build artifacts):
`apps/renthub_flutter/build/ui-checks/listing-pricing-390.png` and
`apps/renthub_flutter/build/ui-checks/pricing-card-390.png`. These use controlled
fixture amounts for UI verification, not hardcoded production rental prices.

Run read-only audits from their respective service directories:

```powershell
# services/ai
.\.venv\Scripts\python.exe -m app.training.audit_pricing_clarity
# services/api
node src/scripts/auditPricingEvidence.js Devices Smartphones Apple "iPhone 17 Pro Max"
node src/scripts/auditPricingEvidence.js Vehicles Cars Toyota Camry
```

Earlier results below are retained as dated historical implementation notes.

Date: 4 October 2026

9 October update: pricing now distinguishes product-specific evidence from
broad estimates, discloses unseen identities/synthetic-heavy training and
withholds numeric predictions when there is no usable price evidence. Catalog
identity alone does not establish a rental price. See
[photo and pricing safeguards](ITEM_PHOTO_AND_PRICING_SAFEGUARDS_RESULT.md)
for the audit, limitations and regression results.

## Outcome

RentHub now routes catalog searches through a product-domain provider selected by
the Express API. Flutter never contacts an external catalog directly. Brand and
model results are constrained by category, subcategory, and the selected
canonical brand; a provider failure is different from a valid zero-result search.

The catalog provides identity only. It does not provide or scrape rental prices.
Price recommendations continue to use MongoDB marketplace evidence followed by
the trained FastAPI XGBoost pipeline.

## Provider and domain strategy

| RentHub domain | Provider | Validation rule |
| --- | --- | --- |
| `Vehicles -> Cars` | NHTSA vPIC | Makes come from the vPIC car make list; models are requested by the selected vPIC make ID. |
| `Devices -> Smartphones` | Wikidata Query Service | SPARQL only returns manufacturers connected to smartphone model/model-series classes; models must have the selected manufacturer ID and an allowed smartphone type. |
| `Books -> *` | Open Library | The first field resolves an author ID; titles come from that author's Works endpoint. |
| Other physical subcategories | validated Wikidata fallback | Results must contain category/subcategory semantics and an entity-type marker. Unvalidated text matches are discarded. |

Provider selection is generic and based on RentHub taxonomy, not on individual
brands. There is no Apple, Toyota, or other manufacturer-specific API branch.

The main endpoints are:

```text
GET /api/v1/catalog/brands?category=...&subcategory=...&query=...
GET /api/v1/catalog/models?category=...&subcategory=...&brand=...&catalogBrandId=...&query=...
```

`query` is optional for the model endpoint. This permits the first model page to
load immediately after a canonical brand is selected. Entering two or more model
characters still performs debounced autocomplete.

MongoDB cache entries are scoped to category, subcategory, entity type, and
provider source. Old generic Wikidata car/smartphone cache records therefore do
not override the domain provider. Fresh cache lifetime is 168 hours by default;
stale cache may be used only when its matching provider is unavailable.

Configuration:

```text
CATALOG_MODE=domain
CATALOG_PROVIDER_URL=https://www.wikidata.org/w/api.php
CATALOG_WIKIDATA_SPARQL_URL=https://query.wikidata.org/sparql
CATALOG_VEHICLE_PROVIDER_URL=https://vpic.nhtsa.dot.gov
CATALOG_BOOK_PROVIDER_URL=https://openlibrary.org
CATALOG_CACHE_TTL_HOURS=168
CATALOG_TIMEOUT_MS=4000
CATALOG_MIN_INTERVAL_MS=250
CATALOG_MAX_RESULTS=12
```

`CATALOG_MODE=wikidata` remains accepted for configuration compatibility, but
the router still applies the domain strategy. `disabled` disables all providers.

## Filtering behavior and UI states

The old implementation ranked every result returned by Wikidata text search.
That allowed labels such as Apple Music, application software, Applied Physics
Letters, and microbiology journals to appear in a smartphone brand field.

The smartphone path no longer uses generic text results. A manufacturer must be
linked by Wikidata's manufacturer property to an entity classified as a
smartphone model, smartphone model series, or mobile-phone series. Model queries
use the selected canonical manufacturer ID. The general fallback separately
requires both domain terms and a brand/product entity marker before ranking.

Flutter presents three different outcomes:

1. match found: selectable canonical results are displayed;
2. no match found: the provider succeeded with zero valid results and manual
   entry remains available;
3. catalog unavailable/error: an error card and retry action are displayed.

Express returns `503 CATALOG_UNAVAILABLE` when a provider fails and no matching
stale cache exists. It never converts that condition to an empty array.

## Apple smartphone verification

The live integration test requested:

```text
Devices -> Smartphones -> "appl"
```

It returned canonical `Apple` (`wikidata-smartphones:Q312`) and no journal,
software, or streaming-service entity. A query-less model request using that
canonical brand returned an initial page containing iPhone models. Every model
was retrieved through the smartphone type + manufacturer graph constraint.

## Toyota car verification

The live integration test requested:

```text
Vehicles -> Cars -> "toyota"
```

It returned canonical `Toyota` (`nhtsa-vpic:448`). Model lookup used that make ID
and retrieved common Toyota models including Camry and Corolla. Lowercase brand
input is normalized case-insensitively; display casing comes from the provider.

## Product matching and persistence

Listings store `canonicalProductId`, `catalogBrandId`, `productMatchType`, and
`catalogSource`. Express verifies the selected identity against its cache before
trusting it. A mismatched ID degrades to manual entry.

Supported match types remain:

- `exact_catalog_match`;
- `fuzzy_catalog_match`;
- `catalog_brand_match_model_manual`;
- `manual_entry`.

## Completed-rental evidence and cold start

The configured development MongoDB was inspected read-only on 4 October 2026:

| Check | Count |
| --- | ---: |
| Eligible completed rentals (`captured` or `settled`) | 1 |
| Eligible completed Toyota/Cars rentals | 0 |
| Cached Toyota/Cars catalog records before provider migration | 13 |

Toyota/Camry's zero historical-rental result is therefore correct. Catalog
records identify products; they are not transactions and cannot be counted as
completed rentals.

Completed and active evidence are queried separately. Each source uses this
narrow-to-wide hierarchy:

1. exact canonical product, city;
2. exact canonical product, state;
3. exact canonical product, Malaysia-wide;
4. exact normalized brand + model, Malaysia-wide;
5. same subcategory + brand + condition + state;
6. same subcategory + brand, Malaysia-wide;
7. same subcategory + state;
8. same subcategory, Malaysia-wide;
9. same category + state;
10. category-wide.

The price flow prefers sufficient completed-rental statistics, then sufficient
active comparable listings, and otherwise relies on XGBoost with low-confidence
cold-start warnings. No completed rental is fabricated.

### Optional demo history

Development-only history can be created explicitly:

```powershell
cd services/api
npm.cmd run seed:pricing-demo
```

Every inserted listing and booking is marked `sourceType=demo_seed`. It is
excluded from live pricing by default. A developer may opt in locally with:

```text
PRICING_INCLUDE_DEMO_SEED=true
```

Production configuration rejects that option. Pricing exports label these rows
as `source_type=demo_seed` and use separate `demo_seed_*` target sources, so they
cannot be reported as real transactions. API responses also report marketplace
and demo-seed completed counts separately and warn when demo evidence is used.

## Item-age audit

The end-to-end contract is:

```text
Flutter item age
  -> Express itemProfile.item_age_years
  -> FastAPI item_profile.item_age_years
  -> numeric__item_age_years in the fitted pipeline
  -> XGBoost prediction
```

The Flutter/API regression tests assert that the entered value reaches the AI
request. FastAPI controlled tests keep product identity, condition, duration,
market evidence, owner fields, state, and month fixed while changing only age.

The previous artifact barely reacted: ages 0, 1, 3, 5, and 8 produced about
RM101.03, RM100.99, RM100.99, RM100.99, and RM100.59. Native age importance was
only 0.00131. The cause was training leakage: comparable medians were generated
from the same age-adjusted latent target, so the model could ignore age.

Synthetic bootstrap generation now keeps wider-market comparable medians
separate from subject-item depreciation. It uses category-specific training-data
relationships. Devices and Vehicles have category-specific non-increasing age
constraints; Books have no such global constraint because fiction and
collectibles may be stable or appreciate. There is no inference-time rule such
as subtracting a fixed Ringgit amount per year.

Controlled predictions from the retrained artifact:

| Age (years) | Devices / Smartphones (RM/day) | Vehicles / Cars (RM/day) |
| ---: | ---: | ---: |
| 0 | 81.05 | 94.65 |
| 1 | 78.14 | 91.43 |
| 3 | 68.39 | 72.51 |
| 5 | 57.05 | 66.09 |
| 8 | 42.35 | 51.96 |

Held-out permutation importance measured the mean MAE increase when item age was
shuffled:

- global: RM13.80;
- Devices: RM22.11;
- Vehicles: RM32.80;
- Books: RM0.33.

Native XGBoost importance for `numeric__item_age_years` is 0.02391. The much
smaller Books permutation effect is expected and confirms that a single global
depreciation rule was not imposed.

The reproducible audit command is:

```powershell
cd services/ai
.\.venv\Scripts\python.exe -m app.training.audit_price_age --category Devices
```

## Dataset and evaluation

The retrained dataset contains 5,013 rows: 5,000 deterministic synthetic
bootstrap rows and 13 MongoDB observations (11 active asking prices, one
completed rental, and one accepted booking). No catalog price is used.

| Evaluator | Test rows | MAE (RM) | RMSE (RM) | R-squared |
| --- | ---: | ---: | ---: | ---: |
| Selected global/category strategy | 808 | 10.39 | 24.72 | 0.978 |
| Global XGBoost | 808 | 10.36 | 24.14 | 0.979 |
| Category/subcategory median baseline | 808 | 66.10 | 128.37 | 0.394 |

Held-out 90% interval coverage is 90.10%. These metrics mainly measure the
synthetic bootstrap distribution and must not be presented as production
Malaysian-market accuracy.

## Remaining limitations

- NHTSA vPIC is authoritative vehicle metadata but is US-oriented; some
  Malaysia-only makes/models may be absent.
- Wikidata's structured smartphone coverage is incomplete and may omit new or
  poorly modelled devices.
- Open Library's author/work model does not provide a complete publisher or
  edition/SKU catalog; manual entry remains necessary.
- The validated fallback intentionally prefers false negatives over unrelated
  entities.
- Real RentHub history remains too small for production price validation.
- The item-age effect is learned mainly from explicitly labelled synthetic
  bootstrap data until sufficient reviewed marketplace observations exist.
- Automatic retraining, drift monitoring, and production catalog SLAs remain
  future operational work.

## Verification performed

- Express/API: 105 passed, 3 optional E2E tests skipped;
- live NHTSA + Wikidata catalog E2E: 2 passed;
- FastAPI/AI: 16 passed (one dependency deprecation warning);
- Flutter: 91 passed, 2 intentionally skipped;
- Flutter analyzer: no issues;
- OpenAPI YAML: parsed successfully.
