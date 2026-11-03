# AI validation: measured results and independent-data gaps

Later 1 November follow-up: [licensed public-photo and sourced-price pilot](PUBLIC_AI_EVALUATION_PILOT_RESULT.md)
adds 11 public images/33 diagnostic cases and 13 researched asking observations.
The zero-photo counts below describe the earlier audit snapshot. Public pretrained
overlap remains unknown; the original 198-case independent collection and genuine
recommendation feedback remain incomplete.

Executed 1 November 2026 (Malaysia time). This is a fresh evaluation round, not
retraining or completion of the real-world study. The user confirmed there are
no independent permissioned photos or completed tester feedback yet. Existing
platform activity stays classified as dedicated demo activity under the user's
earlier clarification. No activity was generated on anyone's behalf.

## Executed work

| Area | Actual work | Independent real-world validation |
| --- | --- | --- |
| Recognition | Loaded installed baseline/general/YOLO-World models; audited 22 subcategories and 92 product types | Not evaluated: zero reviewed photos |
| Item-photo risk | Re-ran enabled frozen artifact on fingerprint-verified original 2,714-image test split | Original benchmark reproduced; zero reviewed rental photos |
| Pricing | Read-only current export; frozen deployed model with forward-time/history-only comparable features | Diagnostic asking-price results; zero genuine completed-rental targets |
| Recommendations | Read-only staged export; non-deploying chronological SVD evaluation and baseline | Staged diagnostic; zero marketplace holdout/independent feedback |

No model, threshold, ranking weight, source setting, booking, listing, payment,
index or live database record changed. Source pages were not fetched. No new
image/source permissions or tester consents were declared. Original public-data
licence/grouping caveats remain in `PUBLIC_ITEM_RISK_DATASET_RESULT.md` and
`ITEM_RISK_TRAINING_RESULT.md`.

## All-category recognition and price coverage

Label support means a deployed detector has a matching configured object label,
not measured accuracy or complete product coverage. Every recognition photo-case
count is zero. Existing 198-slot collection templates remain unfilled/unchanged.
Price counts are eligible stored asking references, not independently reviewed
transactions. Distinct offers retain package/duration semantics; they are not
necessarily distinct physical products or independent businesses.

| Category | Specific category | Price observations | Distinct offers | Types with matching label |
| --- | --- | ---: | ---: | ---: |
| Devices | Smartphones | 2 | 2 | 1/1 |
| Devices | Cameras | 223 | 223 | 1/2 |
| Devices | Computers | 3 | 3 | 4/5 |
| Devices | Audio | 8 | 8 | 4/5 |
| Devices | Gaming | 6 | 2 | 2/3 |
| Devices | Other devices | 6 | 6 | 4/7 |
| Vehicles | Cars | 73 | 13 | 1/1 |
| Vehicles | Motorcycles | 16 | 16 | 1/1 |
| Vehicles | Bicycles | 10 | 10 | 1/1 |
| Vehicles | Other vehicles | 0 | 0 | 4/7 |
| Equipment | Event equipment | 16 | 16 | 7/10 |
| Equipment | Tools | 1 | 1 | 6/9 |
| Equipment | Sports equipment | 0 | 0 | 11/18 |
| Equipment | Other equipment | 5 | 5 | 4/5 |
| Books | Textbooks | 0 | 0 | 1/1 |
| Books | Reference books | 0 | 0 | 1/1 |
| Books | Fiction | 0 | 0 | 1/1 |
| Books | Other books | 0 | 0 | 1/1 |
| Clothing | Formal wear | 1 | 1 | 2/4 |
| Clothing | Costumes | 3 | 3 | 1/1 |
| Clothing | Traditional wear | 3 | 3 | 2/5 |
| Clothing | Other clothing | 1 | 1 | 2/3 |

62 of 92 types have a matching deployed label; 30 remain manual-review types.
Gaps include monitors, camera lenses, VR headsets, mixers, walkie-talkies,
video-capture devices, smartwatches, specialised scooters/tools/sports equipment
and garments. Generic books do not establish title/edition/genre. No threshold
was lowered and the separate expanded World candidate was not deployed.

The recognition CLI now accepts `--report NEW_PRIVATE_JSON`, saving valid JSON
separately from third-party console messages. Existing invocation/stdout behaviour
remains compatible; unavailable/unmeasured results stay explicit.

## Frozen item-risk evaluation

Added `app.training.evaluate_item_risk`. It evaluates local TorchScript weights
with the trainer's RGB/224/ImageNet preprocessing, bounded CPU batches and no
fitting/downloads. It verifies the original manifest plus image fingerprint
against embedded metadata before selecting its test split or checking new photos.

Original test benchmark: 2,714 images, 1,354 supplied proxy groups; 1,435 labelled
normal and 1,279 risky. Groups are supplied filename/content groups, not
independently verified physical-item identities.

| Fixed threshold | Accuracy | Macro-F1 | Risky precision | Risky recall |
| --- | ---: | ---: | ---: | ---: |
| Classification, 0.50 | 68.64% | 0.6848 | 67.29% | 65.13% |
| Existing production warning, 0.65 | 66.40% | 0.6420 | 74.05% | 44.18% |

Confusion matrices: rows actual normal/risky; columns predicted normal/risky.

- At 0.50: `[[1030, 405], [446, 833]]`.
- At 0.65: `[[1237, 198], [714, 565]]`.

The 0.50 result reproduces the saved benchmark. At the existing app warning
threshold, 714 altered benchmark photos do not raise that warning and 198
baseline photos do. The threshold was measured, not tuned. These are public
image-manipulation benchmarks, not reviewed RentHub photos or an authentic versus
counterfeit test. Normal never means genuine, owned or good condition.

Separate classification: AutoSplice 884 samples, 72.62% accuracy, macro-F1 0.7147;
CASIA2 1,830 samples, 66.72%, macro-F1 0.6526. Reviewed-real remains
`not_evaluated`, zero samples and null metrics at both thresholds.

New reviewed evaluation requires actual permission/review flags, documented label
evidence, `reviewed_real` provenance and a test-only manifest. It rejects exact
duplicates and overlap with **any** original dataset image/group, including old
test images. Relabelling the benchmark cannot create independent rental-photo
evidence. Hash/group checks cannot rule out every near-duplicate or false label.
One-class collections report `insufficient_class_coverage`; empty data fails.

Header-only private template/instructions, alongside the existing recognition kit:
`.data/evaluation/item-subtype-readiness-v1/risk_reviewed_cases.csv` and
`RISK_EVALUATION.md`. No actual paths, labels, photos or permissions were filled.

## Pricing: measured diagnostic

Fresh export: 397 observations = 377 external asking references + 20 staged
platform observations. All 20 staged rows are excluded from clean evaluation.
Coverage remains 16/22 subcategories. All 377 references lack condition and age;
missing values were not replaced with guesses.

Two completed database bookings: one has simulated payment; one has no payment
evidence. All 26 payment records are simulated. Neither booking establishes
genuine achieved-rental evidence. No historical source markers were rewritten.

Forward cutoff: 28 October 2026, 10:09:37 pm MYT; full precision is in the private
report. There are 233 earlier history rows, 130 holdout targets and 14 excluded
late-known/unknown-time rows. Holdout prices do not become comparable features.

| Measure | Frozen XGBoost | History-only category-median baseline |
| --- | ---: | ---: |
| Predicted targets | 21 | Same 21 targets |
| Mean absolute daily-price error | RM133.09 | RM186.19 |
| Root mean square daily-price error | RM145.01 | RM222.98 |
| R-squared | -0.0965 | -1.5926 |

Coverage is 21/130 (16.15%), with 109 abstentions (83.85%). All 21 predictions are
Cars. Other domains lack compatible earlier history. Negative R-squared and large
MYR errors do not support an accuracy claim even though the baseline is worse.

The artifact lacks a row-level training manifest, so original training overlap
cannot be proven absent. Results remain diagnostic. No achieved-rental or
age/condition calibration is established. No new candidate was fitted/deployed.
Manual pricing remains available.

The bounded audit found no separately supplied reuse-review evidence for the 11
retained sources. This does not reverse source settings or assert permission is
absent; this round did not independently establish it. The permission-cleared
preview contains zero rows, a documented shortfall of 100.

## Recommendation diagnostic

17 strongest interactions, eight accounts, nine listings: four views, eleven
booking signals and two published reviews. All are staged in the private export,
consistent with the user's clarification; no database source flags changed.

Temporary non-deploying SVD evaluation: 13 training/four holdout interactions.
Only two users qualify for ranking: Precision@5 0.20, Recall@5 1.00, HitRate@5 1.00.
This tiny staged cohort does not establish personalization accuracy. Explicit
feedback is absent; implicit action weights are not satisfaction ratings.

RMSE 1.4591/MAE 1.2785 are worse than the training-mean baseline (RMSE 1.3990,
MAE 1.2500). Marketplace-only is `insufficient_data`, zero interactions. The
deployed artifact has seen two of the four holdout pairs; its comparison is
`not_comparable_seen_holdout`, not independent accuracy. SVD metrics do not
evaluate the complete content/proximity/availability feed or a user study.

## Reproduction and private outputs

Commands were executed from the corresponding service directories. Export and
report filenames are exclusive; choose a new round ID to repeat.

```powershell
# services/api; earlier confirmation says platform activity is dedicated/staged
node src/scripts/exportPricingData.js --all-staged --output .data/evidence/ai-validation-2026-11-01/pricing_observations.json
node src/scripts/exportRecommendationData.js --all-staged --output .data/evidence/ai-validation-2026-11-01/recommendation_interactions.json
node src/scripts/auditPricingRealWorld.js --output .data/evidence/ai-validation-2026-11-01/audit

# services/ai
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/evidence/ai-validation-2026-11-01/pricing_observations.json `
  --mode deployed --report .data/evaluation/ai-validation-2026-11-01-pricing.json
.\.venv\Scripts\python.exe -m app.training.train_recommendation `
  --real-export ../api/.data/evidence/ai-validation-2026-11-01/recommendation_interactions.json `
  --evaluate-only --no-synthetic --report .data/evaluation/ai-validation-2026-11-01-recommendations.json
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --coverage-only --report .data/evaluation/ai-validation-2026-11-01-recognition.json
.\.venv\Scripts\python.exe -m app.training.evaluate_item_risk `
  --training-manifest .data/datasets/public_item_risk_acknowledged_v2/manifest.csv `
  --report .data/evaluation/ai-validation-2026-11-01-risk.json --cpu-threads 4
```

Exports/reports stay Git-ignored/private. Exported rows/reports contain no emails,
raw IC numbers, identity documents or exact coordinates. Pseudonymization does
not guarantee anonymity. Mongo command monitoring recorded reads only/zero writes.

## Verification and next independent inputs

- Full AI suite: **620 passed**, four existing dependency/sparse-fixture warnings.
- Focused evaluator/training/readiness: **40 passed**.
- Relevant API evidence/export/recommendation suites: **38 passed**, using isolated
  mock auth/storage and disabled external effects, not the live environment.
- Tests cover fingerprint mismatch, dataset overlap, permissions, label evidence,
  duplicates, empty/one-class data, frozen artifacts, safe reports and noisy console
  output. No model/example labels from these generated fixtures are research results.
- Before/after deployed model/metrics checksums are verified. Flutter presentation
  did not change; Flutter builds were not rerun.
- Ultralytics attempted denied user-profile cache/settings writes during loading;
  local models still loaded and the separate JSON report is valid. No permissions
  were broadened and no model was downloaded to suppress the messages.

Independent work remains incomplete; use the existing collection/session guides:

1. Recognition: 44 distinct permissioned items with overview/alternate/detail
   photos plus 66 unrelated cases = 198 diagnostic cases. Add actual reviewed
   boxes/context. Keep those items out of later training/development.
2. Risk: permissioned originals/alterations with documented label basis; keep
   manipulation, authenticity, condition and ownership separate.
3. Recommendations: willing testers perform their own actions and later provide
   feedback; record consent/exclusions. Scripted actions remain staged.
4. Prices: reviewed period/package-compatible quotations, then genuine transactions
   when available. Prioritize six empty domains and thin Computers/Tools/Smartphones/
   Clothing coverage. Do not invent condition/age or completed rentals.

See `AI_VALIDATION_COLLECTION_GUIDE.md` and `PRICING_RECOMMENDATION_TEST_SESSION.md`.
No result justifies automatic approval, authenticity claims or automatic model
replacement. This round completes supported diagnostics/tooling, not the missing
independent evidence.

## Commit message

```text
feat(ai): evaluate frozen item risk and document fresh evidence diagnostics

- verify the risk artifact against its original dataset fingerprint
- separate benchmark/real cohorts at fixed classification and app thresholds
- reject overlap, missing permissions, unsupported labels and duplicate photos
- save recognition JSON separately from model-library console messages
- rerun read-only pricing and staged recommendation diagnostics without deployment
- document all-22 coverage, errors, abstentions and independent-data gaps
- preserve deployed artifacts, production metrics and marketplace records
```
