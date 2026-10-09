# RentHub AI pricing and product catalog result

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
