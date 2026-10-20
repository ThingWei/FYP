# Pricing evidence and safe recommendation evaluation

Follow-up: 20 October 2026. This is training-data preparation and offline evaluation work, not a claim of validated Malaysian-market accuracy.

## Implemented

- Pricing exports include eligible `pricing_references` alongside platform asking prices and accepted/completed bookings. External references retain `source_type = external_asking_price` and `target_source = external_asking_price`; they never become bookings or completed rentals.
- Manual references require recorded review. Automatic references require an implemented, maintainer-approved and enabled source, accepted validation, compatible product type and valid duration band. Inactive, stale (over 365 days), future, malformed and unsupported references are excluded. Source URLs are not fetched.
- Amount, quoted period, source URL/name, packages, collection method and applicable duration bands survive preparation. A daily rate advertised only for 7–30-day bookings is not presented as a one-day offer: the original quote is retained and the feature explicitly uses the eligible band minimum when necessary.
- Repeated reference observations deduplicate; conflicting duplicate prices stop export. Python preserves distinct duration bands even when their daily prices are equal.
- External asking prices receive the existing asking-price training weight (0.45), below completed rentals (1.0). This is an evidence weight, not a product-price rule. Feature order and live inference contracts are unchanged. Future pricing reports include target-source as well as source-provenance performance.
- Recommendation reports separate marketplace, demo and synthetic holdouts. Source-specific ranking uses that source's item catalogue, not synthetic distractors for the marketplace cohort. Reports include candidate and cold-start counts.
- A separate `marketplaceOnly` experiment excludes demo/synthetic rows from fitting and evaluation and includes a train-mean baseline. Insufficient/no-holdout cohorts return explicit states/null errors, not invented zero-error scores.
- `--evaluate-only` fits temporary in-memory models without saving deployed artifacts, production metrics or generated CSVs. Optional `--report` exclusively creates a new JSON file outside deployed models/metrics/data directories; existing files cannot be overwritten.
- The deployed Surprise model is checked for already-seen holdout pairs. Overlap prevents an independent comparison. Without overlap, unknown training chronology still makes comparison diagnostic only. No automatic promotion occurs.
- Marketplace observations take precedence over demo/synthetic duplicates in Express and Python. Stronger-action precedence remains within each source. No activity is fabricated.

## Read-only pricing database check

The configured MongoDB was queried using bounded native reads, without importing Mongoose models, creating collections/indexes, fetching websites or writing an export file:

```powershell
cd C:\Users\weith\FYP\services\api
npm.cmd run export:pricing-data -- --summary-only
```

| Eligible observation | Rows |
| --- | ---: |
| External advertised rental-price references | 332 |
| Platform active asking prices | 3 |
| Accepted physical bookings | 4 |
| Completed physical rentals with captured/settled payment | 1 |
| Total | 340 |

No database/export-file writes occurred. These are eligible export counts, not every database record. `real` is the legacy platform provenance label, not independent proof of a commercial transaction. Older reports describe different snapshots/eligibility rules. No history was deleted or rewritten.

Default bounds are 10,000 records per queried collection. Exceeding a bound fails the whole export rather than silently truncating it. `--limit N` explicitly allows up to 100,000.

## Saved recommendation-export evaluation

The local export was last modified on 6 October 2026: this is **not a fresh audit of current recommendation activity in MongoDB**. It contains 11 marketplace-labelled interactions from seven accounts across six listings, plus 3,360 deterministic synthetic rows when defaults are enabled. No demo rows are present.

```powershell
cd C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m app.training.train_recommendation --evaluate-only
# Entirely marketplace-only; still no deployment:
.\.venv\Scripts\python.exe -m app.training.train_recommendation --evaluate-only --no-synthetic
```

Measured seed-42 results:

| Evaluation | Train rows | Test rows | MAE | RMSE |
| --- | ---: | ---: | ---: | ---: |
| Mixed candidate, combined holdout | 2,648 | 723 | 0.71325 | 0.90372 |
| Mixed candidate, marketplace holdout | mixed | 3 | 1.18446 | 1.28867 |
| Mixed candidate, synthetic holdout | mixed | 720 | 0.71128 | 0.90178 |
| Marketplace-only candidate | 8 | 3 | 0.68264 | 0.78102 |
| Marketplace-only train-mean baseline | 8 | 3 | 0.66667 | 0.81650 |

Marketplace Precision@5 = 0.21667, Recall@5 = 1.0 and HitRate@5 = 1.0, on only three ranking users and six catalogue items before seen-item exclusion. Precision divides by the number returned (up to five). Tiny candidate sets and implicit-action labels make apparent recall/hit rate unsuitable as accuracy claims. The marketplace-only candidate does not beat the mean baseline on MAE.

The deployed artifact had already seen **all 723 holdout pairs**: `existingArtifact.status = not_comparable_seen_holdout`. No winning model or improvement over deployment is claimed. Before/after SHA-256 checks were identical:

- Recommendation artifact: `af6003b48ccee8e5c190103c8747b336e76a3ce58d411da5f3c1a2c60bba6657`
- Existing recommendation metrics: `4c34ca31ee32a9efa13b50b84e16a67f01828ca62573a4740a1d6a4137c8fc02`

## Next workflow

1. Collect consented browsing, saves, requests, rentals and feedback through the app. Keep procedural seeds labelled `demo_seed`; do not describe staged activity as real commercial transactions.
2. Review source health and collected quotes. The 332 eligible records are not 332 independently verified product prices or successful rentals. Coverage/package compatibility still matter.
3. Explicitly export new local files when ready, preserving the old audit input:

   ```powershell
   cd C:\Users\weith\FYP\services\api
   npm.cmd run export:pricing-data -- --output .data/pricing_observations_reviewed_2026-10-20.json
   # Existing recommendation export workflow; use permissioned activity only:
   npm.cmd run export:recommendation-data -- .data/recommendation_interactions_reviewed_2026-10-20.json
   ```

4. Evaluate without replacing the running recommendation model:

   ```powershell
   cd C:\Users\weith\FYP\services\ai
   .\.venv\Scripts\python.exe -m app.training.train_recommendation `
     --real-export ../api/.data/recommendation_interactions_reviewed_2026-10-20.json `
     --evaluate-only --no-synthetic
   ```

   Optionally add `--report .data/recommendation-evaluation-new.json` if the parent exists and the filename is new. Only load locally trusted Surprise files using `--baseline-artifact`: pickle files are executable data, not safe uploads.

5. Review source-specific results, cohort sizes, baseline comparison and cold-start effects before a separate intentional deployment run. Do not casually remove `--evaluate-only`: existing training commands intentionally save artifacts.

## Limitations

- No fresh recommendation export, real-data collection, pricing retraining or deployed-model replacement occurred. Live pricing already consumes compatible references; they are now also available for future reviewed training.
- One eligible completed physical rental and 11 saved marketplace interactions cannot validate production accuracy. Existing saved training reports remain unchanged and heavily synthetic.
- Pricing features use strictly earlier evidence also collected/reviewed/validated before the target. Demo evidence cannot contribute to non-demo targets; the subject product group cannot supply its own target evidence. Public references are constrained by domain/type/duration; private owner locations/IDs and reviewer details are omitted.
- Pricing groups use canonical identity, normalized category/brand/model, then source-product/record fallbacks. Missing/inconsistent identities can defeat cross-source grouping. Current listing metadata is not a historical booking-profile snapshot.
- Pricing splitting remains grouped, not globally chronological. Comparable features are built before splitting, so earlier observations from another held-out group may contribute features. Strict forward-time, fold-local evidence evaluation remains future work: fully leakage-free pricing accuracy is not claimed.
- Recommendation holdout remains per-user chronological, not a global time cutoff. Implicit action ratings are not satisfaction scores; SVD evaluation does not evaluate the entire content/proximity/availability feed. Source-specific catalogues are diagnostic, not exposure experiments.
- iRent, RentSmart and 12RENT adapters are unchanged and still unfinished. More data does not resolve ambiguous periods, retail/deposit mixes or access/reuse conditions automatically.
- No UI, Auth0, ranking weights, taxonomy, hosting, source adapter or production dependency changed. Previous image-recognition/risk preparation work was preserved.

## Verification

- Full AI suite: 482 passed; two existing dependency deprecation warnings.
- Full API suite: 375 passed, three optional environment-dependent tests skipped. Focused export/recommendation regressions: 25 passed.
- Regression coverage: bounded/read-only MongoDB access, source approval/enabling, malformed/stale/future/unreviewed records, domain/duration constraints, conflicts/deduplication, source precedence, privacy, completed-payment eligibility, provenance retention, sparse evaluation, seen-holdout rejection, corrupt baseline and report-file/no-write protection.
- No Flutter source changed in this follow-up; UI builds were not rerun. Existing unrelated Auth0 test/analyzer constructor errors were not repaired.

## Commit message

```text
feat(ai): export rental-price evidence and add safe recommendation evaluation

- include eligible external asking prices with source and duration provenance
- exclude stale, disabled, incompatible and future-known price observations
- preserve completed-rental separation and private-data boundaries
- retain duration bands and validate pricing source/target labels
- report recommendation scores by source with marketplace-only evaluation
- prevent demo signals from replacing marketplace observations
- add non-deploying evaluation mode and seen-holdout baseline guards
- document evidence gaps and add export/evaluation regression tests
```
