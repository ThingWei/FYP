# RentHub catalogue, evidence and recognition gap report

Audit date: **25 October 2026, Malaysia time**. Read-only baseline and recommended
increments, not completed remediation or real-world accuracy certification.

Follow-up implementation: [item-type alignment](ITEM_RECOGNITION_TYPE_ALIGNMENT_RESULT.md)
addresses the recognition routing gap and exposes unsupported types. The audit
findings below are the original baseline. Pricing compatibility gaps, missing real
photo evaluation and unavailable monitor-specific model evidence remain open.

## 1. Executive summary

The main bottleneck is not simply an old API or missing training commands.

- All 22 physical subcategories have starter identities: **67 category-specific
  brand/author entries and 125 model/title entries**. These are not 67 distinct
  manufacturers or exhaustive product coverage.
- Five actual public-provider probes succeeded, including iPhone 17 Pro Max and
  MX Master 4. Those are manufacturer-confirmed 2025 examples, not a claim to
  cover every latest model as of this audit.
- **A cross-layer gap is confirmed:** mice/keyboards/monitors can be selected in
  the catalogue, but Computers pricing types remain desktop/laptop, and item
  verification excludes peripheral labels. Adding another catalogue API alone
  cannot fix this.
- MongoDB still has **334 eligible external asking-price observations across
  16/22 subcategories**, with no observed condition or item age. Platform activity
  is treated as staged according to the user's prior statement, not as real
  commercial transaction evidence.
- The local detector, general detector, prepared YOLO-World and advisory risk
  model load successfully. **The existing independent recognition pack has
  zero reviewed cases out of 198 planned slots.** Installed labels do not prove
  accuracy.

Recommended first increment: align existing product types across catalogue,
pricing compatibility and image evidence, starting with the explicitly requested
peripherals. Then expand reviewed identities and collect evidence, rather than
retraining on more synthetic data.

## 2. Inspected implementation and checks

Catalogue:

- `services/api/src/modules/catalog/catalog.coverage.js`, `catalog.curated.js`,
  `catalog.deviceDomains.js`, `catalog.provider.js:216`, `catalog.service.js:206`,
  `catalog.limits.js:4`, validation/controller/model files.
- Existing Owner picker/controller/form wiring and catalogue unit/widget tests;
  `docs/CATALOGUE_BROWSING_AND_FRESHNESS_RESULT.md`.

Evidence and evaluation:

- `services/api/src/scripts/auditPriceCoverage.js`, `exportPricingData.js`,
  `exportRecommendationData.js`; `priceCoverage.js`, `priceProductDomains.js`,
  `recommendationInteractions.js` and price-source registry.
- `services/ai/app/services/pricing.py`, `recommendation.py`,
  `app/training/audit_pricing_clarity.py` and local fitted artifacts.
- `services/ai/metrics/price_metrics.json`, `recommendation_metrics.json`;
  existing 22 October pricing/recommendation evaluation reports under
  `.data/evaluation/` (private, not copied into Git).

Recognition/risk:

- `services/ai/app/services/item_verification.py:24`, `item_world.py:14`,
  `app/training/evaluate_item_recognition.py`, `prepare_item_review.py`.
- Runtime artifact validation using `models_status()`, not just file existence.
- Existing `.data/evaluation/item-readiness-kit-v1/` reviewed-case/template files
  and item-risk candidate metrics/configuration; no source photographs opened.

Database reads used native MongoDB with projections, 10,000-row bounds and
timeouts, without Mongoose connection/index initialization. Observed command
names were **find/getMore only**. No database writes, exports of private rows,
source enablement, retraining, model downloads, service starts or secret changes.
Only this report and documentation links were written. Existing uncommitted
application work is preserved.

## 3. Current flows and boundaries

```text
Owner brand/model choice -> Express category-aware provider -> product cache
                        -> canonical selection on listing

Listing profile + compatible MongoDB price evidence -> Express -> FastAPI
                        -> fitted pricing features / conservative fallback

Listing photos + expected category/subcategory -> detectors + image-risk model
                        -> advisory evidence -> administrator review
```

Identity does not establish a rental price or authenticity. Those boundaries
are correct. However, independently maintained product-type registries have
drifted, so a selectable identity is not necessarily supported by the other two
flows. No diagram arrow above implies catalogue entries train either model.

## 4. Evidence-backed findings

Finding confidence below means confidence in the audit finding, not product-match
confidence, image-risk probability or pricing uncertainty.

| Priority | Finding / evidence | Impact | Finding confidence | Recommendation |
| --- | --- | --- | --- | --- |
| P1 | Catalogue Computers includes mouse/keyboard/monitor; `priceProductDomains.js:7` has only desktop/laptop | No compatible fine-grained peripheral price matching strategy | High: code inspection | Add semantic types and negative cross-type matching tests; no price rules |
| P1 | `item_verification.py:30` allows only computer/desktop/laptop; general installed detector already has mouse/keyboard labels | Valid peripheral photos cannot contribute those labels as Computer matches | High: code + loaded vocabulary | Align allowed types using available labels, preserving uncertainty and photo-context checks |
| P1 | Frozen World vocabulary lacks mouse/keyboard/monitor as item targets; screen is competing context (`item_world.py:14-29`) | Merely adding a word or changing the hash would not provide valid prepared weights | High | Do not relabel every screen/TV as a monitor. Evaluate a monitor-specific strategy; prepare any changed World candidate separately |
| P1 | Other vehicles catalogue/pricing use electric/mobility scooters, while AI `item_verification.py:39` allows truck/bus/van/boat | Same subcategory name hides different supported objects | High | Review compatible subtype mappings without moving existing listings or claiming exact recognition |
| P1 | Sports pricing includes camping tents; AI Sports labels omit tent (`item_verification.py:43`) while Event includes it | Legitimate camping items can be inconclusive in their selected domain | High | Review context-aware tent mappings; do not equate every tent with event equipment |
| P1 | 334 references; zero with age/condition; six subcategories have none | Insufficient model-specific and age-sensitive real-price validation | High: native DB summary | Collect reviewed explicit quotes; preserve missing attributes rather than fabricate values |
| P1 | 17 strongest interactions, all staged under the selected overlay; feedback form remains blank | No meaningful independent recommendation/user-study claim | High for counts; classification depends on prior user statement | Obtain consenting tester activity/feedback; preserve staged provenance |
| P1 | Existing recognition pack contains zero reviewed cases; risk real cohort has zero samples | No all-category real-photo performance baseline | High: file counts + embedded artifact metadata | Complete the diagnostic set and evaluate recognition/risk separately |
| P2 | 67 starter brand/author entries and 125 model/title entries | Initial browsing is necessarily sparse | High | Expand reviewed identities per product type; verify providers against failures before adding vendors |
| P2 | Nine subcategories have a dedicated structured strategy; thirteen rely on curated/general fallback | Uneven external coverage and validation depth | High: provider registry | Prioritize domain-level gaps, not one global text search or an unsupported completeness claim |
| P2 | Generic book label appears in all four Books domains (`item_verification.py:50`) | Detection does not verify genre/title/edition | High | Keep catalogue/ISBN/contextual human review separate; do not invent genre-detection accuracy |

## 5. Sources, cache and provenance

Dedicated structured strategies exist for Smartphones, Computers, Gaming, Cars,
Motorcycles and four Books subcategories. Other rows retain curated/validated
general fallback and manual entry. Classifications and manufacturer links may
be absent upstream even when a product exists.

The live MongoDB catalogue contains **315 rows across nine subcategories** in this
snapshot. No `wikidata-devices` source rows were observed. This does **not** prove
the new provider is unavailable: caching is on-demand, and this audit deliberately
did not call cache-writing catalogue endpoints. It also cannot prove the running
app/API has reloaded the latest code. Restart/relaunch and test the actual picker
before diagnosing a UI report as source absence. Old generic Computer/Gaming
cache rows are no longer trusted by the new provider chain; they were not deleted.

### Read-only public-provider checks

All five checks returned HTTP 200 from their upstream search/structured requests
and validated results. These were direct provider calls without MongoDB writes.

| Domain | Selected brand / typed query | Result |
| --- | --- | --- |
| Smartphones | Apple / iPhone 17 Pro Max | [Q136203050](https://www.wikidata.org/wiki/Q136203050) |
| Computers: mouse | Logitech / MX Master 4 | [Q136409079](https://www.wikidata.org/wiki/Q136409079) |
| Computers: keyboard | Logitech / MX Keys S | [Q125697771](https://www.wikidata.org/wiki/Q125697771) |
| Computers: monitor | Apple / Studio Display | [Q111154626](https://www.wikidata.org/wiki/Q111154626) |
| Gaming: controller | Sony / DualSense | [Q89695113](https://www.wikidata.org/wiki/Q89695113) |

The first two product identities were checked against
[Apple's announcement](https://www.apple.com/newsroom/2025/09/apple-unveils-iphone-17-pro-and-iphone-17-pro-max/)
and [Logitech's announcement](https://news.logitech.com/press-releases/news-details/2025/Remastering-an-Icon-Introducing-Logitech-MX-Master-4/default.aspx).
They were not imported as new starter entries or treated as rental-price data.
Observed request elapsed times were approximately 1.6-2.7 seconds in these runs,
not an availability/latency guarantee or complete provider benchmark.

### Price-source gates

The current stored/configured snapshot has 16 registered sources: 11 enabled,
iRent/Goritta/12RENT awaiting configured access review, and RentSmart/optional AVM
without usable adapters. iRent and 12RENT parser code already exists; do not
reimplement it. Earlier documented 12RENT policy and RentSmart retrieval blockers
were not bypassed or freshly re-probed here. Goritta requires written permission.
Source approval flags are configuration, not independent proof of reuse rights.

The CASIA rights uncertainty and AutoSplice research-use/attribution limitations
remain documented in `ITEM_RISK_TRAINING_RESULT.md`. No permission was inferred
from successful model loading or from downloaded files.

## 6. Quality baseline

### All-22 diagnostic inventory

Starter checks passed query-less brand retrieval and one model/title lookup per
subcategory. They do not establish external completeness. All independent photo
case counts below refer to the existing reviewed benchmark pack, not to informal
tests the user may have performed on the phone.

| Category | Subcategory | Starter brands / models | Eligible asking observations | Reviewed photo cases |
| --- | --- | ---: | ---: | ---: |
| Devices | Smartphones | 3 / 6 | 2 | 0 |
| Devices | Cameras | 3 / 6 | 181 | 0 |
| Devices | Computers | 4 / 9 | 3 | 0 |
| Devices | Audio | 3 / 9 | 8 | 0 |
| Devices | Gaming | 3 / 7 | 6 | 0 |
| Devices | Other devices | 3 / 6 | 6 | 0 |
| Vehicles | Cars | 3 / 8 | 73 | 0 |
| Vehicles | Motorcycles | 3 / 6 | 15 | 0 |
| Vehicles | Bicycles | 3 / 6 | 10 | 0 |
| Vehicles | Other vehicles | 3 / 6 | 0 | 0 |
| Equipment | Event equipment | 3 / 6 | 16 | 0 |
| Equipment | Tools | 3 / 6 | 1 | 0 |
| Equipment | Sports equipment | 3 / 6 | 0 | 0 |
| Equipment | Other equipment | 3 / 6 | 5 | 0 |
| Books | Textbooks | 3 / 5 | 0 | 0 |
| Books | Reference books | 3 / 4 | 0 | 0 |
| Books | Fiction | 3 / 6 | 0 | 0 |
| Books | Other books | 3 / 4 | 0 | 0 |
| Clothing | Formal wear | 3 / 2 | 1 | 0 |
| Clothing | Costumes | 3 / 3 | 3 | 0 |
| Clothing | Traditional wear | 3 / 2 | 3 | 0 |
| Clothing | Other clothing | 3 / 6 | 1 | 0 |

Prices include 253 named-product and 81 specification-only observations. Camera
evidence is 138 lenses and 43 cameras. Gaming's six rows are console duration
bands, not six independently priced controllers/consoles. No peripheral prices
or condition/age labels were inferred from specifications or retail prices.

### Pricing artifact and controlled inference

The local fitted artifact loaded; its saved metrics match its embedded metrics.
Model version `renthub-price-v2-66aad34c4295`, trained 6 October 2026. Training
contains 5,000 synthetic rows and 19 labelled `real`; those legacy labels do not
independently establish real commercial activity. SHA256 is unchanged:
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

With identical controlled evidence, Apple iPhone 17 Pro Max, Samsung Galaxy S25
Ultra and two deliberately unseen fixture identities all returned **RM65.30**
as a broad subcategory estimate. These are test predictions, not market quotes.

| Item age, all other inputs fixed | Predicted daily amount |
| ---: | ---: |
| 0 | RM67.14 |
| 1 | RM65.30 |
| 3 | RM58.50 |
| 5 | RM50.32 |
| 8 | RM38.77 |

Thus age reaches inference and affects this fitted model. Held-out permutation
MAE increases in the saved training distribution: item age 14.0210, brand 0.0590,
product model 0.0. This does not validate real depreciation: current external
observations have no recorded age/condition. Do not add hardcoded age penalties.

The current staged-overlay pricing summary has 342 eligible rows: 334 external
asking observations, three staged platform asks, four staged accepted bookings
and one staged completion. None becomes real achieved-rental evidence merely
because its database marker once said marketplace/real.

The **existing 22 October** non-deploying forward-time evaluation (not rerun or
retrained today) used 310 earlier asking observations and 24 later targets:
MAE RM89.66 versus category-median baseline RM118.13, RMSE RM127.49, R-squared
-0.1178. All targets used category-wide evidence. This is limited asking-price
evaluation, not exact-model or achieved-rental accuracy.

The configured running AI health endpoint was not reachable during this audit,
including the privileged read-only check. Local loadability is verified;
matching the currently running process/artifact remains unverified. No service
was started or settings changed.

### Recommendations

Current strongest-signal summary: 17 interactions across eight accounts and nine
listings: four views, eleven booking signals, two published reviews. Accounts
are not independently verified participants; stronger signals can hide earlier
saves/views, so these are not raw event totals.

The all-staged overlay uses the user's earlier description of their/dedicated
demo activity, changes no database markers and exports no rows. Reconfirm and
use consent/exclusion handling if new natural or third-party activity is added.
The existing feedback form remains blank (`consentRecorded=false`), not completed
user-study evidence.

The local SVD artifact loads and knows 127 users/186 items. Its saved training
report is 3,360 synthetic + 11 legacy marketplace-labelled interactions. The
existing 22 October staged-only diagnostic held out four interactions with only
two ranking users; its strong recall is not generalizable and marketplace-only
evaluation is insufficient. See `PRICING_RECOMMENDATION_EVIDENCE_ROUND1_RESULT.md`.

### Recognition and risk

Load/contract checks succeeded for the 16-label trained detector, 80-label general
detector, 65-label prepared World model and item-risk classifier. These counts
are vocabularies, not independent RentHub training classes/accuracy guarantees.
Gaming, Other equipment and four Clothing subcategories rely on World-only
matching labels. All 22 have some matching vocabulary, not complete subtype
coverage or calibrated performance.

The current real-photo pack has 198 slots, zero paths filled and zero reviewed
cases. The evaluator correctly refuses an empty pack rather than generating
successful metrics. No recognition inference on private photos was attempted.

The deployed-local risk artifact matches the trained candidate SHA256:
`6913286b4a82ddebffb0027542663248d1beaacd1b8d46a3a4a1a9d427eea02d`.
Embedded evaluation remains `synthetic_only`: 2,714 benchmark images, macro-F1
0.6848, risky precision 0.6729 and recall 0.6513. It missed 446 altered benchmark
images and flagged 405 unaltered ones. Reviewed-real samples remain zero. Neither
the model nor its confidence establishes ownership, condition or authenticity.

Ultralytics attempted user-profile settings/cache writes during local loading;
the sandbox denied them. Model validation still succeeded; permissions were not
broadened to suppress these warnings.

## 7. Minimal target design and trade-offs

Reuse the current stack and endpoints. Maintain reviewed product types per
category/subcategory, with explicit mappings into:

1. catalogue provider types and starter identities;
2. pricing compatibility/evidence types;
3. available detector labels/prompts and unsupported/manual-review states.

A schema/type registry is not training data or a price rule. Books still need
identity/context for title/genre. A monitor should not be accepted merely because
a generic screen/TV was detected. World vocabulary changes require an isolated
prepared candidate with matching embeddings/hash, not editing the runtime names.

Alternative: immediately add another API. It may expand identities but does not
resolve these mapping/evidence gaps and adds access, licence and maintenance
costs. Evaluate it only against measured misses. No universal free or exhaustive
provider has been established by this audit.

## 8. Phased work and acceptance gates

| Increment | Acceptance evidence | Dependency / relative effort | Rollback |
| --- | --- | --- | --- |
| A: subtype consistency | Mouse/keyboard/controller/monitor selection cannot silently inherit laptop/console price evidence; supported labels match correct domain; unsupported remains reviewable; negative cross-type tests pass | Existing labels can help mouse/keyboard; monitor requires reviewed strategy. Small-medium code change, plus real evaluation | Retain contracts/old artifacts; revert scoped mapping patch, never delete user records |
| B: broader selection | Reviewed brands/models per relevant product type across all 22; sources recorded; current missing examples tested; failures remain distinct from no-match | Source research; do not require the user to know model names. Medium ongoing curation | Additive IDs, no automatic replacement of saved selections |
| C: price evidence | Explicit MYR periods/packages and lawful sources; missing types filled where usable; asking/accepted/completed/staged cohorts separate; forward-time results reported against baseline | Permission/source/data dependent; no invented quotes or age fields | New observations deactivate independently; no booking-history rewrite |
| D: recommendation study | Consented staged sessions/feedback, cold-start cases, independent chronological holdout and baseline comparisons | Actual participant activity; do not generate it on their behalf | Evaluation-only exports, no automatic model replacement |
| E: image evaluation | 198-case diagnostic pack reviewed with actual boxes/permissions; detector/World/hybrid and unrelated false positives reported separately | 44 distinct items x 3 views plus 66 unrelated cases. Collection-dependent | Preserve holdout; any later tuning uses a new evaluation set |
| F: justified retraining | Candidate improves the declared independent cohorts, with no leakage and explicit deployment review | Only after C/D/E provide suitable evidence | Keep current artifacts; candidate directory and explicit rollback |

The 198 cases are a small diagnostic target, not a statistical completeness
threshold. Reuse `docs/AI_VALIDATION_COLLECTION_GUIDE.md`,
`docs/PRICING_RECOMMENDATION_TEST_SESSION.md` and the existing private kit; do not
create another competing set of templates.

## 9. Decisions/input still needed

- No missing-model list is required from the user: representative source research
  can be done by the agent. User examples remain useful but are not a blocker.
- Permissioned independent photos and consenting tester participation cannot be
  fabricated by tooling. The user/participants supply or authorize those inputs.
- Publisher access/reuse conditions must be resolved before blocked collection.
- A material paid-provider choice, new taxonomy, changed image artifact or model
  deployment requires separate explicit approval. No such choice was assumed.

## 10. Smallest recommended next implementation

**Do subtype consistency first**, covering the explicitly requested mouse,
keyboard, monitor and controller cases end-to-end. Add semantic compatibility
and image-label tests without lowering thresholds or treating catalogue presence
as image proof. Reuse the installed mouse/keyboard detector labels where valid;
leave uncertain monitor evidence under review until tested.

Then expand reviewed identities and collect missing evidence. Do not start by
retraining both models or enabling all sources: the present gaps would survive.

This turn changed documentation only. Full test/build results in the previous
browsing handoff (480 API / 473 Flutter, clean analysis and web/Android builds)
are historical 24 October verification, not newly rerun suites for this audit.

Suggested documentation commit:
`docs: audit catalogue breadth, pricing evidence and image-type alignment gaps`.
