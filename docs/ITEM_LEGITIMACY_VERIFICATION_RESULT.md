# RentHub item-photo verification — implementation result

22 October follow-up: [false-match/context safeguards](ITEM_PHOTO_AND_PRICING_SAFEGUARDS_RESULT.md)
replace consistent-type claims with tentative detection wording and flag dominant
document/screen context for administrator review. [Item-risk training and advisory
activation](ITEM_RISK_TRAINING_RESULT.md) are complete; neither establishes
physical-item relevance or authenticity.

20 October follow-up: [YOLO-World and item-risk preparation](ITEM_WORLD_AND_RISK_PREPARATION_RESULT.md)
records the prepared optional model, v4 contract, actual bounded evaluation and
separate preview-only risk dataset workflow. Prompt availability is not complete
real-photo coverage or authenticity verification.

15 October category-coverage follow-up: see
[all-category audit and detail-view fixes](ITEM_LEGITIMACY_CATEGORY_COVERAGE_RESULT.md).
It supersedes the historical local-artifact inventory below: the custom detector
now exists (16 classes), local general weights supplement it, six of 22
subcategories still lack matching labels, and the item-risk model remains absent.
The new evidence contract is `renthub-item-evidence-v3`; model misses are manual
review evidence, not automatic photo-quality failures.

9 October update: public listing photo loading is fixed; all existing photo
inputs have confirmation previews. New verification results include boxes,
per-photo quality and view-coverage-weighted detection scores. These do not fix
model false positives or prove authenticity. See
[photo and pricing safeguards](ITEM_PHOTO_AND_PRICING_SAFEGUARDS_RESULT.md).

Updated: 8 October 2026. Scope: physical listing photos only; identity verification,
pricing, booking workflow and service listings retain their existing behavior.

## What is implemented

1. Flutter stores listing uploads through the existing Express API. Express reads
   owned stored bytes and sends category **and subcategory**, plus stated condition,
   to FastAPI. Client-supplied AI results are not accepted as listing evidence.
2. OpenCV decodes photos, requires at least three decodable views, reports existing
   blur/exposure/resolution checks and perceptual dHash repeats within a submission.
   A repeated hash is a similarity indicator, not proof of a stolen/duplicate photo.
3. YOLO labels use an explicit case-insensitive object ontology, not category-name
   substring matching. `car` matches Vehicles → Cars; it does not match Motorcycles.
   A background `person` cannot raise the submitted item's confidence. Detections
   below 0.55 do not count as a category match.
4. A custom `models/item_yolo.pt` is preferred. When absent, the already-downloaded
   `services/ai/yolov8n.pt` is usable as a **general pretrained** fallback. It is not
   relabelled as RentHub-trained, copied into the custom-artifact path, or downloaded
   during requests. Explicit custom-path failures never silently fall back.
5. Detector vocabulary determines category support. Unsupported classes are reported
   as **not assessed**, never as a mismatch or a pass. Corrupt models and per-photo
   inference failures result in explicit manual/partial review evidence.
6. Item EfficientNet inference requires a TorchScript artifact with the embedded
   `renthub-item-risk-v1` metadata contract, correct normal/risky ordering, RGB/224
   ImageNet normalization and two finite logits. KYC weights and generic ImageNet
   classification weights must not substitute for a trained item-risk classifier.
7. Each result records per-photo detections/risk scores, model availability/source,
   quality indicators and reasons. `confidence` represents matched object detections,
   **not authenticity confidence**. Condition is explicitly `not_assessed`.
8. Positive automated results are `approved_candidate`, never a final listing
   approval. Advisory submissions remain `pending_review`; an admin must approve.
   Strict mode accepts compatible candidates, preserves failed evidence on drafts
   and otherwise retains its existing blocking policy.
9. Submission history is persisted with the photo references, category, condition,
   timestamp and result. Editing clears current evidence, not previous history.
   Upload deletion refuses to remove photos referenced by moderation history.
10. Owner and Admin listing cards open a photo/check dialog. Stored photos can be
    enlarged; loading/unavailable states are explicit. The shared evidence panel
    explains limitations and distinguishes object-detection confidence from risk
    scores. Service listings never show physical-item verification controls.

## Category coverage

These are label mappings, not catalogue identities or pricing rules. Actual support
depends on the deployed detector's vocabulary; defining an alias does not train it.

| Category | Specific category | Example matching labels | Local general detector |
|---|---|---|---|
| Vehicles | Cars | car, automobile, sedan, SUV | car supported |
| Vehicles | Motorcycles | motorcycle, motorbike, scooter | motorcycle supported |
| Vehicles | Bicycles | bicycle, cycle | bicycle supported |
| Vehicles | Other vehicles | truck, bus, van, boat | truck/bus/boat supported |
| Devices | Smartphones | cell phone, mobile phone, smartphone | cell phone supported |
| Devices | Cameras | camera, digital camera, DSLR | unsupported; manual review |
| Devices | Computers | laptop, computer, desktop | laptop supported |
| Devices | Audio | speaker, headphones, microphone | unsupported; manual review |
| Devices | Gaming | gaming console, game controller | unsupported; manual review |
| Devices | Other devices | TV, projector, tablet, printer | TV supported; others limited |
| Equipment | Tools | drill, hammer, saw, wrench | unsupported; manual review |
| Equipment | Sports equipment | tennis racket, sports ball, skis | partial coverage |
| Equipment | Event equipment | chair, dining table, tent, speaker | chair/table only; partial |
| Equipment | Other equipment | generator, ladder, equipment | unsupported; manual review |
| Books | Textbooks / Reference books / Fiction / Other books | book | generic book only; not genre/title |
| Clothing | Formal wear | suit, tuxedo, dress | unsupported; manual review |
| Clothing | Costumes | costume | unsupported; manual review |
| Clothing | Traditional wear | baju Melayu, baju kurung, kebaya, sari | unsupported; manual review |
| Clothing | Other clothing | clothing, shirt, coat, jacket | unsupported; manual review |

Every specific category has an ontology regression case. These use controlled
detector fixtures and establish routing/filtering correctness, **not real-photo
detector accuracy**. General model coverage follows the actual locally loaded
vocabulary and [Ultralytics COCO classes](https://docs.ultralytics.com/datasets/detect/coco/).

## Current local artifact status and remaining work

- The existing local pretrained YOLO detector loads successfully and exposes car,
  motorcycle, bicycle, cell phone, laptop, book and other COCO labels.
- A custom RentHub item detector remains absent. Dataset inventory contains MyKad
  datasets, not a reviewed item detection/risk dataset. Unsupported item types need
  appropriate item annotations and fine-tuning, or manual review.
- `models/image_risk_efficientnet.pt` remains absent. **No item-risk training or
  real-world accuracy claim was fabricated in this implementation.** MyKad
  synthetic field-risk training does not establish item-photo risk performance.
- Health now reports `item_verification_contract` and compatible-model status,
  including the general-pretrained source and missing risk model. Artifact counts
  represent compatible availability, not category coverage or authenticity accuracy.
- Stock-photo, screenshot, AI-generated-image, ownership, exact brand/model and
  cosmetic condition detection are not established by a general object detector.
- Duplicate checks are within the supplied submission, not a marketplace-wide
  reuse database. Perceptual-hash collisions are possible and remain advisory.
- Admin APIs retain prior evidence. The new dialog displays the current submission,
  not a full historical timeline. Existing submissions need resubmission to receive
  the new item-evidence contract; no historical records were bulk rewritten.

## Preparing the item-risk model

Use permissioned item photos with independently reviewed labels. `normal` means
no labelled risk in that dataset; it must not mean "guaranteed genuine".

Create `.data/datasets/item-risk/manifest.csv`. Required columns:

```csv
path,label,item_id,split,source_type
photos/item-a-front.jpg,normal,item-a,train,reviewed_real
photos/item-a-altered.jpg,risky,item-a,train,synthetic_manipulation
photos/item-b-front.jpg,normal,item-b,validation,reviewed_real
photos/item-b-altered.jpg,risky,item-b,validation,synthetic_manipulation
photos/item-c-front.jpg,normal,item-c,test,reviewed_real
photos/item-c-altered.jpg,risky,item-c,test,synthetic_manipulation
```

This is a format example, not a dataset. At least 40 reviewed images are required;
40 is only an input floor, not sufficient evidence of real-world performance.
Both labels must exist in every split. Keep all views, captures and alterations
of the same item together. The loader rejects missing images, invalid provenance,
exact content duplicates and cross-split item groups. Supplied grouping cannot
prove independence by itself; review near-duplicates/source provenance separately.

```powershell
cd C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m app.training.train_image_risk `
  .data/datasets/item-risk/manifest.csv `
  --output .data/candidates/item-risk-round1 `
  --epochs 8 --acknowledge-source-permission
```

The trainer fine-tunes an EfficientNet-B0 two-class head, uses deterministic
evaluation transforms, keeps the frozen feature extractor in evaluation mode,
selects the best validation checkpoint and evaluates the held-out test split.
It exports the runtime metadata, source types, accuracy, macro-F1 and confusion
matrix, then checks a fresh-loaded export in the new isolated candidate directory.
It never replaces a deployed artifact. Pretrained initialization must be cached;
downloading requires an explicit `--allow-download`. See the
[readiness handoff](AI_VALIDATION_AND_DEMO_READINESS_RESULT.md).
Report synthetic evaluation separately; independent realistic held-out testing
is still needed before interpreting scores as useful real-world risk assistance.

For a custom detector, use the existing item-specific training command with a
permissioned YOLO detection dataset whose classes match the ontology:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_yolo .data/datasets/items/data.yaml
```

Do not point this command at a MyKad dataset. Keep train/validation/test photos of
the same item/source together. More epochs cannot add classes missing from data.

## Verification

- Full AI suite: **229 passed**. Existing KYC/pricing/recommendation tests included.
- Targeted Express suite: **30 passed**, covering item client/listing/upload
  contracts, strict mode, retained evidence and mandatory identity access.
- Full Flutter suite: **152 passed, 2 skipped**, including the photo-dialog
  interaction cases. The focused panel/dialog suite has **6 passing cases**.
- Focused analysis of all changed Dart files is clean.
- Flutter widget checks cover 360, 390 and 1024 logical-pixel widths and service
  exclusion. These are automated widget checks, not a live-device scan/visual UAT.
- Admin standard JavaScript web build succeeds. Existing Socket.IO WASM dry-run
  and Cupertino font warnings remain.
- Full Flutter analyzer still reports two pre-existing undefined named parameters
  in `test/auth0_persistence_test.dart`: `latestLinkProvider` and
  `mobileLinkPollInterval`. This unrelated Auth0 module was not modified.
- No live database mutation, permissioned-photo upload, model training, service
  shutdown, credentials change or mock marketplace data insertion was performed.
- The existing port-8001 service was not reachable during the final read-only
  probe. Runtime availability was checked in-process; no service was started
  or restarted on the user's behalf.

Restart the API/AI/app with the existing launcher if the running services have not
reloaded the changed code. Submit a new physical listing or edit/resubmit a rejected
one, then open its listing card in Owner/Admin to review photos and advisory checks.

## Plain-language review follow-up — 15 October 2026

The live Owner/Admin item-photo dialog now uses a compact summary rather than
displaying every model explanation, risk indicator and confidence percentage.

- Short status labels: **No photo issues flagged**, **Photos need attention**,
  **Photos need review**, **Photo check unavailable**, or **Photos not checked yet**.
- The main view shows a brief explanation and at most three practical notes, such
  as **Retake blurry photos** or **Replace repeated photos with different views**.
- **Photo details** expands category/photo-coverage information, remaining notes
  and short per-photo guidance. Raw server reasons are not copied into Owner copy;
  unknown concerns receive a conservative review message, not a made-up verdict.
- One reminder stays visible: **Photos alone cannot prove an item is genuine or
  who owns it.** The enlarged-photo explanation is also shorter and avoids jargon.
- Administrators can expand **Technical details** for the retained detector,
  classifier, synthetic-training, confidence and original review evidence. That
  section is collapsed by default and is not offered in the normal Owner dialog.
- Photo previews, enlargement, highlighted boxes and all moderation actions remain
  available. Services still do not display physical-item photo verification.

The new presentation adapter reads the existing response without changing model
results, thresholds, saved evidence, endpoints or authorization. Missing/malformed
summary metadata falls back to manual review rather than claiming success. No
retraining, API/AI code change, dependency or database update was needed.

Verification for this follow-up:

- Focused photo-panel and preview suites: **16 passed**.
- Full non-live Flutter suite: **379 passed, 3 skipped**.
- Source and changed-test analysis: **no issues**.
- Web build: **passed**, retaining the existing Socket.IO WebAssembly dry-run and
  Cupertino-font warnings.
- Full analysis retains the two existing Auth0 test named-parameter errors above.
- Widget coverage includes 360/390/1024 widths with 1.5x text for the panel,
  collapsed/expanded details, retained admin evidence, service exclusion,
  unavailable/partial/malformed summaries and opening/enlarging/closing photos.
  No Android hardware/visual UAT is claimed.

Hot-reload or restart Flutter, then open a physical listing's photo review from
Owner Listings. Repeat in Admin Listings to check the optional technical section.
The API and AI services do not need restarting for this presentation-only change.

Commit message:

```text
refactor(ui): simplify item photo verification wording

- replace lengthy evidence text with short statuses and practical photo notes
- move per-photo summaries behind expandable Photo details
- retain raw model evidence in collapsed administrator Technical details
- remove owner-facing scores and shorten photo-preview guidance
- preserve authenticity limits, photo previews and moderation behaviour
- add responsive wording and diagnostic-expansion regressions
```
