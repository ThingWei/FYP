# Item recognition type alignment and evaluation readiness

Next increment: [expanded isolated World candidate](ITEM_WORLD_EXPANDED_CANDIDATE_RESULT.md)
was prepared locally without deployment. Its larger vocabulary is not measured
real-photo accuracy; the active-model inventory below remains unchanged.

Updated 25 October 2026. This change fixes routing and exposes remaining gaps.
It does not establish improved real-photo accuracy or complete authenticity
verification.

## Implemented

- `item_domains.py` defines 92 object-type routes within all 22 physical
  subcategories. Category-only callers retain their vocabulary. An explicit
  known type narrows accepted labels; unknown types cannot inherit other labels.
- Computers uses the general detector's existing mouse/keyboard labels.
  Controller uses the prepared World's existing label. A laptop cannot validate
  a typed mouse, nor a console a typed controller.
- Monitor requires a computer-monitor label, not TV or the competing screen
  label. VR headset, mobility scooter and camping tent also have explicit routes;
  generic headphones/scooter/tent cannot establish those specialised types.
- Express resolves `specifications.productType` from the stored selected product
  with matching canonical ID, category, subcategory, brand and model. Submitted
  type values, price inference and manufacturer APIs are not used. Missing
  catalogue type metadata retains category-only evidence: a remaining limitation.
- The optional FastAPI `expected_product_type` and additive
  `renthub-item-types-v1` evidence contract preserve existing endpoints. Express
  treats an older AI response ignoring a supplied type as unavailable. Restart
  both services when deploying. Manual listing entry remains available.
- The existing audit reports support per type and accepts
  `--require-labels-for-every-type`; this fails while label gaps remain.
- The evaluator reports per-type positive localization and unrelated-image
  false-positive case rates, assessed denominators and unavailable inference.
  It applies production photo-context checks. Missing cohorts have null rates.
  Baseline, World-only and hybrid detection remain separate. Detail views receive
  no fabricated positive boxes or successful localization claims.
- Collection templates include optional reviewed `product_type` and a per-type
  checklist. Existing drafts were preserved.

Thresholds, runtime prompts, prepared embeddings, trained weights, prices,
pricing evidence, identity checks and administrator approval rules are unchanged.
Book detection does not establish title, edition or genre.

## Actual local vocabulary inventory

Existing artifacts loaded: custom detector (16 labels), general detector (80),
prepared YOLO-World (65), and item-risk classifier. Across the **92 routes, 62
have matching labels and 30 require manual review**. Routes can share labels;
these are not 92 independently trained classes or measured accuracies. World
prompts remain uncalibrated. No subcategory is claimed completely covered.

| Category | Specific category | Types with local matching labels | Types needing manual review / further evidence |
|---|---|---|---|
| Devices | Smartphones | Smartphone | Variants and accuracy untested |
| Devices | Cameras | Camera | Camera lens |
| Devices | Computers | Laptop, desktop, mouse, keyboard | Monitor |
| Devices | Audio | Speaker, headphones, microphone, amplifier | Audio mixer |
| Devices | Gaming | Console, controller | VR headset |
| Devices | Other devices | Television, projector, tablet, printer | Walkie-talkie, video capture, smartwatch |
| Vehicles | Cars | Car | Models and variants untested |
| Vehicles | Motorcycles | Motorcycle | Models and variants untested |
| Vehicles | Bicycles | Bicycle | Models and variants untested |
| Vehicles | Other vehicles | Legacy truck, bus, van, boat | Electric scooter, mobility scooter, electric unicycle |
| Equipment | Tools | Drill, hammer, saw, wrench, screwdriver, ladder | Sander, grinder, generic power tool |
| Equipment | Sports equipment | Racket, ball, baseball bat/glove, skateboard, surfboard, skis, snowboard, bicycle, kayak, dumbbell | Camping tent, sleeping bag, golf clubs, paddleboard, life jacket, snorkel set, fitness equipment |
| Equipment | Event equipment | Chair, table, tent/canopy, projector, speaker, lighting, television | Mixer, tripod, PA set |
| Equipment | Other equipment | Generator, ladder, pressure washer, vacuum | Fabric cleaner |
| Books | Textbooks | Book | Textbook context, title and edition unverified |
| Books | Reference books | Book | Reference-book context, title and edition unverified |
| Books | Fiction | Book | Fiction genre, title and edition unverified |
| Books | Other books | Book | Title and edition unverified |
| Clothing | Formal wear | Suit, formal dress | Formal jacket, unspecified formal wear |
| Clothing | Costumes | Costume | Styles and accuracy untested |
| Clothing | Traditional wear | Malay traditional garments, sari | Hanfu, kurta, unspecified traditional costume |
| Clothing | Other clothing | Winter garment, general garment | Rainwear |

Private inventory:
`services/ai/.data/evaluation/item-subtype-coverage-2026-10-25-v1.json`.
It records zero evaluated photos and unchanged SHA-256 digests for all four item
artifacts. Ultralytics attempted profile-cache/settings writes that the sandbox
denied; model loading succeeded. No permission expansion was used.

## Prepared collection and evaluation

New private pack:
`services/ai/.data/evaluation/item-subtype-readiness-v1/`.
It contains the existing 198-slot diagnostic structure: two distinct items with
overview, alternate and detail photos, plus three unrelated photos per subcategory.
It adds type checklists and source-review metadata. `reviewed_cases.json` remains
empty and all slots unreviewed. The 132 source test annotations are not independent
reviewed real-world cases. Existing packs were not overwritten.

The 198 cases are a first diagnostic set, not proof for all 92 types. Add held-out
examples for each relevant type; keep those physical items out of training and
development. Positive examples need reviewed normalized boxes and compatible
labels. Review/rights flags must reflect actual checks. No labels, boxes, consent
or photo paths were fabricated. Open Images synthetic-generation permission is
still pending. This preparation generated metadata only, with no source-photo
inference or training.

From `services/ai`:

```powershell
# Vocabulary only: no source-photo inference or accuracy claims.
.\.venv\Scripts\python.exe -m app.training.audit_item_coverage
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition --coverage-only

# After completing and reviewing actual permissioned cases:
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/item-subtype-readiness-v1/reviewed_cases.json
```

Empty reviewed cases remain an explicit error. Collect targeted training data
after diagnostics identify failures. More mapping entries or epochs are not
evidence of better accuracy.

## Verification and remaining work

Routing fixtures cover all 22 domains, catalogue/AI peripheral type agreement,
mouse/keyboard positives, cross-type negatives, monitor-versus-TV/screen,
controller-versus-console, unknown types, specialised garment/vehicle/tent
limitations, typed annotation validation, unavailable metrics and API forwarding/
old-service guards. These fixtures are not accuracy evidence. Final suite results
are recorded below.

- Full AI suite: 592 passed, four existing dependency/imputation warnings.
- After extending source-annotation type routing, focused AI tests: 81 passed.
- Full API suite: 487 passed, three existing optional skips.
- Model SHA-256 checks repeated after verification: all four unchanged.
- No Flutter source changes; Flutter tests/builds were not repeated for this
  server/AI-only change. The preceding catalogue change's checks remain recorded
  in its separate result document.

Real all-category recognition evaluation remains **not completed**. The risk
classifier remains trained and advisory; reviewed real rental-photo risk evaluation
remains **not completed**. Existing benchmark results do not establish authenticity,
condition or ownership. Missing types need a separately prepared/evaluated model
candidate or targeted labelled data before stronger coverage claims. No Flutter
presentation changes were needed.

Suggested commit:

```text
fix(ai): align item recognition with catalogue object types

- define explicit type routes across all 22 physical subcategories
- use existing mouse, keyboard and controller labels without lowering thresholds
- narrow checks using server-resolved catalogue metadata and guard AI contracts
- retain unsupported/manual-review states and production photo-context checks
- report per-type localization, false positives and unavailable inference
- extend private collection templates without changing datasets or artifacts
- add cross-type, API forwarding and evaluation regression tests
```
