# YOLO-World fallback and separate item-risk preparation

Updated: 20 October 2026. Item response contract: `renthub-item-evidence-v4`.

## Delivered / not claimed

- Installed optional, pinned CLIP preparation dependencies in the existing AI
  virtual environment. **Ultralytics 8.3.40, Torch 2.5.1, torchvision 0.20.1 and
  NumPy 1.26.4 were retained**, not upgraded.
- Downloaded official YOLOv8s-Worldv2 and CLIP ViT-B/32 weights and prepared
  `services/ai/models/item_world_offline.pt`. It contains 66 text prompts / 65
  canonical labels, including an open-book prompt mapped to `book`.
- Existing custom item weights were not replaced/retrained. CLIP is stripped
  from the saved runtime model; only frozen text embeddings remain. The encoder
  and raw download live under ignored `services/ai/.data/item-world`.
- Runtime loads only an existing, contract-compatible WorldModel, verifies the
  fixed vocabulary/hash and finite embedded features, and never calls
  `set_classes`, installs packages or downloads weights during requests.
- Added bounded real-photo evaluation, a separate dry-run-first synthetic ITEM
  risk generator, source-separated risk-training metrics and conservative UI
  copy. **No item-risk classifier was trained or invented.**
- No live MongoDB records, private identity photos, Auth0, KYC screening,
  pricing/recommendation models or hosting settings were changed. Private
  screenshot attachments were not added to any dataset or fixture.

Preparation follows [Ultralytics' offline-vocabulary approach](https://docs.ultralytics.com/models/yolo-world/).
Model download: [Ultralytics v8.3.0 small Worldv2 weights](https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8s-worldv2.pt).
CLIP preparation dependency: [official OpenAI CLIP pinned revision](https://github.com/openai/CLIP/tree/d05afc436d78f1c48dc0dbf8e5980a9d471f35f6).
CLIP encoder bytes are checked against the SHA-256 embedded in its official URL.
The output records raw-model checksums/source URLs; this is provenance recording,
not independent manufacturer/model certification. Review third-party reuse terms
before distributing model artifacts.

Prepared local artifact SHA-256:
`1c4d4efd5aaf9f1df6232e8f70febc88f92fc034321ab8cddfa4281de1faf43c`.
Vocabulary SHA-256:
`723c135b5733a75938c5cff0121b744e3e5d40bd8c4ae6b6cbd69e7d175fa802`.
Weights/caches remain ignored by Git.

## Runtime strategy

1. Keep the trained detector, supplementing it with existing general COCO weights.
2. Exhaust their bounded orientation retries before trying YOLO-World.
3. If those models miss, use the prepared World artifact with the **same fixed
   multi-domain vocabulary**, including competing person/paper/poster/screen/
   illustration classes. Do not force only the user's requested class.
4. Keep the existing 0.55 threshold, at most 20 boxes per prediction, four
   orientations and 3–10 submitted photos. Upper bound is three models x four
   orientations per photo. Map boxes back to original uploaded coordinates.
5. Record actual source/version/orientation per detection. A prompted match can
   contribute advisory object evidence, **never an automatic candidate pass**.
6. Missing/corrupt/disabled World artifacts leave existing detection and manual
   review available. Broken explicit primary-model configuration is not silently
   overridden. Missing, partial and failed evidence never becomes a genuine-item
   verdict. Low synthetic-only risk scores also cannot clear a candidate.

The existing YOLO tuple returned to KYC phone-screening consumers is unchanged.
World is scoped to item-listing verification, not MyKad anti-spoofing.
World inference uses the existing shared predictor lock; prompts are immutable
across requests/accounts/categories.

### All 22 subcategories: configured vocabulary, not measured full coverage

Existing C/G = custom/general labels. W = prompted World vocabulary. Every row
keeps `allProductsCovered=false`, `specificCategoryVerified=false` and an
unestablished subcategory-accuracy status. `openVocabularyOnly=true` identifies
the six domains without relevant C/G vocabulary. Generic book/garment object
recognition cannot verify genre, title, traditional-garment identity or authenticity.

| Category | Specific category | Available strategy / representative World labels |
|---|---|---|
| Devices | Smartphones | C/G then W: cell phone |
| Devices | Cameras | C then W: camera |
| Devices | Computers | C/G then W: laptop, desktop computer |
| Devices | Audio | C then W: headphones, microphone, speaker, amplifier |
| Devices | Gaming | W-only: game console, game controller |
| Devices | Other devices | G then W: tv, projector, tablet, printer |
| Vehicles | Cars | C/G then W: car |
| Vehicles | Motorcycles | C/G then W: motorcycle, scooter |
| Vehicles | Bicycles | C/G then W: bicycle |
| Vehicles | Other vehicles | G then W: truck, bus, van, boat |
| Equipment | Tools | C then W: drill, hammer, saw, wrench, screwdriver |
| Equipment | Sports equipment | C/G then W: racket, sports ball, dumbbell, kayak and existing sports labels |
| Equipment | Event equipment | C/G then W: chair, table, tent, projector, speaker, stage light |
| Equipment | Other equipment | W-only: generator, ladder, pressure washer, vacuum cleaner |
| Books | Textbooks | C/G then W: book/open book; no textbook verification |
| Books | Reference books | C/G then W: book/open book; no genre verification |
| Books | Fiction | C/G then W: book/open book; no fiction verification |
| Books | Other books | C/G then W: book/open book; inside pages can remain unconfirmed |
| Clothing | Formal wear | W-only: suit, tuxedo, dress |
| Clothing | Costumes | W-only: costume |
| Clothing | Traditional wear | W-only: baju Melayu, baju kurung, kebaya, sari; real testing especially important |
| Clothing | Other clothing | W-only: shirt, coat, jacket |

There are now configured object prompts for every current subcategory. **This
does not mean all 22 have been successfully evaluated on real photos.**

## Actual bounded held-out comparison

Evaluated the existing local Open Images **test** split with a deterministic cap
of three images per mapped source class. This yielded 41 annotated object/category
cases across 10 subcategories, not necessarily 41 distinct photos. Positive
localization requires the correct annotated class and IoU >= 0.50 against its box
at the unchanged confidence threshold. No source train/validation photos were used.

| Specific category | Cases | Existing C/G localized | Hybrid localized | World alone localized |
|---|---:|---:|---:|---:|
| Smartphones | 3 | 3 | 3 | 0 |
| Cameras | 3 | 2 | 2 | 0 |
| Computers | 3 | 2 | 2 | 2 |
| Audio | 6 | 2 | 2 | 0 |
| Cars | 3 | 3 | 3 | 2 |
| Motorcycles | 3 | 3 | 3 | 3 |
| Bicycles | 3 | 2 | 2 | 1 |
| Tools | 5 | 4 | 4 | 0 |
| Event equipment | 9 | 5 | 5 | 4 |
| Other books | 3 | 1 | 1 | 0 |
| **Total** | **41** | **27** | **27** | **12** |

There were zero inference failures. **No measured improvement in this sample**;
do not claim improved accuracy from installation. No hybrid case used a World
match in this run. The production pipeline stops when ordinary detection finds
a qualifying type, even if an external ground-truth localization check would
disagree. World is a miss fallback, not a second-opinion authenticity verifier.

Gaming, Other devices, Other vehicles, Sports equipment, Other equipment,
Textbooks, Reference books, Fiction and all four Clothing domains had **zero
evaluated cases**. Existing book annotations cannot be relabelled into three new
genres to fabricate coverage. No independently reviewed detail-view/negative set
was available. Blank-image network-blocked tests are controlled negatives, not
real-photo false-positive validation. This is bounded localization evidence,
not mAP, a calibrated authenticity percentage or complete benchmark coverage.
Do not tune on these same held-out cases and then report them as a new holdout.

Repeat without writes/downloads, from `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.audit_item_coverage
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition --dataset-yaml .data/datasets/open_images_items_v1/data.yaml --per-class 3
```

The audit distinguishes prompted-only categories from fixed-model label coverage.
Its existing `--require-labels-for-every-category` gate checks vocabulary only;
passing does **not** establish real-photo coverage.

### Add private evaluation cases

Place a reviewed JSON list in ignored `.data/evaluation/item-recognition/cases.json`.
Each case uses paths relative to the JSON, category, subcategory, view
(`overview`, `detail` or `unrelated`) and expectation (`target_present`,
`detail_only`, `target_absent`). Positive cases require a canonical `label` and
reviewed normalized `[left, top, right, bottom]` object `boxes`. Example schema:

```json
[
  {"path":"gaming/console.jpg","category":"Devices","subcategory":"Gaming","view":"overview","expectation":"target_present","label":"game console","boxes":[[0.1,0.1,0.9,0.9]]},
  {"path":"gaming/wallpaper.jpg","category":"Devices","subcategory":"Gaming","view":"unrelated","expectation":"target_absent"}
]
```

These coordinates are **format examples, not annotations for the user's photos**.
Collect permissioned whole-object, different-angle, detail and unrelated cases
across all 22 domains. A small smoke set does not establish production accuracy,
but independent reviewed cases are necessary to measure failures honestly.

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition --reviewed-cases .data/evaluation/item-recognition/cases.json
```

Reports aggregate counts only; paths, photo bytes and private identities are not
included. Unsupported/missing cases remain `not_evaluated`, not assumed passes.
Evaluation is read-only and has a 500-case cap.

## Separate item-risk preparation

Added `app.training.prepare_item_risk`, separate from all document/MyKad code:

- Reads local YOLO item annotations only; document field classes are excluded.
- Read-only preview by default. Explicit `--generate` and source-permission
  acknowledgement are required to write a new dataset. Existing nonempty outputs
  are never overwritten. No trainer is launched automatically.
- Keeps original train/validation/test boundaries, groups all derivatives under
  their source-image hash, checks exact cross-split duplicates and reports
  **physical-item-level grouping as unverified**. Hashes cannot establish that
  different photos belong to different physical items; near-duplicate/holder
  review is not replaced by this tool.
- Generates balanced normal/risky pairs with known local object-region erasure
  or copy/move operations. Brightness, rotation, encoding and research watermark
  are shared across each pair. No-op/duplicate outputs are not labelled risky.
- Both labels use `source_type=synthetic_manipulation`; unaltered baselines are
  not called genuine. No object class becomes a risk label automatically.
- Writes a trainer-compatible manifest with category, operation and proxy-group
  scope. This is **synthetic item-manipulation research**, not counterfeit,
  AI-image, stolen-photo, condition or ownership detection.

Actual preview, `--per-class 3`: **129 source-image groups** (48 train, 40
validation, 41 test), at most **516 generated images**, ten represented domains,
twelve unrepresented domains. **Preview only: none were generated or trained.**
The item-risk runtime artifact consequently remains unavailable.

After source-rights/group review, the available commands are:

```powershell
# Read-only preview, safe to repeat:
.\.venv\Scripts\python.exe -m app.training.prepare_item_risk .data/datasets/open_images_items_v1/data.yaml --per-class 3

# ONLY after reviewing permission, grouping and intended research use:
.\.venv\Scripts\python.exe -m app.training.prepare_item_risk .data/datasets/open_images_items_v1/data.yaml --per-class 3 --generate --acknowledge-source-permission

# Inspect/spot-review generated pairs and manifest BEFORE this explicit trainer:
.\.venv\Scripts\python.exe -m app.training.train_image_risk .data/datasets/item_synthetic_risk_v1/manifest.csv --epochs 8 --acknowledge-source-permission
```

If independent physical-item groups cannot be established, retain that limitation
and treat the metrics as a source-image-proxy synthetic study. Real-world
usefulness needs a separate reviewed real-photo dataset/test set; synthetic
performance cannot supply it. The trainer now records `evaluationScope`, label
definitions and `testMetricsBySourceType` separately. Runtime marks a
synthetic-only model as experimental and keeps its results under review even
when its risk score is low. KYC artifacts must not be reused.

## Setup and launcher

Prepared locally already. Normal `run-renthub.ps1` still starts AI with the API/
blockchain; no new long-running process is needed. It now requires
`renthub-item-evidence-v4`, checks compatibility against the Python constant in
regression tests, and refuses to silently reuse older item services. The optional
World availability message does not block ordinary/manual operation when missing.
Neither the launcher nor API automatically installs CLIP or downloads weights.

For another machine, explicitly prepare once from `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-item-world.txt
.\.venv\Scripts\python.exe -m app.training.prepare_item_world --download
```

This downloads roughly 400 MB and requires internet once. Subsequent preparation
can use cached weights without `--download`. Output-path guards protect existing
trained item/KYC/risk artifacts; a fresh-load inference check precedes replacement
of a previous World artifact. In `.env.example`:

```dotenv
ITEM_WORLD_ENABLED=true
ITEM_WORLD_MODEL_PATH=models/item_world_offline.pt
```

Defaults work with the local prepared artifact. Do not overwrite `.env` or copy
server secrets to Flutter. Keep the existing item enforcement advisory until
models are evaluated: strict mode still blocks non-candidate results, including
prompted/synthetic-only evidence. No checks auto-publish a listing.

Restart the original AI/API launcher, rebuild/hot-restart Flutter and resubmit a
draft/rejected listing. Old saved evidence is not bulk rewritten. If port 8001
has a v3 service, stop its original terminal with Ctrl+C before rerunning the
launcher; unrelated processes are never automatically killed.

## Verification / handoff

- Full AI suite: **471 passed**. Includes all-22 prompt mappings/advisory gates,
  ordinary-before-World ordering, unchanged threshold, unrelated objects,
  unavailable/disabled/corrupt weights, output-path protection, offline inference
  with HTTP/CLIP access blocked, truthful unevaluated reports, synthetic-only risk
  gating, source leakage, no-op rejection, paired labels and preserved sources.
- Focused API item-client/listing/identity-access suites: **28 passed** using
  temporary MongoDB. The all-22 listing test retains v4 prompted evidence and
  pending admin review; no live marketplace data is changed.
- Full Flutter suite: **407 passed, 3 skipped**. Photo messages, existing previews,
  360/390-pixel large-text panels and other prior regressions pass. Source and
  changed-test analysis are clean. Full analysis retains two unrelated Auth0 test
  parameter errors (`latestLinkProvider`, `mobileLinkPollInterval`, lines 41/43).
- PowerShell launcher syntax/compatibility regression passes; it accepts actual
  Python v4 and rejects missing/v3 item contracts. Tests do not start/kill services.
- Standard web and Android debug APK builds pass. Existing Socket.IO WASM/font
  and Kotlin-plugin migration warnings remain unrelated. No Android installation,
  camera UAT or actual live launcher restart was performed.
- Ultralytics attempted restricted user-cache writes during local read-only
  inference; these were denied without preventing evaluation.
- The original working tree was clean at this task's start. No unrelated module
  rewrite, bulk migration, secret change or primary detector training occurred.

Next hands-on work: supply reviewed real gaming/clothing/equipment test photos
and overview/detail/unrelated cases for every domain, run the evaluator, then
decide whether prompts or targeted fine-tuning need a new development set. The
user's attached book cover/pages have not been reproduced on Android here.

## Commit message

```text
feat(ai): add offline YOLO-World fallback and item-risk research preparation

- preserve trained/general detectors before bounded prompted fallback inference
- freeze category-aware vocabulary with competing non-item classes
- validate local World artifacts and prohibit runtime downloads or prompt changes
- keep prompted and synthetic-only evidence under administrator review
- add held-out localization evaluation with honest untested-category reporting
- prepare grouped synthetic item-risk pairs through an explicit preview workflow
- separate risk metrics by provenance without reusing MyKad weights
- coordinate launcher item-v4 compatibility and safe advisory UI wording
- add AI/API/Flutter/launcher regressions and document measured limitations
```
