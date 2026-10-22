# Pricing and recommendation evidence — measured round 1

22 October 2026. The user confirmed existing activity is theirs/dedicated demo
accounts. This round implements safe staged export, audits actual coverage and
runs non-deploying evaluations. It does **not** complete independent tester
participation, create commercial transactions or improve the deployed models.

## Executed, not just prepared

- Read-only native MongoDB summaries, then new private exports. No production
  database writes, schema/index changes, data cleanup, source enablement or URL
  fetching. Existing collection methods, time/amount/type checks and bounds apply.
- Added explicit `--all-staged` to the two existing export CLIs for a database
  whose platform activity is entirely one's own/consenting dedicated test accounts.
  The classification is written to the export, **not** MongoDB. External rental
  asking references remain `external_asking_price`.
- Added incompatible-option/type/missing-path guards. A missing `--staged-users`
  argument must not silently fall through to unclassified exporting. All export
  writes remain exclusive/new-file-only and private fields remain excluded.
- Staging now happens before recommendation action precedence. Otherwise a
  legacy marketplace-labelled view could incorrectly hide a staged completed
  action for the same account/listing. Synthetic recommendation signals stay
  synthetic. With neither export override selected, live behaviour is unchanged.
- No new dependencies, Flutter/Auth0 changes, ranking-weight changes, automatic
  source onboarding or model deployment. No fabricated activity or participant
  feedback. The older data collection kit remains intact.

## Private outputs

From `services/api`, executed once:

```powershell
npm.cmd run export:pricing-data -- --all-staged --output .data/evidence/2026-10-22-round1/pricing_observations.json
npm.cmd run export:recommendation-data -- --all-staged --output .data/evidence/2026-10-22-round1/recommendation_interactions.json
```

These paths are Git-ignored. They contain minimized/pseudonymized data, not a
guarantee of anonymity. Keep them private; no email, identity images, exact
coordinates or raw account IDs are exported. The same filenames cannot be reused.

Evaluation reports under `services/ai`:

- `.data/evaluation/pricing-evidence-2026-10-22-round1.json`
- `.data/evaluation/recommendation-evidence-2026-10-22-round1.json`

Commands actually executed:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/evidence/2026-10-22-round1/pricing_observations.json `
  --report .data/evaluation/pricing-evidence-2026-10-22-round1.json
.\.venv\Scripts\python.exe -m app.training.train_recommendation `
  --real-export ../api/.data/evidence/2026-10-22-round1/recommendation_interactions.json `
  --evaluate-only --no-synthetic `
  --report .data/evaluation/recommendation-evidence-2026-10-22-round1.json
```

Temporary evaluation models were fitted in memory. Their weights were not saved
or deployed. All deployed model/metric SHA-256 inventories are identical before
and after this round, including the previously enabled item-risk model.

## Pricing audit and 22-subcategory coverage

Raw eligible summary: 342 observations, including 334 external asking quotes,
three platform listing prices, four accepted bookings and one completed rental.
The database's legacy `real` labels on those eight platform rows are not evidence
of commercial activity. Following the user's clarification, the export marks
them all staged and excludes them from real/asking-price model evaluation.

| Evaluation provenance | Rows |
|---|---:|
| External advertised asking prices | 334 |
| Staged platform active asking prices | 3 |
| Staged accepted bookings | 4 |
| Staged completed rentals | 1 |
| Eligible non-staged achieved rentals | 0 |

Coverage of the 334 eligible external references:

| Category | Specific category | Observations | Product groups |
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

Thus **16 of 22** subcategories have some external evidence, not verified
coverage of every product/model. Product groups use existing canonical/text/source
keys, not independently confirmed unique physical items. Several car/game
duration bands refer to the same product. Cameras includes compatible optical
product types and must not be read as 181 independently priced camera bodies.

All 334 quotes were automatic observations already eligible under configured
source checks. Sources: RENTISM 203; DRIVOR 73; Alquiler Motorbike 15; Ecocana
Sports 10; The Rental Guy 7; Partymix 7; Cilt Tech 6; JomRentPro 6; ITPA 3;
PC Rent 3; Futago Winter 1. This audit did not independently review permissions,
refresh pages or override prior source approvals. Observation dates span
13, 15 and 22 October, not 334 independent collection days.

253 observations are named-product references; **81 are specification-only**.
None of the 334 quotes specifies item age or condition. Those fields correctly
remain null: they were not filled using release dates, random values or synthetic
depreciation. This dataset cannot validate learned age/condition effects. Sources,
durations, compatible item types and package notes remain separate from product
identity providers and achieved-rental evidence.

## Actual pricing evaluation

Seed 42; existing fitted-feature specification and model-building pipeline;
global forward-time split at **2026-10-22 06:24:53.299 UTC**. Eight staged platform
rows were excluded. 310 earlier asking-price observations trained the temporary
candidate; 24 later asking observations formed the holdout. No synthetic rows,
unknown/late observations or seen holdout product-group overlaps were present.
Comparable features were rebuilt using only training-side, earlier-known history.
Every holdout selected the broad `category_wide` evidence tier, not exact-product
rental evidence. Missing fold-local Owner aggregates stayed absent.

| Held-out external asking-price metric | Candidate | Category-median baseline |
|---|---:|---:|
| Observations | 24 | 24 |
| Daily-price MAE | RM 89.66 | RM 118.13 |
| Daily-price RMSE | RM 127.49 | RM 146.10 |
| R² | −0.1178 | −0.4680 |

MAE is average absolute daily-price error, not a percentage accuracy. Although
the temporary candidate beats this median baseline on the small holdout, errors
remain large and R² is negative. No improvement over the running artifact was
measured. No achieved-rental/accepted-booking or platform-asking holdouts remained;
their results are explicitly `no_holdout`, not zero error. This is not a successful
market-wide product-specific or age-sensitive pricing validation.

The imputer warned about entirely missing age/history/Owner features. This is a
real evidence limitation, not a reason to fabricate values or retrain deployment.

## Actual recommendation evaluation

17 strongest account/listing interactions from **eight accounts and nine listings**:
five viewed, ten booking signals and two published reviews. These are all staged;
eight accounts are not eight independent people. There are no retained `saved`
signals after stronger-signal selection, which does not prove nobody ever saved
an already-booked/reviewed listing. Four accounts have just one retained signal;
one has two, two have three and one has five.

`--no-synthetic` added zero synthetic observations. Per-user chronological split:
13 training interactions and four held-out interactions. The report's legacy
dataset-name string still says `marketplace-plus-labelled-synthetic-v2`; actual
source counts are authoritative: **17 demo, zero marketplace, zero synthetic**.

| Staged holdout metric | Candidate | Training-mean baseline |
|---|---:|---:|
| MAE on implicit 1–5 action-rating scale | 1.1401 | 1.2500 |
| RMSE on implicit rating scale | 1.2690 | 1.3494 |

Only two users qualified for ranking: Precision@5 0.20, Recall@5 1.0,
HitRate@5 1.0, on a nine-listing source catalogue before seen exclusions. One of
the held-out listings is cold-start. High recall/hit rate here is not a meaningful
accuracy claim. These implicit weights are not independently supplied satisfaction
ratings, and this SVD diagnostic does not evaluate the whole content/GPS/availability
feed. `marketplaceOnly` is correctly `insufficient_data` (zero observations).

The deployed SVD already saw **two of four** held-out pairs, so comparison with it
is refused (`not_comparable_seen_holdout`). No replacement/improvement claim or
automatic deployment followed the diagnostic.

## What still requires people or new evidence

Use [the short tester-session guide](PRICING_RECOMMENDATION_TEST_SESSION.md) and
private blank feedback template at
`services/ai/.data/evaluation/pricing-recommendation-round1/tester_feedback_template.json`.
The template has no participants, ratings or fabricated responses. It is not an
automated feedback importer. Suggested 5–10-person pilot size is a practical
starting target, not proof of statistical sufficiency.

The next useful work is independent, consented relevance feedback and more
diverse, permissioned, explicitly period-priced observations—not repeated clicks
or bulk scripted bookings. Staged test activity remains staged even when
participants are real people. An honest FYP usefulness study is possible without
claiming commercial transactions or creating fake completed-rental evidence.

Once natural activity/other participants are mixed in, do not blanket-export
with `--all-staged`. Review consent/exclusions first; use the selected staged-user
overlay where appropriate. This flag is classification, not anonymization,
consent verification, authorization to use third-party data or a deletion tool.
The live database still retains its old source markers; no historical migration
or change to live trending/popularity was performed.

## Verification

- Full API suite under isolated mock-auth/test storage and disabled external
  email/FCM/blockchain/jobs: **416 passed, three optional skips** (419 total).
- Focused export/recommendation tests passed; new coverage includes classification
  before precedence, synthetic-source preservation, external-reference separation,
  native read-only/privacy checks, option conflicts, malformed options and exclusive
  creation. Default marketplace precedence remains unchanged without an override.
- An initial bare focused invocation inherited the development Auth0 configuration
  and returned 401 for mock-header tests. Re-running with isolated test settings
  passed; no Auth0 code/config changes were made.
- Full AI suite: **542 passed**, four existing warnings (two third-party
  deprecations and two sparse-pricing fixture warnings). The actual asking-price
  diagnostic separately warned about its missing age/history/Owner features.
- Before/after inventories of all deployed models and metrics matched. Repeated
  aggregate pricing reads still show the same eight legacy platform rows and
  334 external references; exports did not rewrite their provenance in MongoDB.
- Private exports/reports/templates are Git-ignored. `git diff --check` passed.
  No Flutter presentation was changed; Flutter builds/tests were not rerun here.

## Commit message

```text
feat(ai): audit pricing evidence and stage demo-only evaluation exports

- add explicit all-staged export mode without rewriting marketplace history
- apply recommendation staging before stronger-action precedence
- reject conflicting staging flags and missing CLI file arguments
- retain external asking-price provenance and read-only bounded export safeguards
- run fresh forward-time pricing and source-separated SVD diagnostics
- document all-22 coverage, missing age/condition and sparse staged holdouts
- prepare an independent tester-session guide and private blank feedback template
- preserve deployed models, ranking weights, permissions and external source states
```
