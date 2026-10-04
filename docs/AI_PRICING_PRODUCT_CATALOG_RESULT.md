# RentHub AI pricing and product catalog result

Date: 4 October 2026

## Outcome

RentHub now adds catalog-assisted product identity to the existing AI pricing
pipeline. A new physical listing searches for a brand first, enables model search
only after a brand is selected, stores a server-verified canonical identity, and
uses that identity to find stronger MongoDB comparables. An owner can always use
manual brand/model entry when coverage is missing or the external provider is
unavailable.

The product catalog identifies products only. It does not supply a rental price
and there are no fixed price rules for a brand, model, condition, or match type.
The predicted price is still produced by the trained XGBoost pipeline, using
dynamic marketplace evidence calculated by Express.

## Final architecture

```text
Flutter Owner listing form
  -> authenticated Express catalog endpoints
  -> fresh MongoDB product_catalog cache
  -> Wikidata entity search when cache is missing/stale
  -> user confirms a result or chooses manual entry
  -> Express verifies and stores canonical identity

Flutter price request
  -> Express verifies canonical identity again
  -> MongoDB active/completed-rental evidence hierarchy
  -> FastAPI renthub-price-v2 contract
  -> trained XGBoost artifact
  -> suggestion + calibrated range + confidence + explanation
  -> owner accepts or overrides the price
```

Flutter never calls Wikidata directly. Provider configuration remains in the
Express environment, and the client cannot make an arbitrary canonical ID trusted.

## Product catalog source

The provider adapter currently uses the open Wikidata `wbsearchentities` API.
The adapter can be replaced behind the same Express service. It is enabled for
all RentHub physical categories: Books, Clothing, Devices, Equipment, and
Vehicles. Coverage varies by product: major companies and notable products are
usually represented, while local, new, obscure, or variant-specific products may
not be.

RentHub applies these controls:

- MongoDB cache collection: `product_catalog`;
- fresh-cache lifetime: 168 hours by default;
- minimum provider request interval: 250 ms by default;
- provider timeout: 4,000 ms by default;
- maximum returned records: 12 by default;
- stale-cache fallback when the provider fails;
- manual entry when neither provider nor cache has a useful match.

When the provider fails and no cache entry exists, Express returns
`503 CATALOG_UNAVAILABLE`. A successful provider search with zero rows remains a
normal `200` no-match response. Flutter therefore no longer presents API,
authentication, or provider failures as "No catalog match found".

These values are configurable through `CATALOG_MODE`, `CATALOG_PROVIDER_URL`,
`CATALOG_CACHE_TTL_HOURS`, `CATALOG_TIMEOUT_MS`,
`CATALOG_MIN_INTERVAL_MS`, and `CATALOG_MAX_RESULTS`.

Wikidata is entity-oriented rather than a complete commercial SKU catalog. Its
search can return organisations, products, or unrelated entities with the same
name. The UI therefore shows the description and requires the owner to select a
result. A weak result is never silently selected.

## Product matching and persistence

The implementation supports four match types:

- `exact_catalog_match`: the selected result matches the entered label or alias
  after case, punctuation, whitespace, and compact-token normalisation;
- `fuzzy_catalog_match`: the owner explicitly selected a non-exact suggestion;
- `catalog_brand_match_model_manual`: the brand is recognised but the model was
  entered manually;
- `manual_entry`: both identity fields are treated as manual.

Examples such as `Talon 2`, `Talon-2`, and `talon2` resolve consistently after a
confirmed catalog selection. Listings store `canonicalProductId`,
`catalogBrandId`, `productMatchType`, and `catalogSource`. Express looks up the
selected identity in its cache and replaces client-supplied labels/source with
the trusted cached values. Invalid or mismatched IDs degrade to manual entry
instead of being accepted as canonical.

## Flutter owner flow

The physical listing editor now provides:

- 400 ms debounced brand and model searches;
- catalog search enabled by default for a new listing;
- a disabled model field until a catalog brand is selected or manual-brand mode
  is chosen;
- result descriptions and explicit selection;
- separate manual fallbacks for brand and model;
- a `Product recognised` state for canonical products;
- a manual-product state explaining that broader evidence will be used;
- suggestion, range, confidence, model source, exact/similar evidence counts,
  warnings, and explanations;
- explicit `Use suggested price`, while preserving free price override.

Search feedback has three distinct states: matches found, a successful search
with no match, and catalog unavailable/error with a retry action. An old API
process that does not advertise the `product-catalog-v1` capability is rejected
by the launcher instead of being silently reused.

Existing manual listings remain editable in manual mode until their owner opts
into catalog search. This avoids changing saved data without confirmation.

## Historical evidence hierarchy

Active listings and completed rentals are queried separately. Completed-rental
effective daily prices remain the stronger historical signal. Within each source,
the narrowest tier with enough observations is selected:

1. exact canonical product + same city;
2. exact canonical product + same state;
3. exact canonical product + Malaysia-wide;
4. exact normalised product text + same state and condition;
5. same subcategory + brand + condition + state;
6. same subcategory + brand + Malaysia-wide;
7. same subcategory + state;
8. same subcategory + Malaysia-wide;
9. same category + state;
10. category-wide.

Exact canonical and exact text tiers can be used with one observation. Brand
tiers require two and broad subcategory/category tiers require three. Within a
tier, relevance considers canonical/text identity, subcategory, brand, condition,
city/state, item-age distance, rental-duration distance, and record recency. These
signals rank evidence; they do not add fixed Ringgit adjustments.

Express dynamically returns counts, median, mean, IQR, freshness, demand/supply
ratio, selected tiers, and exact-versus-similar counts. If FastAPI is unavailable,
Express only emits a clearly labelled robust statistical median when sufficient
evidence and non-zero spread exist. Otherwise it returns `insufficient_data`.

## XGBoost implementation

The price model remains a genuine `XGBRegressor` inside a persisted scikit-learn
pipeline. Categorical fields—category, subcategory, condition, brand, model, and
Malaysian state—use one-hot encoding with unknown-value support. Numeric fields
include item age, expected rental duration, active comparable statistics,
completed-rental statistics, evidence freshness, demand/supply ratio, owner trust
and rating, completed-rental count, and prediction month.

The target is effective daily rental price, not total booking price. The canonical
catalog ID is used to select market evidence and is deliberately not used as an
ordinal ML feature. The artifact remains:

```text
services/ai/models/price_xgboost.joblib
```

Prediction ranges use the 90th-percentile held-out absolute residual rather than
an arbitrary percentage.

## Dataset provenance and evaluation

The current evaluated dataset contains 5,013 rows:

| Source | Rows | Meaning |
| --- | ---: | --- |
| Synthetic | 5,000 | Deterministic FYP development data |
| Real RentHub | 13 | Read-only observations from the configured MongoDB |
| Real active asking | 11 | Current listing daily prices |
| Real completed rental | 1 | Completed booking effective daily price |
| Real accepted booking | 1 | Accepted booking effective daily price |

No scraped/catalog price is used. The catalog provides identity only.

Held-out grouped evaluation from `services/ai/metrics/price_metrics.json`:

| Evaluator | Rows | MAE (RM) | RMSE (RM) | R-squared |
| --- | ---: | ---: | ---: | ---: |
| Selected global/category strategy | 784 | 10.64 | 24.43 | 0.981 |
| Global XGBoost | 784 | 10.31 | 24.00 | 0.981 |
| Category/subcategory median baseline | 784 | 71.30 | 132.92 | 0.432 |

The held-out 90% interval coverage is 90.56%. Only three real-source rows landed
in the test split, so these results mainly describe synthetic-data fit and must
not be presented as production Malaysian market accuracy.

## Confidence

FastAPI confidence combines calibrated relative model uncertainty, active and
completed evidence volume, evidence freshness, input completeness, supported
category status, and product-match quality. Product quality multipliers rank
exact catalog, fuzzy catalog, recognised-brand/manual-model, and fully manual
identity in that order. Express's emergency statistical fallback separately uses
evidence volume, freshness, spread, and the same product-quality ordering.

Confidence does not alter the predicted price. It communicates how much support
the prediction has. An exact product with no completed history can still be low
confidence when the calibrated model range is wide.

## Complete Giant Talon 2 E2E example

The automated E2E test ran the real chain from Express through MongoDB evidence to
the live FastAPI XGBoost artifact with this input:

```text
Category: Vehicles
Specific category: Bicycles
Brand: Giant
Model: Talon 2
Condition: Excellent
Age: 1 year
Location: Kuala Lumpur
Expected rental duration: 1 day
```

Observed result from the current development artifact and test evidence:

```json
{
  "catalogMatchType": "exact_catalog_match",
  "exactActiveListings": 2,
  "selectedActiveTier": "exact_canonical_city",
  "exactCompletedRentals": 0,
  "similarCompletedRentals": 0,
  "suggestedDailyPrice": 117.99,
  "range": [56.81, 179.16],
  "confidence": 0.482,
  "confidenceLabel": "low",
  "modelSource": "category_xgboost"
}
```

The explanation reported the recognised product, two exact active listings, no
completed-rental evidence, the Vehicles category XGBoost model, and the calibrated
residual range. This is a deterministic integration fixture, not a current market
quotation.

## Live Toyota catalog verification

The configured Wikidata provider was exercised through the complete Express API
and an isolated MongoDB cache using `Vehicles -> Cars -> toyota`. The search
returned the canonical `Toyota` automotive manufacturer (`Q53268`), normalised
the lowercase query case-insensitively, and retrieved Corolla, Camry, Vios, and
Hilux model records. Generic category/subcategory relevance ranking places
automotive manufacturers and vehicle models above same-name places or unrelated
entities. There is no Toyota-specific branch or seed record in application code.

## Verification performed

- live Wikidata smoke searches returned records for Sony, Giant, Apple, and Canon;
- complete API suite: 92 passing, 2 optional live E2E tests skipped;
- live Wikidata Toyota API/cache E2E: 1 passing;
- complete Express + MongoDB + FastAPI + XGBoost E2E: 1 passing;
- FastAPI training and contract suite: 14 passing;
- complete Flutter suite: 84 passing, 2 intentionally skipped;
- Flutter analyzer: no issues;
- OpenAPI YAML: parsed successfully.

## Remaining limitations

- Wikidata is not a complete Malaysian retail product/SKU catalog and may return
  ambiguous entities.
- Catalog identity does not provide current Malaysian rental-market prices.
- Marketplace history is still extremely small: one completed-rental observation
  in the current real export.
- Most model training data is synthetic, so real-world accuracy is unproven.
- Manual and brand-only products necessarily use broader evidence and lower
  confidence.
- City matching currently uses normalised place text; it does not calculate a
  geographic distance radius.
- Category-specific specifications such as bicycle frame material or camera
  sensor type are not yet structured in the listing schema.
- Automatic retraining/monitoring and a reviewed production catalog provider are
  future operational work.
