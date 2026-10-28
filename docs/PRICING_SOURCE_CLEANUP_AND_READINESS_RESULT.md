# Pricing source cleanup and evidence readiness

27 October 2026. Implements the request to remove disabled/unusable sources and
continue the evidence workflow. No live records, stored quotations, source-state
documents, environment secrets or deployed models were changed.

## Removed sources

Removed **iRent, RentSmart Asia, 12RENT, Goritta and AVMProjector** from the live
registry, coverage mappings, parser dispatch and collection paths. Their obsolete
source-specific parsers/tests were removed and replaced with retirement regression
checks. Older source research documents remain historical records, not current
onboarding instructions.

The administrator source list now receives **11 registrations**. Removed IDs
return `PRICE_SOURCE_NOT_FOUND` for enable/sync. Old environment approvals or
enabled database rows cannot restore them. Their automatic observations are
excluded from comparisons and clean exports, even if stale IDs are supplied.
Historical records are preserved; there is no destructive cleanup or migration.
Manual, separately reviewed CSV references retain the existing independent path.

The remaining sources retain their normal enable/disable controls and access
checks. Removing five registrations does not manufacture reuse approval for any
retained source. Future administrative disabling remains reversible; it does not
delete the source definition or history automatically.

Restart the API through the usual launcher, then refresh source status. An old
running process will keep its old registry until restarted. No launcher restart
or source job was run as part of this change.

## All-category strategy after cleanup

The 22 physical-item subcategories remain supported. Product identity/catalogue
providers are separate and unchanged. Counts below are the current frozen review
run's eligible **asking-price observations**, not real completed transactions.

| Category | Specific category | Retained automatic sources | Observations |
|---|---|---|---:|
| Devices | Smartphones | RENTISM | 2 |
| Devices | Cameras | RENTISM | 181 |
| Devices | Computers | ITPA | 3 |
| Devices | Audio | RENTISM | 8 |
| Devices | Gaming | Cilt Tech | 6 |
| Devices | Other devices | RENTISM | 6 |
| Vehicles | Cars | DRIVOR | 73 |
| Vehicles | Motorcycles | Alquiler Motorbike | 15 |
| Vehicles | Bicycles | Ecocana Sports | 10 |
| Vehicles | Other vehicles | No automatic source | 0 |
| Equipment | Event equipment | The Rental Guy, PC Rent, RENTISM | 16 |
| Equipment | Tools | JomRentPro | 1 |
| Equipment | Sports equipment | No automatic source | 0 |
| Equipment | Other equipment | JomRentPro | 5 |
| Books | Textbooks | No automatic source | 0 |
| Books | Reference books | No automatic source | 0 |
| Books | Fiction | No automatic source | 0 |
| Books | Other books | No automatic source | 0 |
| Clothing | Formal wear | Partymix | 1 |
| Clothing | Costumes | Partymix | 3 |
| Clothing | Traditional wear | Partymix | 3 |
| Clothing | Other clothing | Futago Winter | 1 |

Every row retains clean RentHub evidence when it exists, independently reviewed
asking references, conservative estimates where supported, and manual pricing.
An empty source list does not disable listing creation or fabricate a price.
Existing scheduled collection continues to use the remaining enabled sources;
this task does not perform new collection or add replacement providers.

## Condition, age and genuine evidence

Automatic quote normalization now validates optional condition/age metadata and
preserves it when a parser actually supplies it. Missing values stay null; no
release-date guesses, random ages or depreciation-price rules were added.
Existing listing forms, reviewed CSV fields and immutable future booking
snapshots retain the normal collection paths for known condition/age.

Administrator category evidence now shows how many observations include condition
and item age. Current observations have **0/334 condition and 0/334 age values**.
This cannot establish learned real-world age/condition effects. Field completeness
is diagnostic, not proof that a model has learned those relationships.

The real-payment/price-independence gates remain intact. The two completed
bookings still do not establish genuine achieved-rental evidence. Current demo
checkout cannot become real payment evidence through more scripted activity.
The empty private collection template and participant guidance remain available;
no consent, participant action, payment or completed transaction was invented.

## One-command audit and frozen evaluation

From `services/api`, choose a **new** run ID:

```powershell
npm.cmd run review:pricing-evidence -- --run-id pricing-next-round
```

Optional predeclared chronological cutoff:

```powershell
npm.cmd run review:pricing-evidence -- --run-id pricing-next-cutoff --cutoff 2026-10-27T00:00:00Z
```

The command:

1. Validates arguments, output paths and the existing local AI virtual environment.
2. Runs the bounded native MongoDB audit; it starts no API/jobs or model service.
3. Saves new private audit/export files without overwriting previous runs.
4. Executes the existing evaluator with **`--mode deployed`**, never candidate fit.
5. Checks that the frozen report records an unchanged artifact and no candidate.

Run IDs cannot contain paths/whitespace. Existing output files/directories are
rejected before audit. There is no collection, import, retraining or deployment
option in this command. If a later stage fails, preserve the partial private run
for inspection and choose a new ID after correcting the cause.

Exports now include additive `catalogCoverage` metadata from the Express taxonomy.
The evaluator reports all 22 subcategories, including missing cohorts, rather
than making unsupported domains disappear. Older exports without taxonomy
metadata explicitly report unknown expected coverage.

`evidenceReadiness` reports asking/accepted/verified-completed counts, product
groups, known condition/age, unknown fields and missing domains. Counts and field
presence never authorize training. Current gaps yield
`candidateTrainingDecision = not_justified_by_current_data` and
`automaticTrainingAllowed = false`; complete-looking data still requires separate
review. Model feature order and inference endpoints remain unchanged.

## Actual executed result

Run ID: `pricing-retained-sources-2026-10-27-v1`.

- 334 asking observations; 16/22 domains populated; 6 domains missing.
- Zero independently verified completed-rental rows.
- Zero observations with known condition or item age.
- Forward-time split: 310 earlier rows, 24 later targets; 24 abstentions because
  no compatible earlier comparison exists. MAE/RMSE/R-squared remain unavailable.
- No candidate fitted. The old artifact's missing row-level training manifest
  remains an explicit independence limitation.
- Model SHA-256 unchanged:
  `2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

Private outputs:

- `services/api/.data/evidence/pricing-retained-sources-2026-10-27-v1/` contains
  aggregate audit, stored-data diagnostic observations and the unfilled review preview.
- `services/ai/.data/evaluation/pricing-retained-sources-2026-10-27-v1.json`
  contains the frozen evaluation and all-22 readiness assessment.

These are Git-ignored research files. A zero cleared preview is not filled with
invented records. Numerical accuracy and full market coverage remain unestablished.

## Verification and remaining limitations

Regression coverage includes retired IDs/stale approvals, no-fetch rejection,
no-write source removal, all-22 export metadata, unknown versus zero age, empty
cohorts, safe run IDs, output preservation and mandatory frozen mode. Flutter
source-health tests exercise 360/390/1024/1440 widths with increased text size.
Final suite/build results are recorded below after verification.

| Check | Actual result |
|---|---|
| Full API suite | 496 passed, 3 existing skips, 0 failed |
| Full AI suite | 605 passed; 4 existing dependency/controlled-fixture warnings |
| Full Flutter suite | 477 passed, 3 existing skips |
| Flutter analysis | No issues found; no Auth0 analysis failures |
| Source-health layout suite | 15 passed, including four widths and larger text |
| Web build | Passed |
| Android debug APK build | Passed |
| One-command native audit + frozen evaluation | Passed; no database writes, no fit/deployment |
| Retained-source health read | All 11 stored sources enabled with `ready` status |
| Live aggregate/source settings and pricing-model SHA-256 | Unchanged |
| `git diff --check` | Passed |

The API count differs from the prior run because obsolete positive tests for
removed providers were replaced with retirement and runner-safety tests. Existing
duration/package, permission, deactivation, provenance and inference tests remain.
Nonblocking build warnings concern the existing Socket.IO Wasm dry run and future
Kotlin plugin migration; standard web and Android debug builds both succeeded.
No real-device UAT was claimed, and no services were restarted for verification.

Data collection remains necessary for six missing domains, sparse product types,
real condition/age variation and genuine achieved rentals. Software cannot
establish those observations without suitable independent sources or actual
participant activity. No replacement providers, real payment gateway, fabricated
rentals, synthetic expansion or automatic candidate deployment were introduced.

## Commit message

```text
feat(pricing): retire unusable sources and automate clean evidence review

- remove five disabled source registrations and obsolete parser paths
- reject stale source IDs in collection, live comparables and clean exports
- preserve stored history and the eleven retained source integrations
- export canonical category coverage and report all-domain evidence gaps
- surface missing condition and item-age observations in administration
- add a bounded audit and frozen-evaluation command with non-overwriting outputs
- preserve genuine-payment gates and deployed models
```
