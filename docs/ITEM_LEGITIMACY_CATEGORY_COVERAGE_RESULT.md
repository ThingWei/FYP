# Item-photo checks: category coverage and detail views

25 October follow-up: [object-type alignment and current inventory](ITEM_RECOGNITION_TYPE_ALIGNMENT_RESULT.md)
adds type-scoped checks, mouse/keyboard routes and explicit unsupported types.
It records all 22 subcategories, remaining per-type gaps and evaluation readiness;
the historical matrix below does not describe current complete coverage.

20 October follow-up: [offline YOLO-World and item-risk preparation](ITEM_WORLD_AND_RISK_PREPARATION_RESULT.md)
adds the prepared optional fallback and v4 contract. All 22 domains now have
configured prompts, but real-photo testing remains incomplete; the bounded local
comparison did not show improved hybrid localization. This 15 October matrix
below remains the historical **fixed-model** label audit, not today's prompted
vocabulary coverage or a full-accuracy claim.

Updated: 15 October 2026. Contract: `renthub-item-evidence-v3`.

## Outcome and important limit

The generic pipeline and review experience now handle every **22 current physical
subcategory routes**, not just Books. This is **not complete automatic recognition
of every product**. In-process inspection found a 16-class custom detector and an
existing 80-class general YOLO detector. Together they expose at least one relevant
object label for 16 of 22 subcategories. Six have no matching local labels.

An object label is not measured subcategory coverage: a laptop label does not
cover every computer, `book` cannot establish genre/title, and a garment label
cannot establish costume or traditional-wear identity. All matrix rows explicitly
retain `allProductsCovered=false`, `specificCategoryVerified=false` and an
unestablished subcategory-accuracy status. No trained classes were invented.

`models/image_risk_efficientnet.pt` is absent locally. MyKad risk weights must not
substitute for an item-risk model. Consequently local results still need review,
even when object detections succeed.

## Generic changes

- Retain the configured custom detector. Supplement with the already-local
  `ITEM_PRETRAINED_YOLO_PATH` (default `yolov8n.pt`) when
  `ITEM_ALLOW_PRETRAINED_DETECTOR=true` (existing default). No model download,
  new dependency, retraining or existing-artifact replacement occurs.
- Select inference models by their **actual matching vocabulary**, not merely by
  category names. Unknown/missing specific categories stay unassessed. The generic
  word `equipment` no longer pretends to establish an item type.
- Try the uploaded orientation, then 90/270/180-degree rotations on misses.
  This is shared by all supported object domains. Threshold remains **0.55**.
  Stop at positive evidence; at most two models x four orientations per photo,
  with at most 20 boxes per prediction and 3–10 decoded photos per submission.
- Rotate only inference input. Uploaded bytes, quality checks and previews remain
  unchanged. Transform returned boxes back into the original photo coordinates.
  Record source/version/orientation; repeated predictions are not extra views.
- Distinguish actual blur/exposure/resolution concerns from **inconclusive object
  evidence**. A missed cover, inside page, care label, port close-up or tyre detail
  is not automatically a visibility, category-mismatch or authenticity failure.
- Missing detections/partial views return `manual_review` with no invented quality
  indicator. Unconfirmed views remain unverified; one good overview never clears
  unrelated photos. Partial views do not become `approved_candidate`.
- Existing quality, duplicate, elevated-risk and failed-analysis checks remain.
  Candidate gating still requires all views, compatible risk analysis and no
  concerns; it never publishes a listing. Administrator approval stays mandatory.
- Advisory mode accepts reviewable submissions into `pending_review`. Existing
  strict mode still blocks non-candidates; it is not silently changed to advisory.
- Owner form gives category-appropriate overview/detail guidance. The review
  dialog says **“Some views could not be identified automatically. An admin will
  review them.”** rather than claiming every photo is unclear. Actual poor quality
  still receives specific retake guidance. Older saved results get safe wording
  too, but resubmission is needed for fresh model evidence.
- Admin-only expanded diagnostics retain boxes, scores, coverage and detector
  sources. Ordinary Owner copy does not expose model internals. KYC, pricing,
  service verification, Auth0 and booking behaviour were not changed by this fix.

## Actual local vocabulary matrix

**C** = `models/item_yolo.pt` (16 labels); **G** = existing `yolov8n.pt`
(80 labels). “Limited” means vocabulary overlap only, **not full or measured
recognition**. Every row has the same administrator-review fallback.

| Category | Specific category | Relevant local labels/source | Coverage / photo examples |
|---|---|---|---|
| Devices | Smartphones | cell phone — C/G | Limited; whole device, back, ports |
| Devices | Cameras | camera — C | Limited; camera body, other side, controls |
| Devices | Computers | laptop — C/G | Limited; whole device, other side, label/ports; desktop gap |
| Devices | Audio | headphones, microphone — C | Limited; whole device, other side, connections; speaker gap |
| Devices | Gaming | None | Manual; console/controller needs trained labels |
| Devices | Other devices | tv — G | Limited; whole device, other side, label; projector/tablet/printer gap |
| Vehicles | Cars | car — C/G | Limited; whole vehicle, other angle, condition details |
| Vehicles | Motorcycles | motorcycle — C/G | Limited; whole vehicle, other angle, condition details |
| Vehicles | Bicycles | bicycle — C/G | Limited; whole bicycle, other angle, gears/frame |
| Vehicles | Other vehicles | truck, bus, boat — G | Limited; whole vehicle, other angle, condition details |
| Equipment | Tools | drill, hammer, screwdriver, wrench — C | Limited; whole tool, attachments, label; other tool gaps |
| Equipment | Sports equipment | bicycle — C/G; sports ball, tennis racket, baseball bat/glove, skateboard, surfboard, skis, snowboard — G | Limited; whole equipment, another angle, condition; other sports gaps |
| Equipment | Event equipment | chair, table, tent — C; chair, dining table — G | Limited; whole equipment, another side, attachments; AV/lighting gaps |
| Equipment | Other equipment | None | Manual; generator/ladder/cleaning-equipment gaps |
| Books | Textbooks | book — C/G | Generic book only; cover, spine/back, inside page |
| Books | Reference books | book — C/G | Generic book only; cover, spine/back, inside page |
| Books | Fiction | book — C/G | Generic book only; cover, spine/back, inside page |
| Books | Other books | book — C/G | Generic book only; cover, spine/back, inside page |
| Clothing | Formal wear | None | Manual; whole garment, reverse, fabric/care label |
| Clothing | Costumes | None | Manual; whole garment, reverse, fabric/care label |
| Clothing | Traditional wear | None | Manual; whole garment, reverse, fabric/care label |
| Clothing | Other clothing | None | Manual; whole garment, reverse, fabric/care label |

## Repeat the read-only audit

From `services/ai`, using the same environment as the running AI process:

```powershell
.\.venv\Scripts\python.exe -m app.training.audit_item_coverage
```

The output lists all 22 categories, available source labels and missing domains.
It does not print identity data, read MongoDB, write reports or change weights.
For a deployment check that exits 2 when any subcategory has **no matching label**:

```powershell
.\.venv\Scripts\python.exe -m app.training.audit_item_coverage --require-labels-for-every-category
```

Passing this optional gate would still **not** establish real-photo accuracy or
complete within-category coverage. `/health` also returns this matrix inside
`item_verification_status.categoryCoverage`. Individual results store only their
selected category's matrix row plus detector diagnostics, avoiding global-matrix
duplication in listing history.

## Training/data gaps

The existing prepared Open Images dataset contains 1,803 images across 16 labels,
not all RentHub products. Its preparation report has 62 train / 12 validation /
13 test book images and zero held-out hammer examples. Preparation status is not
a fitted-model evaluation. More epochs on those same classes cannot add gaming,
clothing or missing equipment classes.

Completing automatic coverage requires permissioned, annotated photos spanning
the missing classes and realistic within-category variation, including overview,
open/inside and detail views, orientations, unrelated negatives and illustrations.
Keep item/source groups separate across training, validation and held-out tests.
Evaluate per class and per subcategory, including false positives; then deploy
reviewed weights through the existing configured detector path. Item-risk data
and evaluation remain a separate requirement. No sample data or names were
blacklisted and no text-reading heuristic was used to turn arbitrary text into
a book detection.

## Verification

- AI regression fixtures exercise positive ontology routing plus partial/no-label
  behaviour for **every one of the 22 subcategories**. A parity test checks the AI
  matrix against Express's live catalog taxonomy so new subcategories cannot be
  forgotten silently. Rotation/box mapping is tested at 90/180/270 degrees across
  all 22 domains. These are logic tests, **not detector-accuracy measurements**.
- Explicit tests cover local supplementation, absent weights/no download, bounded
  attempts, unchanged confidence threshold, unrelated high-confidence detections,
  unknown categories, missing risk models, bad quality, duplicate photos and
  inference errors. The read-only audit's reporting/failure gate is tested.
- Express integration test submits all 22 category/subcategory pairs with stored
  image reads and retained inconclusive evidence/history; none auto-publishes.
- Flutter tests cover category-specific guidance without blaming model misses on
  photo quality, legacy evidence, expanded diagnostics, existing previews and
  360/390-pixel detail-view panels with 1.5x text scaling.
- Actual local models loaded in-process: C has 16 labels, G has 80. A blank-image
  smoke test for Books, Sports equipment and unsupported Traditional wear produced
  zero expected-type matches and zero inference failures. Blank-image checks do
  not establish real-item accuracy. Restricted-environment Ultralytics attempts
  to update its user-cache settings were denied; inference still completed.
- Full AI suite: **437 passed**. Full API suite: **365 passed, 3 skipped**.
- Full Flutter suite (`--exclude-tags live`): **406 passed, 3 skipped**. This
  includes the two new 360/390-pixel large-text detail-view layouts. Application
  source and focused listing-photo test analysis are clean.
- Full Flutter analysis retains exactly the two existing Auth0 test errors:
  undefined `latestLinkProvider` and `mobileLinkPollInterval` in
  `test/auth0_persistence_test.dart:41,43`. They were not changed here.
- Final standard web build and Android debug APK build succeed. Existing
  Socket.IO WASM dry-run warnings, initial Cupertino font warning and
  firebase_core/shared_preferences_android Kotlin-plugin migration warning
  remain unrelated. No actual Android installation or real-device capture was
  performed. The debug build is not a configured release APK.
- `git diff --check` passes. Existing uncommitted work remains intact. No live
  MongoDB writes, weight downloads, model training or service restarts occurred.

The three supplied book photos were inspected visually in the conversation only;
they were not saved, trained on or committed as fixtures. Their post-change model
predictions have **not** been reproduced on Android. Close crops, opened pages,
flat illustrations, screens and unseen products can still confuse either model.
No automatic authenticity, condition, ownership or exact-edition claim is made.

## Device handoff

Restart the AI/API with the existing launcher, then hot-restart the app. Check
`item_verification_contract=renthub-item-evidence-v3`. Resubmit a draft/rejected
listing to produce a new result; old evidence is not bulk rewritten. Re-test the
book cover/pages, a whole item plus detail views in other domains, unrelated
wallpaper photos, actual poor-quality photos, and the six unsupported domains.
Advisory submissions should remain pending for admin review; missed detections
must not claim unreadable photos or become automatic passes. Verify highlighted
regions align on sideways images. Do not expect the generic `book` label to
establish the exact title or genre.

Suggested commit message (this category-coverage follow-up only):

```text
fix: make item photo checks category-aware and honest about model coverage

- audit all 22 physical subcategories against actual detector vocabularies
- supplement the custom detector with existing local general weights
- retry bounded orientations and map evidence boxes to original photos
- keep missed detail views inconclusive instead of reporting poor visibility
- add category-specific photo guidance and admin coverage diagnostics
- add cross-category AI, API and Flutter regressions and coverage audit tooling
- document unsupported classes, missing risk model and real-photo test limits
```

Existing uncommitted camera/batch-upload and paid-pending booking changes were
preserved; this suggested commit describes only the category-check follow-up.
