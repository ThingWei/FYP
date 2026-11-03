# Item-photo and pricing evidence follow-up

The implementation follow-up at the end records the specification guard and
isolated recognition candidate added after the initial research round below.

Executed 3 November 2026. This extends the existing evaluation kit and frozen-model
audit. It does not complete independent real-world validation, retrain/deploy a
model, import prices, enable a source or change marketplace records.

## New photo diagnostics

Five additional photographs were downloaded from file-specific Wikimedia licence
records and visually inspected. They have attribution, licence URLs, image hashes
and reviewed annotations in the private pack. No pixels were locally edited.
The sources are:

- [Controllers, Ted Mielczarek, CC0](https://commons.wikimedia.org/wiki/File:Game_Controllers.jpg).
- [Vacuum cleaner, Che, CC BY-SA 2.5](https://commons.wikimedia.org/wiki/File:Vacuum_cleaner.jpg).
- [Kebaya, Mike Peel, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:At_Peranakan_Museum,_Singapore_2023_061.jpg).
- [Raincoat, Rathfelder, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Harold_Wilson%27s_raincoat.jpg).
- [Keyboard detail, Yogazsor72, CC0](https://commons.wikimedia.org/wiki/File:Part_of_keyboard.jpg).

The final set contains three positive scenes, four unrelated-category checks and
two detail views from five unique photos. Four controllers in one scene still
count as one case. One tentative negative was excluded because a clipped device
edge made its absence label uncertain; the initial run remains preserved.

| Positive scene | Configured/general | YOLO-World | Production hybrid |
| --- | --- | --- | --- |
| Gaming controllers | Missed | Localized | Localized |
| Vacuum cleaner | Missed | Missed | Missed |
| Traditional garment (kebaya) | Missed | Missed | Missed |

All three variants returned zero false matches on the four final unrelated
checks and zero unavailable cases. Raincoat/keyboard close-ups remain detail
cases, excluded from whole-object localization success rates. No new threshold,
prompt, label, weight or authenticity rule was introduced to improve this set.

There were zero exact-byte overlaps against 1,582 known detector training/
development photos. This does not establish physical-item independence or rule
out resized copies/pretrained-model overlap. Public photos are diagnostic
material, not a representative Malaysian rental-photo benchmark. They have no
authenticity, ownership, condition or manipulation ground truth. No item-risk
classification metrics were manufactured from them. The already enabled risk
model's original CASIA/AutoSplice benchmark is documented in
[round two](AI_VALIDATION_ROUND2_RESULT.md); independent rental-photo risk
performance remains unevaluated.

Private outputs under `services/ai/.data/evaluation/public-photo-round3-2026-11-03-reviewed/`:
`sources.json`, `ATTRIBUTION.md`, `overlap_check.json`, `reviewed_cases_final.json`,
`training_exclusions.csv`, `result_final.json` and unedited `photos/`.

## Easier collection across all 22 subcategories

Extended the existing `services/ai/.data/evaluation/item-readiness-kit-v1/` pack
with real empty folders under `photos/`, `PHOTO_DROP_GUIDE.md` and
`photo_drop_slots_2026-11-03.json`. Its original template/review records were
preserved. There are 198 suggested paths, all still unreviewed and without
confirmed permissions, labels or boxes. Empty folders are not completed cases.

For each subcategory, photograph two different items: overview, alternate angle
and detail for each; add three genuinely unrelated images. Example:
`photos/devices/smartphones/item-1/overview.jpg`. Users can supply originals
without editing JSON or drawing boxes; visual annotation can follow. Record
actual book genre/edition and garment context rather than guessing from appearance.
Start with cleaning equipment, traditional garments, books and desktops/monitors,
then finish remaining subcategories. Keep these evaluation items out of later
training; failures used for development require a new evaluation set afterward.

## Fresh pricing audit and frozen evaluation

Ran the existing read-only workflow with run ID `ai-help-2026-11-03`.
399 stored observations were scanned; 377 were eligible under the current
policy across 16/22 subcategories. Eligibility is not independent publisher
permission or achieved-rental verification. There are zero verified completed-
rental targets and zero supplied age/condition values among the eligible rows.

| Category | Specific category | Eligible asking observations |
| --- | --- | ---: |
| Devices | Smartphones | 2 |
| Devices | Cameras | 223 |
| Devices | Computers | 3 |
| Devices | Audio | 8 |
| Devices | Gaming | 6 |
| Devices | Other devices | 6 |
| Vehicles | Cars | 73 |
| Vehicles | Motorcycles | 16 |
| Vehicles | Bicycles | 10 |
| Vehicles | Other vehicles | 0 |
| Equipment | Event equipment | 16 |
| Equipment | Tools | 1 |
| Equipment | Sports equipment | 0 |
| Equipment | Other equipment | 5 |
| Books | Textbooks | 0 |
| Books | Reference books | 0 |
| Books | Fiction | 0 |
| Books | Other books | 0 |
| Clothing | Formal wear | 1 |
| Clothing | Costumes | 3 |
| Clothing | Traditional wear | 3 |
| Clothing | Other clothing | 1 |

The forward-time diagnostic used 360 history rows and 17 holdout targets.
Only three targets had compatible prior evidence; fourteen abstained.
For those three, model MAE was RM269.22 and RMSE RM295.77, versus the history-only
category-median baseline's RM250.00 and RM278.39. These tiny, source-concentrated
asking-price results do not validate marketplace accuracy. The legacy artifact
has no row-level training manifest, so training overlap is unverified.

The error trace identifies three unbranded Event equipment/projector targets:

| Stored target specification | Stored daily asking amount | Frozen prediction |
| --- | ---: | ---: |
| 2200 ANSI lumens | RM200.00 | RM80.78 |
| 2700 ANSI lumens | RM350.00 | RM80.78 |
| 3500 ANSI lumens | RM500.00 | RM80.78 |

Each received three broader projector comparisons with RM75 median. Current
fitted features do not distinguish those brightness specifications; adding
unrelated quotations or duplicating demo listings would not resolve this.
Prioritize specification/package-compatible observations and evaluate a reviewed
comparison policy before considering a separately trained candidate. No fixed
brand/specification price rule or change to the deployed prediction was added.

The price artifact remains SHA-256
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
The workflow reported zero database writes and no model deployment.

## Price research preview and remaining gaps

Prepared five factual preview rows, **not imports**:

- The Rental Guy: two individual camping tents (RM60/RM80), mini speaker (RM30)
  and mini projector (RM50), each a one-usage-day reference before tax. Delivery
  and setup are separate. These four offers already appeared in earlier research;
  rechecking them does not create four independent new offers. Source:
  [camping page](https://therentalguy.com.my/camping-equipment-2/), with duration
  context checked against its [FAQ](https://therentalguy.com.my/faq/).
- Lazy Traveler: unbranded electric scooter, stated 40 km range/25 km/h, RM55/day.
  It is specification-only Other vehicles evidence, not a petrol motorcycle or
  exact model match. Source: [operator page](https://www.lazytraveler.my/langkawi/getting-around).

Missing manufacturer/model/age/condition remain null. Originating-offer keys use
the existing shared identity helper. Publisher data-reuse permission was not
independently established; the preview is excluded from clean training and
automatic collection. Existing source settings were not changed.

Direct Joy of Books/Carousell book-page retrieval did not succeed; search leads
were not admitted as verified quotations. Dr Scooter's headline minimums were
excluded. Hiking equipment with unsupported product types was not forced into
unrelated categories. No per-title textbook/reference/fiction observation was
verified. These remain collection gaps, not generated prices.

Private pricing outputs:

- `services/api/.data/evidence/ai-help-2026-11-03/`: audit summary, observations,
  permission-gated preview and `source_research_preview.json`.
- `services/ai/.data/evaluation/ai-help-2026-11-03.json`: frozen evaluation.
- `services/ai/.data/evaluation/ai-help-2026-11-03-error-trace.json`: three safe
  public-source diagnostic comparisons, without account/identity/location data.

## Verification and next work

Executed actual installed-model inference for baseline, World and hybrid,
review/overlap checks, the bounded MongoDB audit, forward-time frozen pricing
evaluation and a matching per-target error trace. Private outputs are Git-ignored.
No application/source adapter/production evaluator code changed, so application
tests/builds were not repeated for this research/documentation-only round.

Next: collect/review new physical-photo cases, use separate training items for
demonstrated recognition gaps, and obtain repeated permissioned, compatible
quotations for sparse price domains. Genuine completed rentals must come from
actual nonsimulated transactions; the current demo checkout cannot create them.
Retraining, import and real-world accuracy remain uncompleted.

Suggested commit message:

```text
docs(ai): record fresh photo diagnostics and pricing evidence gaps

- document licensed controller, cleaning-equipment and garment checks
- extend the private all-category photo collection kit with drop folders
- report frozen pricing errors, abstentions and specification limitations
- prepare unimported source research without inventing rental history
```

## Implementation follow-up: specification guards and recognition candidate

Implemented 3 November after the request to continue items 1 and 2. Existing
uncommitted work is preserved. No production dependency, database migration,
price-source activation, import, fitted feature or deployed weight was changed.

### Pricing comparison fix

`pricingSpecifications.js` now constrains the existing shared
`compatibleProductReference` function before tier selection. It reads only
explicit product/model text; it does not manufacture reviewed facts, a canonical
identity, a price or a specification from a brand name.

| Product types | Explicit comparison attributes |
| --- | --- |
| Projectors | Brightness value and ANSI/ISO/LED/unspecified lumen standard |
| Monitors, televisions, laptops, desktops | Display diagonal in inches |
| Laptops, desktops | Explicit RAM GB and SSD GB/TB |
| Camping tents | Numeric people/person/pax capacity |
| Drills | Voltage |

Case, Unicode compatibility forms, thousands separators and common unit/hyphen
formats normalize consistently. Different measurement standards are not converted
into equivalence. Multiple conflicting values, alternatives/ranges, zero/negative
values or a known value on only one side cannot establish compatibility. Unknown
values are not zero. Meaningless model digits are not interpreted as specs.
When both sides lack these attributes, the existing broad type/class policy
remains in force; camera/edition/lens/package/type guards still apply.

The guard applies to platform asking prices, external references, completed-
rental comparisons, exports and offline historical feature reconstruction through
the same existing selector. It cannot be bypassed by matching catalogue IDs or
coarse reviewed classes. Valid matching-spec observations remain selectable.
No endpoint/payload, completed-rental history/count or XGBoost feature order was
changed. Manual pricing remains available. This can reduce suggestion availability
until suitable references exist; it is not a newly trained accurate price model.

Replayed the **same frozen 377-row input**, same 360/17 history/holdout split,
same input hash and same XGBoost artifact used above. The three incompatible
projector predictions are now abstentions: 0/17 predicted, 17/17 abstained, with
null error metrics. This is a compatibility/safety improvement, not zero error or
an accuracy improvement. The previously reported RM80.78 projector estimates
are not replaced with invented rates. A separate fresh read-only audit was also
run; its changing collection timestamps are not used for the before/after claim.

New private report:
`services/ai/.data/evaluation/ai-help-spec-fix-frozen-input-2026-11-03.json`.
The price artifact still matches the SHA-256 recorded above.

### Recognition candidate and new photo checks

Added the optional `object_views_v3` profile to the existing preparation/loading
tools. Its 108 fixed prompts include 12 concrete object-view descriptions for
vacuum cleaners, garments, books and computer displays. Canonical object labels
and competing screen/paper/illustration/person classes remain. It never uses
the requested category as a per-request prompt or lowers confidence thresholds.
The original baseline prompt/hash/defaults remain unchanged.

Prepared a separate candidate using the already cached YOLO-World and
checksum-verified CLIP weights; no model downloads or detector fine-tuning.
The candidate stays under `.data/candidates/item-world-object-views-v3/model.pt`
and was **not activated**. Its SHA-256 is
`22cacf3773c9251a68f71374465f3c6ffe501f0b739a175d5afb1a6f6cb4020f`.

The first nine-case set above was used for development diagnosis. Both the old
expanded candidate and this candidate kept its hybrid result: 1/3 localized
positive scenes, 0/4 unrelated false matches and two separately reported detail
views. Neither fixes the missed vacuum/garment on that set.

After freezing the candidate prompts, collected four further file-specific
licensed photos, visually reviewed boxes/context and checked known training
overlap through the existing manifest:

- [Vacuum, Antonio Mette, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Aspirapolvere_Electrolux.JPG).
- [Kebaya, Bjoertvedt, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Kabaya_first_half_20th_century_Malaya_IMG_9763_singapore_peranakan_museum.jpg).
- [Books, Ch. Maderthoner, CC0](https://commons.wikimedia.org/wiki/File:Old_Books_01.JPG).
- [Monitors, Wikideas1, CC0](https://commons.wikimedia.org/wiki/File:Vertical_monitor_2.jpg).

These create four positive scenes and four unrelated-category checks, not eight
independent photos. No genres, ages, condition, authenticity or risk labels were
invented. Downloaded renditions were not locally pixel-edited; attribution and
licence links remain with the private files. Known exact training overlap is
zero, but near-duplicate/physical-item/pretrained-model overlap remains unknown.

| Additional positive scene | Deployed hybrid | Expanded-v2 hybrid | Object-views-v3 hybrid |
| --- | --- | --- | --- |
| Vacuum cleaner | Missed | Missed | Missed |
| Kebaya | Missed | Missed | Localized |
| Stack of books (Other books) | Missed | Missed | Missed |
| Computer monitors | Missed | Missed | Missed |

All three returned zero false matches on the four unrelated checks and zero
unavailable cases. On the earlier 33-case regression pack, the new hybrid kept
7/9 positive localizations and 0/22 false matches; World alone localized 4/9.
The old regression pack is already development material, not an independent
holdout. These small public-image checks do not justify global deployment or a
claim of reliable all-22 coverage. The new candidate remains isolated.

Private new collection/results:
`services/ai/.data/evaluation/public-photo-candidate-check-2026-11-03/` contains
four photos, attribution, reviewed cases, deployed/v2/v3 reports and prior
regression results. The original risk classifier is unchanged; these unlabelled-
for-risk photos cannot establish manipulation or counterfeit accuracy.

### Verification and outstanding work

- Full API suite: **632 passed, 3 existing optional skips** (635 total).
- Final affected pricing suites: **40 passed**, including compatible-reference
  retention, live-tier exclusion and asking/completed historical feature checks.
- Final full AI suite: **637 passed**, four existing dependency/sparse-fixture
  warnings. Candidate inference is tested with network/prompt encoding forbidden.
- New candidate preparation and three actual detector variants were evaluated;
  confidence stayed 0.55. Ultralytics' denied user-profile cache/settings writes
  remain nonfatal; report files confirm zero unavailable cases.
- The matching-input frozen pricing report confirms unchanged input/model hashes.
  No candidate pricing fit, source import or database write was requested.
- No Flutter presentation/contract changed; Flutter builds were not rerun for
  these API/AI-only changes.

Recognition improvement is **not complete**: new, varied physical-photo data and
separate training/evaluation items are still needed for demonstrated misses.
The existing 198-slot/22-subcategory photo-drop kit remains ready for collection.
All six price-data gaps, unknown age/condition and lack of genuine transaction
evidence remain. Source research previews remain excluded pending their separate
access/reuse review; new stored rates were not invented to fill those gaps.

Commit message for this implementation:

```text
fix(ai): constrain pricing specifications and evaluate recognition candidate

- reject conflicting or missing explicit specs before comparable tier selection
- share projector, display, memory, capacity and voltage guards across evidence
- preserve feature order and abstain from unsupported frozen-model estimates
- prepare an isolated offline object-view vocabulary without changing defaults
- evaluate licensed photo cohorts and retain deployment gates after limited gains
- add pricing and candidate regressions and document remaining data gaps
```
