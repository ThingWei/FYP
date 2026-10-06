# MyKad field detection and synthetic-risk runtime integration

## Delivered

Connected the user's trained combined field detector and crop classifier to
MyKad analysis, without replacing the whole-card scanner, general item risk,
passport model or driving-licence OCR/admin workflow. Existing model artifacts,
metrics, source datasets and protected user documents were not modified.

```text
Flutter MyKad front/back submission
  -> existing Express protected-upload + verification API
  -> FastAPI /verify/document (quality and OCR gates)
  -> combined field YOLO on original BGR images
  -> side/domain/confidence/geometry validation
  -> eligible RGB field crop + training-identical context/letterbox/normalization
  -> synthetic EfficientNet field-risk classifier
  -> advisory evidence + manual_review
  -> existing masked MongoDB verification history (pending)
  -> administrator evidence panel and explicit human review
```

This is runtime integration, **not validation of real-world authenticity**.
The user's crop-model test accuracy was 91.38%, recall 87.36%, ROC AUC 0.9532,
with copy-move recall 18/29. Those measurements used synthetic edits and annotated
oracle regions. Combined detector scores (mAP50 98.55%, recall 97.58%) are
validation scores. They must not be presented as end-to-end KYC performance.

## Field selection and preprocessing

- Uploaded image order remains front then back. Only expected-side classes score.
- Eligible: `front_identity_number`, `front_name`, `front_address`,
  `back_identity_number`, `back_serial_number`. The serial region is not an IC
  holder-number claim. Logos, faces, unrelated classes and opposite-side fields
  do not enter this classifier.
- Default detector confidence threshold 0.5; strongest detection per eligible
  class, finite in-bounds boxes, minimum 8 by 6 pixels. No fabricated region when
  detection is missing. At most five distinct eligible fields across both sides.
- Runtime and trainer share `document_risk_preprocessing.py`. Original colour
  data is converted BGR to RGB; no OCR contrast sharpening feeds the classifier.
  Field crop context, aspect-preserving letterbox, size and normalization come
  from the saved artifact contract.
- TorchScript must declare synthetic research provenance and a supported field
  contract. Missing metadata, a full-image artifact, unknown normalization or
  invalid dimensions fail closed. Combined detector classes are validated too.
- Cached models are CPU/evaluation mode; mutable YOLO prediction is serialized.
  No crop, upload, identity text or inference preview is saved by this adapter.

## Evidence and safety policy

`extracted_fields.documentFieldRisk` stores aggregate and per-side field signals:

- `status`: `available`, `partial`, `unavailable`, `disabled`.
- `sourceType=synthetic_manipulation`, research purpose, `advisoryOnly=true`,
  `requiresAdminReview=true`, artifact names and explanatory warnings.
- `riskScore`: maximum scored-field value, or null when no field was scored.
- `signal`: elevated at 0.5, otherwise no elevated signal, or unavailable.
- Per-side field names, detection confidence, risk score, missing required identity
  fields and analysis failure flag. No extracted personal values or image bytes.

The maximum is **uncalibrated**, not an authenticity probability. Its 0.5 threshold
is advisory triage only, not a new approval/rejection threshold. Completeness means
both identity-number regions were scored without analysis errors; it does not mean
all text, security features, holder identity or document legitimacy was verified.
Partial/absent fields and exceptions remain manual review even if another field
has a low score. Both low and high scores yield `accepted=false`, `manual_review`.
The approval check explicitly prevents MyKad automated candidates, independently
of warnings. Administrators retain the existing confirmed review actions.

Express already stores arbitrary AI evidence and keeps new submissions pending
(rescan_required remains resubmission_required). It strips raw OCR and masks
identity numbers before persistence; no new production Express transformation
was necessary. A MongoDB regression confirms the new evidence survives unchanged
while raw OCR is absent and the identity number masked. The new Flutter admin
panel explains synthetic provenance, coverage and uncalibrated scores instead of
printing the nested map in the generic extracted-fields line.

Whole-card live scanning is unchanged. Driving evidence never calls this model;
passport full-image inference rejects synthetic/crop artifacts accidentally pointed
at `DOCUMENT_RISK_MODEL_PATH`. Existing EasyOCR front/back matching remains its
separate heuristic: this integration does not add field-guided OCR, confirmed
two-sided identity matching, government/JPN/JPJ lookup or automatic authenticity.

## Configuration and use

Defaults use the artifacts already trained under `services/ai/models/`:

```dotenv
MYKAD_FIELD_RISK_ENABLED=true
MYKAD_FIELD_MODEL_PATH=models/mykad_fields_front_back_yolo.pt
MYKAD_FIELD_RISK_MODEL_PATH=models/document_risk_synthetic_fields_v2_efficientnet.pt
MYKAD_FIELD_DETECTION_THRESHOLD=0.5
```

These are documented in `services/ai/.env.example`. **No setup or renaming is
needed with the existing default filenames.** Overrides must be supplied to the
AI process environment; the launcher does not automatically load an AI `.env`.
Do not point `DOCUMENT_RISK_MODEL_PATH` at the crop model. Restart the AI process
to load this code or changed model files, and restart/hot-restart Flutter for the
admin panel. The existing launcher already starts the AI service; no new daemon
is needed. Merely rerunning it will not replace a previously running healthy AI
process. Existing KYC attempts are not silently reanalysed: submit a new permitted
front/back attempt to see new evidence.

`GET /health` adds separate MyKad field artifact-presence flags and reports enabled/
advisory status. Presence is not compatibility/readiness: contracts are validated
when first used. Quality failures or missing OCR models still stop before field
inference and request a rescan or report unavailability. Missing field models do
not prevent manual KYC submission. If cold OCR/model loading exceeds the API's
existing timeout, it returns unavailable evidence and stays pending; review the
logs and adjust `AI_TIMEOUT_MS` if necessary rather than granting approval.

## Validation and remaining work

- Full AI suite: **116 passed**, two existing third-party deprecation warnings.
- Focused inference/classification/training tests: **65 passed**. New coverage
  includes training/inference tensor parity, RGB channel order, expected-side and
  confidence filtering, duplicate classes, tiny/out-of-bounds regions, missing/
  disabled/corrupt/incompatible artifacts, nonfinite/wrong-shape logits, and low/
  high signals always requiring administrator review.
- Focused Express/MongoDB test: **1 passed**, in a temporary in-memory database
  with test/mock/local process settings; no real database or environment file
  changed. Initial run inherited Auth0 settings and returned 401; rerun with
  explicit test settings passed.
- Flutter admin panel: **9 passed**, including 360/1024 pixel widths and all four
  states. Existing scanner/driving regressions: **7 passed**. Focused analysis:
  no issues. These are automated widget checks, not a signed-in browser walkthrough.
- `flutter build web --no-pub` passed. Existing `socket_io_common` WebAssembly
  dry-run interop warning remains; the standard JavaScript web build succeeded.
  `git diff --check` passed. The complete unrelated Flutter/API suites were not run.
- Both actual artifacts loaded with validated provenance/classes. A blank-image
  smoke check exercised real YOLO and the real crop classifier (finite 1x2 output),
  with zero detected fields correctly giving unavailable/manual-review evidence.
  No identity images were used; this is not an accuracy benchmark.
- No trained artifact was overwritten; no new dependency or credentials added.

Remaining: independent permitted end-to-end evaluation on detector-selected fields,
per-side/class detector test evaluation (rare front watermark has insufficient
support), field-guided OCR/identity matching, whole-card scanner annotations/model,
real-world risk calibration and genuine-vs-manipulated evaluation. Holder-level
train/test grouping still needs human review. Keep protected application KYC
uploads out of training unless separately authorized and permitted.

Commit message:

```text
feat(kyc): integrate advisory MyKad field-risk models and admin evidence

- score side-validated YOLO field crops with the synthetic research classifier
- share training/inference preprocessing and enforce artifact contracts
- retain manual review for every synthetic signal and unavailable/partial result
- expose model availability and readable admin risk/coverage states
- add AI, MongoDB persistence and responsive widget regression tests
```
