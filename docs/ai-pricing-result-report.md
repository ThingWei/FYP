# RentHub AI pricing implementation result

Date: 4 October 2026

## Outcome

The Owner listing flow now uses a genuine XGBoost regression pipeline with a
versioned inference contract and MongoDB-derived marketplace evidence. The prior
hard-coded product records, category prices, condition/age multipliers and
external-comparable weighting rules were removed.

The code is complete and tested as a development implementation. Production
accuracy is **not established**: the current evaluated dataset contains 5,000
explicitly labelled synthetic rows and only 13 real MongoDB observations. The
reported metrics are therefore reproducibility evidence, not a claim about live
Malaysian rental-market accuracy.

## Baseline audit

The replaced implementation had four material problems:

- training targets were produced by hand-authored category and condition rules;
- the train/test split could place the same product family on both sides;
- inference ranges were derived from a general error value rather than calibrated
  held-out residuals;
- Express could use static product examples and hand-tuned resale/rental factors.

Those paths are no longer used. `marketPriceComparables.js` and its static-data
test were removed.

## Files changed and purpose

- `services/ai/app/training/pricing_dataset.py` defines the canonical,
  provenance-aware dataset and validation.
- `services/ai/app/training/train_tabular_models.py` trains/evaluates the global
  and qualified category XGBoost pipelines, calibrates intervals, writes the
  bundle atomically and validates it from a fresh Python process.
- `services/ai/app/services/pricing.py`, `schemas.py` and `main.py` enforce the
  versioned runtime contract, cached compatible artifact and health status.
- `services/ai/metrics/price_metrics.json` contains generated held-out results;
  AI tests cover data, leakage, model type, categories, unknowns and failure modes.
- `services/api/src/modules/listing/pricingEvidence.js` implements comparable
  tiers, robust statistics and evidence-based fallback confidence.
- `services/api/src/modules/listing/listing.service.js` now builds the trusted
  Mongo evidence and canonical AI request; its static comparable module was
  deleted.
- `services/api/src/scripts/exportPricingData.js` adds the anonymised, read-only
  historical export command; API tests cover hierarchy, fallback and injection
  prevention.
- `packages/api_contracts/openapi.yaml` documents the price request and response.
- `apps/renthub_flutter` controller, Owner form and contract test carry the new
  evidence, warnings, confidence, exclusion and accept-suggestion behavior.
- `services/ai/README.md`, `docs/architecture.md` and this report document the
  artifact-backed implementation and reproducible workflow.

## Implemented architecture

```text
MongoDB listings/bookings/reviews
  -> read-only anonymised export with prior-only evidence
  -> provenance-aware canonical dataset
  -> grouped train / validation / test split
  -> preprocessing + XGBRegressor pipeline
  -> versioned atomic artifact + held-out metrics

Flutter Owner listing form
  -> authenticated Express endpoint
  -> server-derived MongoDB comparable hierarchy
  -> FastAPI versioned inference contract
  -> calibrated price/range/confidence/evidence
  -> accept or ignore suggestion
```

Flutter does not send trusted price aggregates. Unexpected client fields such as
`marketEvidence` and `supplyDemandRatio` are ignored by Express.

## Dataset and provenance

The canonical dataset is assembled by
`services/ai/app/training/pricing_dataset.py`. Every observation records
`source_type`, `target_source`, `observed_at` and a product-group identifier.

Current evaluated run:

| Source | Rows | Meaning |
| --- | ---: | --- |
| Synthetic | 5,000 | Deterministic development seed data |
| Real | 13 | Read-only export from the configured MongoDB database |
| Active asking | 11 | Current active listing daily prices |
| Completed rental | 1 | Completed booking effective daily price |
| Accepted booking | 1 | Approved/active booking effective daily price |

Category coverage is Vehicles 1,033, Equipment 1,018, Devices 995, Books 988 and
Clothing 979. The daily target has minimum RM1.00, median RM59.66 and maximum
RM1,422.07.

Real-data priority is reflected in sample weights: completed rental 1.00,
accepted booking 0.75, active asking 0.45 and synthetic seed 0.35. Synthetic rows
remain identifiable and are never described as scraped or production data.

The export hashes listing identifiers and does not include names, emails,
addresses or other direct user identifiers. For each historical target, comparable
features, prior Owner reviews and completed-rental counts are computed only from
strictly earlier observations. The current database does not keep historical
trust-score snapshots, so exported historical trust score is left missing and
imputed during training rather than leaking the Owner's current score.

Validation records required-column failures, invalid/non-positive targets,
invalid timestamps, duplicates, null rates, category counts and high values above
the three-IQR threshold. The current run has zero duplicates and 65 high-value
observations; they are retained because the multi-category marketplace legitimately
contains high-price vehicle/equipment rentals. Dataset fingerprint:
`c62c56316afa01a43f47bdcb5b25524c9e2d5c4a184defe2d133165055ad4879`.

## Features

Categorical features are category, subcategory, condition, brand, product model
and Malaysian state. Numeric features include item age, expected rental duration,
active-comparable count/median/mean/IQR, historical-rental
count/median/mean/IQR, evidence freshness, demand/supply ratio, Owner trust score,
Owner rating, Owner completed rentals and prediction month.

Missing categorical values use `Unknown`; missing numeric values use the training
median. One-hot encoding uses `handle_unknown=ignore`, and a fresh-loaded artifact
is smoke-tested with an unseen brand before training is considered successful.

Category-specific structured specifications are not yet available in the current
listing schema. They are intentionally not fabricated. Adding reviewed structured
specification fields is a future schema/data task.

## Model and leakage controls

The pipeline uses `ColumnTransformer`, categorical and numeric imputers,
`OneHotEncoder` and a genuine `XGBRegressor`. Its fixed, reproducible configuration
uses 360 trees, depth 6, learning rate 0.035, minimum child weight 3, 0.85 row and
column sampling, L2 value 1.2, one worker and seed 42.

Products are separated with `GroupShuffleSplit` by product/model group. The final
split contains 3,471 training rows, 758 validation rows and 784 untouched test
rows. Validation selects a category model only when it has at least 500 training
rows, 75 validation rows and improves validation MAE by at least 2%. Books,
Clothing and Vehicles selected category models in the current run; Devices and
Equipment retained the global model.

A category/subcategory median predictor is the honest baseline. No tuning result
uses the test set. Prediction intervals use the 90th percentile of absolute
validation residuals, globally or for a selected category model.

## Evaluation

| Evaluator | Rows | MAE (RM) | RMSE (RM) | R² |
| --- | ---: | ---: | ---: | ---: |
| Selected global/category strategy | 784 | 10.64 | 24.43 | 0.981 |
| Global XGBoost only | 784 | 10.31 | 24.00 | 0.981 |
| Category/subcategory median baseline | 784 | 71.30 | 132.92 | 0.432 |
| Real-source slice | 3 | 28.88 | 29.28 | -2.510 |
| Synthetic-source slice | 781 | 10.24 | 23.98 | 0.982 |

The 90% residual interval covered 90.56% of the grouped test rows. The three-row
real test slice is far too small for a stable estimate; its poor R² is reported
rather than hidden. Source-slice figures use the global model so the comparison
does not mix estimator-selection effects.

| Category | Test rows | MAE (RM) | RMSE (RM) | R² | Selected model |
| --- | ---: | ---: | ---: | ---: | --- |
| Books | 216 | 0.60 | 0.89 | 0.954 | Category |
| Clothing | 148 | 1.41 | 2.24 | 0.959 | Category |
| Devices | 108 | 9.93 | 15.25 | 0.974 | Global |
| Equipment | 126 | 15.62 | 24.15 | 0.966 | Global |
| Vehicles | 186 | 26.69 | 44.49 | 0.964 | Category |

The run completed model training/evaluation in 1.760 seconds. Full-precision
generated category and source metrics are stored in
`services/ai/metrics/price_metrics.json`.

## Runtime evidence and fallback

Express independently queries a 365-day evidence window and selects the narrowest
tier with at least three observations:

1. exact product + local state + condition;
2. subcategory + brand + local state;
3. subcategory + local state;
4. category + local state;
5. marketplace-wide category.

It sends active and completed-rental count, median, mean, IQR, freshness and
demand/supply ratio to FastAPI. The model result includes its source, version,
currency, interval, warnings and evidence. Confidence is derived from calibrated
relative error, evidence volume, evidence freshness, feature completeness and
out-of-distribution status.

If FastAPI or its artifact is unavailable, Express may return a labelled
`active_listing_median` or `completed_rental_median` fallback only when at least
three observations and non-zero robust spread exist. Its confidence is derived
from evidence count, freshness and relative spread. Otherwise the response is
`insufficient_data`; no guessed price is emitted.

## Representative successful inference

For the retained Sony camera contract fixture with eight active and twelve
completed comparables, the fresh artifact returned:

```json
{
  "available": true,
  "suggested_daily_price": 80.45,
  "lower_bound": 54.21,
  "upper_bound": 106.68,
  "confidence": 0.7875,
  "confidence_label": "high",
  "currency": "MYR",
  "model_source": "global_xgboost",
  "model_version": "renthub-price-v2-c62c56316afa"
}
```

This fixture response proves contract and artifact execution only; it is not a
market quotation.

## Owner UI

The physical-listing form collects category, subcategory, condition, brand,
product model, item age, location/state and expected duration before requesting a
suggestion. Editing excludes the listing itself from active comparables. The card
shows daily suggestion, calibrated range, confidence label/score, model source,
active and completed evidence, warnings and explanation. The Owner must explicitly
accept the value; it is never silently applied. Unavailable/insufficient-data
states remain visible and do not overwrite an entered price.

## Artifact lifecycle and compatibility

The artifact contains schema version, model version, training timestamp, global
and selected category pipelines, ordered feature schema, supported categories,
calibration data, metrics and dataset fingerprint. It is written to a temporary
file and atomically replaced, then loaded again for a smoke prediction. FastAPI
rejects request schema versions other than `renthub-price-v2`, reports missing or
incompatible artifacts explicitly, and exposes compatibility in `/health`.

Generated raw exports and model files stay ignored by Git. The evaluated metrics
JSON is retained for the report and review.

## Reproduction commands

From `services/api`:

```powershell
npm.cmd run export:pricing-data
```

From `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_tabular_models `
  --synthetic-rows 5000 `
  --real-export ..\api\.data\pricing_observations.json
.\.venv\Scripts\python.exe -m pytest -q
```

API validation from `services/api`:

```powershell
$env:NODE_ENV='test'
$env:AUTH_MODE='mock'
$env:STORAGE_MODE='local'
$env:BLOCKCHAIN_MODE='disabled'
$env:FCM_MODE='disabled'
npm.cmd test
```

Flutter validation from `apps/renthub_flutter`:

```powershell
C:\Users\weith\develop\flutter\bin\cache\dart-sdk\bin\dart.exe analyze `
  lib\features\live\live_owner_shell.dart `
  lib\features\live\live_renthub_controller.dart `
  test\live_owner_operations_contract_test.dart
C:\Users\weith\develop\flutter\bin\flutter.bat test `
  test\live_owner_operations_contract_test.dart
```

To start the complete local stack and Flutter Windows client using the configured
environment, run from `apps/renthub_flutter`:

```powershell
.\run-renthub.ps1
```

For separate service terminals, run `npm.cmd run dev` from `services/api` and:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

from `services/ai`, then start Flutter with the repository's configured Dart
defines (the combined PowerShell script is the preferred path).

Observed results: Python 13/13 passed, API 81/81 passed, focused Flutter 6/6
passed, and full Dart analysis reported no issues. The full Flutter suite recorded
80 passes, two conditional skips and one failure in the unrelated
`new shared account pages render at 360 pixels` test: its `SecurityPage` fixture
does not provide `AuthController`. The same failure reproduces in isolation, and
authentication code was not changed for this pricing task. The first API attempt inherited
`BLOCKCHAIN_MODE=ganache` from local configuration and waited for an unavailable
node; the isolated passing run explicitly disabled that unrelated adapter.

## Remaining limitations and retraining plan

- Collect substantially more completed rentals across all categories and states;
  completed prices are the highest-value targets.
- Store point-in-time listing and Owner reputation snapshots when a booking is
  accepted/completed, rather than reconstructing mutable listing fields later.
- Add reviewed structured category specifications before using device storage,
  vehicle year, book edition or similar fields.
- Re-evaluate by time as well as product group once enough dated real data exists.
- Report per-category and per-source metrics only where sample sizes are useful;
  do not promote the present three-row real test slice as accuracy evidence.
- Retrain by re-exporting MongoDB observations, running the same versioned command,
  reviewing data-quality and held-out metrics, and deploying the new artifact only
  if it beats the baseline and passes compatibility/smoke tests.
