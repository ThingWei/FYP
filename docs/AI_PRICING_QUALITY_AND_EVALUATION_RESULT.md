# Pricing suitability, source recovery and frozen evaluation

28 October 2026. This follow-up implements all three requested work areas:
safer comparisons, recovery/review of published price observations, and evaluation
of the installed model before any retraining decision. Existing uncommitted work
is preserved. No live database records, source settings or model weights were
changed by the audit, preview or evaluation commands.

## 1. Suitable comparisons

The previous EOS R name-family heuristic let an EOS R50 borrow R3/R5/R6/R7
body-only prices. The earlier read-only reproduction selected seven observations
with a median of RM400 and produced RM357.45 for age one. A common name stem is
now insufficient to establish a comparable model family.

`productComparisonFacts.js` defines a reusable reviewed-specification contract.
Cross-model camera comparisons require matching reviewed attributes. Known
classes cannot borrow observations from unknown or contradictory classes.
Other domains retain an explicitly broad product-type fallback only when both
classes are unknown. Exact named products still require compatible product type,
package, variant and rental period. This is a selection policy, with no prices,
price tiers, depreciation rules or R50 price cap.

The initial reviewed camera facts cover sensor format, body type and in-body
stabilization for four models, sourced from manufacturer specifications:

- [EOS R50](https://asia.canon/en/consumer/eos-r50/body/specification): APS-C, mirrorless, no in-body stabilization.
- [EOS R10](https://asia.canon/en/consumer/eos-r10/body/specification): the same three comparison attributes.
- [EOS R7](https://asia.canon/en/consumer/eos-r7/body/specification): APS-C, mirrorless, with in-body stabilization.
- [EOS R6 Mark II](https://asia.canon/en/consumer/eos-r6-mark-ii/body/specification): full frame, mirrorless, with in-body stabilization.

These are identity/specification facts, not manufacturer price APIs or a claim
of identical capabilities. R50/R10 may be broadly compared; R50/R7 and R50/R6 II
are incompatible under this reviewed class. Additional models need reviewed facts
before cross-model camera evidence can be used. In particular, a missing class
does not silently inherit another camera's prices.

Camera adapters, accessories, action cameras, camcorders, cinema cameras and
lenses also have separate pricing types. Contradictory legacy coarse `camera`
tags are excluded until an ordinary validated refresh corrects them. The live
service clears client-supplied comparison facts and joins trusted catalogue/
reviewed metadata. Server-side absence of evidence overrides an incorrectly
available AI response. Manual pricing remains available with a readable message.

Selection is shared by live comparisons, exports and forward-time feature
rebuilding. Catalogue metadata projections now retain comparison facts. Native
exports retain rate basis, parser version, lens and comparison facts; fitted
feature names/order and endpoint paths are unchanged.

## 2. Published observations and parser recovery

The existing RENTISM parser discarded every plus-sign bundle. Parser version 3
now accepts an identifiable camera body plus one focal-range lens, stores the
lens separately and distinguishes that kit from a body-only offer in quotation
keys. Arbitrary multi-item bundles still fail. Explicit body-only markers are
preserved, and numeric DSLR body names within manufacturer sections are read.

[RENTISM's October price list](https://www.rentism.com.my/price-list/) advertises
the EOS R50 with 18–45mm lens at RM100/day. This is an asking price for a kit,
not evidence of a completed rental or a body-only tariff. Its nonfinal discount
ranges are not converted into invented multi-day quotes.

A bounded diagnostic collection returned 244 normalized observations, including
38 identifiable camera/lens kits. Results are private at:

`services/api/.data/evidence/pricing-quality-2026-10-28/rentism-preview.json`

The preview was not imported. Existing source enablement/maintainer approval
was observed; publisher reuse permission was not independently established by
this research. No new permission declaration or source enablement was made.
The ordinary configured source job will use the new parser when it next runs,
subject to existing approval, access and lease checks. Administrator deactivation
is preserved on refresh.

A final repeat of the direct source-access probe was unavailable, both within
the network sandbox and through the approved network execution path. It wrote
no new preview and left the successful earlier collection intact. This is an
actual remaining source-health limitation; the ordinary job must succeed before
newly parsed quotes appear in the live database.

[FFCAMERA's published tariff](https://ffcamera.my/price-list/) supplies two
additional R50 review candidates: RM90 for one day and RM160 total for two days.
The second is an RM80/day average, not a one-day quote. Package details, condition,
age and additional charges remain unconfirmed. These two observations are stored
in `additional-source-review-candidates.json` alongside the preview. They are
not imported, enabled, or represented as reuse-cleared evidence. R50 V remains
a separate product.

## 3. Current evidence audit

The bounded native audit issued only `find`/`getMore` database commands. It found
335 stored references; 313 passed current evidence/type eligibility, representing
249 distinct offers across 16 of 22 subcategories. Eligibility is distinct from
independently verified publisher reuse permission or transaction authenticity.
Counts can change when the existing scheduler or app is used.

| Category | Subcategory | Eligible observations | Distinct offers |
| --- | --- | ---: | ---: |
| Devices | Smartphones | 2 | 2 |
| Devices | Cameras | 159 | 159 |
| Devices | Computers | 3 | 3 |
| Devices | Audio | 8 | 8 |
| Devices | Gaming | 6 | 2 |
| Devices | Other devices | 6 | 6 |
| Vehicles | Cars | 73 | 13 |
| Vehicles | Motorcycles | 16 | 16 |
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
| **Total** | | **313** | **249** |

All eligible observations lack condition and item age. Fourteen physical
listings retain unknown price origin; they are excluded from clean evidence.
Both completed bookings are unsuitable as genuine completed-rental evidence:
one has simulated payment and the other lacks payment evidence. Demonstration
listings and simulated transactions remain excluded. No replacement history,
condition or age was fabricated.

## Frozen-model evaluation

Executed from `services/api`:

```powershell
npm.cmd run review:pricing-evidence -- --run-id pricing-quality-2026-10-28-final
```

The command refuses output overwrites and does not fit, collect or deploy a model.
Use a new run ID to repeat it. Private outputs:

- `services/api/.data/evidence/pricing-quality-2026-10-28-final/`: summary, observations, permission-gated preview.
- `services/ai/.data/evaluation/pricing-quality-2026-10-28-final.json`: frozen evaluation report.
- `services/ai/.data/evaluation/pricing-quality-2026-10-28-artifact-inspection.json`: fitted feature inspection.

After the final lens-type refinement, a second read-only run with ID
`pricing-quality-2026-10-28-verified` reproduced the same counts, split,
abstentions and unchanged checksum. Its audit/evaluation files use the same
directories above with that run ID.

The forward-time split used 289 earlier history rows and 24 holdout observations.
All 24 holdout observations lacked compatible earlier product evidence, so
prediction coverage was **0/24**, with **24 abstentions**. Status is
`insufficient_data`. MAE, RMSE, R² and the history-only category-median baseline
are unavailable for an evaluated prediction cohort, rather than reported as
zero errors. There are no eligible accepted-booking or completed-rental targets.
The later source batches do not constitute repeated histories for those products;
reshuffling them to obtain attractive accuracy figures would defeat the temporal
test. Permission-gated independent preview contained zero cleared rows because
no publisher reuse-review evidence file was supplied.

The installed artifact matches its saved report: 5,000 synthetic rows and 19
legacy rows labelled real. It has no row-level training manifest, so training
overlap cannot be established and any future comparison with this artifact must
retain that diagnostic limitation. Its SHA-256 remains:

`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`

No retraining candidate is justified by the current clean evidence. No deployed
artifact or production metrics were replaced.

## Controlled live-inference checks

Eighty read-only scenarios tested stored evidence versus the unimported parser
preview, body-only versus 18–45mm kit, lengths 1/2/3/7 and ages 0/1/3/5/8. There
were no failed AI requests. All stored R50 cases now abstain instead of using
R3/R5/R6/R7 prices. Preview body-only cases also abstain: a kit is not a body.

With the preview kit quote, condition Excellent, one rental day, neutral Owner
features and all evidence fixed, the running frozen model returned:

| Item age | Predicted daily amount |
| ---: | ---: |
| 0 | RM96.38 |
| 1 | RM93.88 |
| 3 | RM85.26 |
| 5 | RM80.38 |
| 8 | RM66.79 |

At age one, rental lengths 1/2/3/7 produced RM93.88/RM93.69/RM93.54/RM90.69 per
day. Multi-day cases retain a qualified daily baseline, not exact period-specific
tariffs or verified discounts. The published reference stays RM100/day.

The fitted global tree assigns normalized importance 0.02243 to item age,
0.00291 to duration, 0.15258 to active median and 0.28593 to historical median.
Age/duration genuinely reach fitted inference. These numbers describe a mostly
synthetic-trained model; neither the sensitivity check nor proximity to a single
quote establishes real-world accuracy. Private results:
`services/api/.data/evidence/pricing-quality-2026-10-28/controlled-inference.json`.

## Verification and remaining limits

- Full API suite: 549 passed, three optional skips; final affected selector/parser/export/sync suite: 125 passed after the lens-type refinement.
- Full AI suite: 606 passed; focused pricing suite: 49 passed. Existing sparse-fixture imputation and library deprecation warnings remain.
- Full Flutter suite: 489 passed, three skips; Flutter analysis: no issues.
- Launcher syntax, compatibility and disposable-process integration checks: passed. Running API advertises `pricing-daily-baseline-v1` and `pricing-suitability-v1`.
- Web and Android debug builds: passed. Web retains existing socket_io_common WebAssembly dry-run and Cupertino font warnings; normal JavaScript web build succeeds.
- Tests cover unsuitable EOS comparisons, generic reviewed-class matching, camera type separation, package/lens conflicts, kit/body quotation keys, idempotent refresh, forged client facts, evidence-free AI responses, duration baselines, offline chronology, and manual-price/retry presentation.

No real-device interaction check was performed. More reviewed class metadata is
needed beyond the initial four cameras; unknown non-camera classes still have
broad type comparisons. Six subcategories have no eligible observations, and
several others have only one business/product. Condition/age calibration and
achieved-rental accuracy need independently sourced, permissioned, repeated
observations and genuine transaction evidence. Catalog recognition and demo
activity cannot fill those gaps.

## Commit message

```text
fix(pricing): validate comparable classes and recover camera kit references

- require reviewed specifications for cross-model camera comparisons
- separate bodies, lenses, adapters, action cameras and camcorders
- preserve lens/package identity and distinct quotation keys on source refresh
- recover identifiable kits and numeric DSLR body names without price rules
- retain trusted class and rate-basis metadata in catalogue joins and exports
- reject evidence-free model responses and keep manual pricing available
- audit all 22 domains and evaluate the frozen artifact without deployment
- record source-review gaps, live sensitivity results and regression coverage
- update launcher capabilities to reject stale pricing services
```
