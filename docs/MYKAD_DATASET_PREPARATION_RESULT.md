# MyKad dataset preparation result

## Scope

Prepared the user-supplied local field dataset for initial research. Original
images/labels were not modified, uploaded, committed or used to train a model.
No production KYC records were used. No bounding boxes, tamper labels, document
authenticity decisions, or accuracy values were fabricated.

Source: `services/ai/.data/datasets/mykad/c4rd2.v1i.yolov8/`.
Prepared copy: `services/ai/.data/datasets/mykad_fields_prepared_v1/`.
The supplied YAML declares CC BY 4.0 and Roboflow provenance; actual licence,
redistribution rights and consent still require review, not merely trusting the
export metadata. This report contains only aggregate results, no IC data/images.

## Measured audit

| Check | Result |
| --- | --- |
| Images / corresponding labels | 206 / 206 |
| Successfully decoded images | 206 |
| Independent filename/duplicate groups | 82 **proxy groups**, not verified identities |
| Unique file hashes | 206 |
| Original train / validation / test | 186 / 4 / 16 images |
| Original cross-split filename groups | 0 |
| Original cross-split exact-file duplicates | 0 |
| Prepared train / validation / test | 148 / 30 / 28 images |
| Prepared train / validation / test groups | 58 / 12 / 12 |
| Prepared cross-split groups / exact files | 0 / 0 |
| Seed | 42 |

The preparation uses filename stems before the Roboflow augmentation suffix and
unions exact duplicates, including renamed files, into one connected group.
Identity leakage remains possible if one holder has differently named photos.
A human-reviewed `path,base_document_id` mapping can consolidate these groups;
this has **not** yet been supplied. Front/back and all derivatives of the same
holder must share a reviewed group. Do not claim identity-level leakage is solved.

## Labels and limitations

| Field | Original annotation count |
| --- | ---: |
| Address | 206 |
| Name | 203 |
| Sex | 201 |
| Face | 200 |
| MyKad Number | 197 |
| States | 195 |
| Religion | 132 |
| Face Watermark | 4 |

Four watermark annotations are insufficient to evaluate a robust watermark
detector. In the prepared split all four fall in training; validation/test have
zero watermark annotations. The tool reports this honestly rather than moving
related images across splits or inventing examples. Overall mAP must not be
presented as reliable watermark or tampering performance. A visible watermark
field is not proof of an authentic security feature. More reviewed, diverse
source groups are needed, including front/back and mobile capture conditions.

## Code changes

- `services/ai/app/training/prepare_mykad_dataset.py`: image/label/class/coordinate
  validation; aggregate audit; deterministic grouped splits; optional reviewed
  holder mapping; opaque output filenames; private CLI output; no-overwrite copy.
- `services/ai/app/training/train_mykad_fields.py`: separate field training command
  and `models/mykad_fields_yolo.pt` artifact. It is **not** wired into production OCR.
- `services/ai/app/training/train_document_yolo.py`: validates whole-document class
  semantics before downloading/training, rejecting this field dataset; training
  previews/runs now stay under ignored `.data/training_runs/`.
- `services/ai/tests/test_mykad_dataset.py`: synthetic preparation, grouping,
  duplicate protection, coordinate/label validation, privacy/overwrite behavior,
  reviewed mapping and separate-artifact regression tests.
- `services/ai/datasets/README.md`: preparation/training/annotation workflow.

No new dependency, server configuration, API contract or Flutter screen changed.
The existing scanner uses manual fallback until a compatible whole-card model is
trained. Fields cannot silently overwrite the whole-card artifact via its trainer.

## Commands

From `services/ai`:

```powershell
# Read-only audit of the supplied export:
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_dataset .data/datasets/mykad/c4rd2.v1i.yolov8

# Already executed; refuses another write to this existing directory:
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_dataset .data/datasets/mykad/c4rd2.v1i.yolov8 --output .data/datasets/mykad_fields_prepared_v1

# OPTIONAL, only after provenance/identity grouping review; not executed:
.\.venv\Scripts\python.exe -m app.training.train_mykad_fields .data/datasets/mykad_fields_prepared_v1/data.yaml --epochs 80

# Regression checks:
.\.venv\Scripts\python.exe -m pytest -q
```

Training may require downloading initial pretrained YOLO weights. The training
summary reports validation metrics; held-out test evaluation is a separate step,
and the absent watermark test support must be disclosed. No training ran here.

## What remains

1. Review dataset licence/consent and confirm grouping by holder, not filenames.
2. Acquire more independent groups for rare fields and diverse mobile conditions.
3. Create a **separate human-reviewed whole-card bounding-box dataset**. Label the
   actual visible card rectangle; do not use text-box unions or guessed full-image
   boxes. Add front/back and background/partial-card cases, grouped by holder.
4. Train/evaluate field and whole-card detectors separately. Field-assisted OCR
   integration remains a later task and must include fallback/evaluation.
5. Tamper/risk training still requires independently reviewed normal/risky images
   and derivative-safe grouping. This dataset supplies no such ground truth.

## Validation results

The full AI test suite passed: **65 tests**, with two existing third-party
deprecation warnings. The 12 new dataset/training-guard tests use synthetic
images and mocked training only; they do not claim trained MyKad accuracy.
The supplied labels passed coordinate/class checks and images decoded
successfully. Prepared-copy re-audit confirmed no provided-group or exact-byte
overlap across splits. `git diff --check` passed. No Flutter/API code changed.

Commit message:

```text
feat(ai): prepare grouped MyKad field datasets and guard scanner training
```
