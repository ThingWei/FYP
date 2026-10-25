# AI validation and demonstration readiness

25 October: [current combined gap audit](AI_CATALOGUE_EVIDENCE_AND_RECOGNITION_GAP_REPORT.md)
confirms local model loadability, missing real-photo evaluation and cross-layer
peripheral/type mismatches. It separates fresh aggregate counts from historical
training/evaluation results; no retraining or activity generation was performed.

22 October follow-up: [CASIA/AutoSplice preparation](PUBLIC_ITEM_RISK_DATASET_RESULT.md)
and [actual eight-epoch candidate training](ITEM_RISK_TRAINING_RESULT.md) are complete.
The user acknowledged proceeding after the attribution discussion; CASIA's unclear
licence remains documented rather than independently verified. Held-out benchmark
accuracy is 68.64%; reviewed-real evaluation remains **not done**. The user later
authorized advisory activation at `models/image_risk_efficientnet.pt`; see the
training report's activation section for runtime checks and restart instructions.
The readiness snapshot below is historical (21 October), not a claim that the
subsequent candidate has already met its external validation gates.

Updated 21 October 2026. Scope: AI-assisted item-risk assessment with mandatory
administrator review, not counterfeit certification. Image permissions and iRent
access/reuse review remain pending, as selected by the user.

## Implemented tooling

| Area | Implemented | Still needed externally |
|---|---|---|
| Item-risk research | Isolated candidate training, cached-only initialization by default, fingerprint/configuration, provenance-separated metrics | Permission review, generated-pair inspection, actual training and independent real-photo evaluation |
| Recognition | All-22 collection template, strict reviewed-case validation, optional training group/hash exclusion, detector availability reporting | Permissioned photos/annotations and real all-category evaluation |
| Pricing | Forward-time offline evaluation using shared evidence code and fixed training-side history | More permissioned, historically reliable achieved-rental evidence |
| Recommendations | Native read-only bounded summaries, non-overwriting exports, explicit staged-user overlay and cohort baselines | Consent/exclusion review, tester activity and meaningful independent holdout |
| Source onboarding | Fresh bounded probes and documented review workflow; existing parser/access safeguards preserved | iRent review/enablement; 12RENT policy clarification; usable RentSmart catalogue |

No altered user photos, training dataset or deployed risk model was generated.
No live source was enabled, price imported, booking fabricated, database history
changed or deployed model replaced. Test-only tiny networks/controlled fixtures
exercise tooling; they are not EfficientNet performance or research results.
Existing uncommitted preparation work was preserved.

## Private collection kit

Generated metadata-only pack:
`services/ai/.data/evaluation/item-readiness-kit-v1/README.md`.
The earlier preview remains intact. See [the collection guide](AI_VALIDATION_COLLECTION_GUIDE.md)
for rights review, the 198-case photo checklist, consent guidance, tester scenarios,
staged-account handling, safe exports and onboarding steps.

The new pack selects 839 source-image hash proxy groups (400 train, 219 validation,
220 test), potentially at most 3,356 paired synthetic examples; **actual generated
images: zero**. It includes 235 source-annotation test cases across 10 domains,
not new independent evaluation. Twelve domains still have no source examples.
All 198 real-case template slots are empty/unreviewed. No coverage is invented.

## Candidate training interface and deployment separation

`train_image_risk` now **requires `--output`** pointing to a NEW candidate directory
under `.data`; old invocations without an output fail rather than writing to
`models/image_risk_efficientnet.pt`. Review rights before using the acknowledgement.
After permission, dataset generation and pair review, from `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_image_risk `
  .data/datasets/item_synthetic_risk_v1/manifest.csv `
  --output .data/candidates/item-risk-round1 `
  --epochs 8 --seed 42 --acknowledge-source-permission
```

This command was **not executed on the user's dataset**. Pretrained initialization
must be locally cached with the expected checksum; missing/corrupt weights fail.
Only explicitly adding `--allow-download` permits downloading initialization.
Defaults retain EfficientNet-B0, frozen features, two-class head, batch 16 and
learning rate 0.001. Model selection uses validation loss, not test performance.

Candidate output contains TorchScript weights, embedded metadata, configuration
and evaluation JSON with a manifest+image fingerprint. Each cohort reports samples,
confusion matrix, per-class precision/recall/F1 and macro metrics. Missing reviewed-real
test cases yield `not_evaluated` and null metrics. A single-label cohort is not a
complete two-class benchmark. Caller-supplied group/label provenance is not verified
by the trainer. Raw paths/photos are not included in reports.

There is no automatic deployment. After a separate intentional review, a maintainer
may point `IMAGE_RISK_MODEL_PATH` at a chosen trusted candidate and restart AI.
Do not copy/replace working weights casually. Runtime synthetic-only safeguards
remain advisory and unchanged; no authenticity or condition guarantee is introduced.

## Offline evaluation details

- Pricing CLI: `python -m app.training.evaluate_pricing --real-export FILE
  [--cutoff ISO_TIME] [--report NEW_PATH]`. Uses no synthetic rows by default or
  otherwise; demo/synthetic records are excluded and counted.
- Default cutoff is the 70% point of distinct observation-availability timestamps.
  Training observations must be known before it; test targets must occur at/after it.
  Late-known early targets and external records missing acquisition time are excluded.
- Comparable features are rebuilt through the shared Express selector, using only
  training-side rows. Each target additionally excludes its own product group,
  same/future times, late-known quotes, stale evidence, demo contamination and
  incompatible external types/duration bands. Holdout prices never become features.
- Historical owner aggregates cannot be rebuilt from the private export, so they
  are excluded/null rather than reusing potentially leaked totals. The fitted pipeline
  handles missing values; expected empty-feature warnings can occur in sparse fixtures.
- Reuses existing XGBoost feature order, pipeline and weights in memory. Reports
  MAE/RMSE and category/subcategory-median baseline separately for active asking,
  external asking, accepted bookings and completed rentals. No-holdout cohorts have
  null metrics. At least 20 training and five test rows are required mechanically;
  this minimum is not a reliability claim or deployment criterion.
- This is forward-time, not unseen-product evaluation. Seen holdout product-group
  counts are disclosed; current listing attributes remain an imperfect historical
  snapshot. No calibrated real-market accuracy or production-model improvement is claimed.
- Recommendation evaluation retains its existing per-user chronological split,
  ranking/cold-start reports and seen-holdout baseline guard; adds source-specific
  training-mean baselines. It does not evaluate the full content/proximity feed or
  become a global-time experiment. Staged cohorts cannot validate marketplace accuracy.
- Native recommendation exports preserve existing interaction strength/provenance
  precedence. `--staged-users PRIVATE_JSON` marks dedicated tester accounts' output
  as demo only. Both pricing/recommendation export files are exclusively created;
  existing files and database records remain untouched. Summary mode writes no file.

## Actual read-only checks on 21 October

MongoDB aggregate-only queries (zero database/file writes):

| Eligible pricing target | Count |
|---|---:|
| External asking references | 332 |
| Platform active asking prices | 3 |
| Accepted bookings | 4 |
| Completed rentals | 1 |

Recommendation summary: 16 marketplace-labelled interactions, eight pseudonymizable
accounts, nine listings; four views, ten booking signals and two published reviews.
This is not consent verification or proof of genuine commercial activity. No fresh
training export or real-data fitting was performed while consent review is pending.

Fresh source diagnostics (no database writes/enablement):

- **iRent:** six accepted Smartphone duration-band observations across seven pages;
  five skipped parser results. Publisher reuse permission remains unestablished.
- **12RENT:** `ACCESS_RESTRICTED`; no collector-policy bypass or new adapter needed.
- **RentSmart:** all three allowlisted public category pages passed the existing
  access check and returned HTML (31,396 / 31,423 / 31,329 bytes), without Product
  schema. The independently retrieved electronics page was a catalogue shell,
  not verifiable offers. No usable structured amount/period catalogue was established;
  adapter remains unavailable. Search snippets/private APIs were not ingested.

Current source access can change. Re-run the bounded diagnostics before onboarding.
Read-only probes do not grant permission. The initial sandbox network denial was
resolved through approved read-only diagnostics, not access-control circumvention.

## Verification and remaining checklist

- **Full AI suite: 502 passed.** Two existing dependency deprecations remain;
  two expected sklearn empty-feature warnings come from the controlled sparse
  pricing smoke fixture (not missing-data evidence being treated as zero error).
- **Full API suite: 414 passed, three optional tests skipped** (417 total).
  Tests use temporary MongoDB, mock auth/local storage, disabled email/FCM/blockchain,
  and the existing custom claim names. The initial bare run inherited live Auth0
  and was stopped; an isolated default-claim run exposed a pre-existing claim-setting
  assumption. The final correctly configured run passed without Auth0 code changes.
- Before/after SHA-256 inventories of all deployed AI models and metrics are
  identical. `git diff --check` passes; private kit files remain Git-ignored.
- No real-device photo test, participant session, trained EfficientNet candidate,
  fresh consented-data model evaluation, source enablement or model promotion occurred.

Reproduce API tests from `services/api` without loading live `.env` settings:

```powershell
$env:DOTENV_CONFIG_PATH='.data/disabled-environment-for-tests.env'
$env:NODE_ENV='test'
$env:AUTH_MODE='mock'
$env:AUTH0_EMAIL_CLAIM='https://renthub/email'
$env:AUTH0_NAME_CLAIM='https://renthub/name'
$env:STORAGE_MODE='local'
$env:FCM_MODE='disabled'
$env:EMAIL_MODE='disabled'
$env:BLOCKCHAIN_MODE='disabled'
npm.cmd test
```

Use a separate test terminal; these variables are process-local and do not edit
`.env`. AI command from `services/ai`: `.\.venv\Scripts\python.exe -m pytest -q`.

- [x] New training/output/cache/permission and manifest safety tests.
- [x] All-22/198-slot templates, empty drafts, source preservation and overlap tests.
- [x] Forward-time, late-known, same-product and holdout-leakage regressions.
- [x] Controlled real-pipeline smoke test, provenance cohorts and sparse-data states.
- [x] Native DB read-only/projection/bounds, staged overlays and concurrent exclusive-export tests.
- [x] Existing source restrictions/parsers/deduplication/deactivation regressions retained.
- [ ] Image permissions/attribution and physical-item grouping reviewed.
- [ ] Actual item-risk candidate trained and independently evaluated.
- [ ] Real recognition cases collected/reviewed across all 22 subcategories.
- [ ] Consented tester study and independently reviewed rental evidence collected.
- [ ] iRent permission review and explicit onboarding completed.
- [ ] 12RENT usable policy / RentSmart catalogue supplied by publisher.

No Flutter presentation or public endpoint/schema changed; Flutter builds are not
required for this tooling-only change. No Auth0, taxonomy, payment or hosting change.

## Commit message

```text
feat(ai): add safe candidate training and demonstration validation tooling

- isolate item-risk candidates with explicit permission and offline weight guards
- fingerprint datasets and separate synthetic and reviewed-real classification metrics
- prepare all-22 recognition collection slots and enforce reviewed-case overlap checks
- add forward-time pricing evaluation with fold-local shared comparable features
- bound native recommendation exports and preserve files through exclusive creation
- separate dedicated staged testers from marketplace evidence without rewriting history
- report source-specific recommendation baselines and sparse holdout limitations
- recheck source onboarding without bypassing policy or claiming publisher permission
- document consent, attribution, collection scenarios and actual readiness blockers
```
