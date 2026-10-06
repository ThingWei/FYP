# Synthetic document-manipulation risk dataset implementation

## Original implementation and intentionally not done

Implemented an automatic, local research data generator using the already
annotated front/back fields. It creates procedural alterations and their labels,
without manually drawing new boxes or downloading an additional forgery dataset.
No new dependency, network call, upload, production record mutation, OCR or
MyKad/production classifier training was performed. Downloaded originals and trained artifacts
remain untouched. No authenticity assertion is made about those originals.

Generation from downloaded identity images requires explicit
`--acknowledge-source-permission`. The source's consent/usage review is still
unconfirmed, so only a read-only preview and synthetic-fixture tests ran here.
This does not bypass permission review, a small output quality review, or honest
independent evaluation.

## Generation contract

- Supported targets: annotated IC-number, name, address and serial-number fields.
  Existing side-specific labels keep front/back number regions separate from
  serial regions. No OCR values are read, logged or used to manufacture credentials.
- `field_erase`: removes local field texture using its mean colour.
- `field_copy_move`: duplicates a small part of that same field within the field.
- `field_test_patch`: inserts visibly non-credential `TEST` content, not plausible
  names/IC numbers. No other person's real portrait is inserted.
- For each effective change, writes a normal baseline and risky derivative with
  the **same** brightness, blur, compression and research watermark. Poor quality
  alone is not a tamper label; both labels contain capture nuisances.
- `normal`: no controlled local manipulation, apart from shared preprocessing.
  **Not government-confirmed genuine** and not independently verified original.
- `risky`: known procedural alteration. **Not a real-world counterfeit verdict**.
- All outputs have `SYNTHETIC RESEARCH - NOT VALID ID` visible on top/bottom.
  This is not anonymization; underlying identity data may still be present.
- Skips zero-change edits and too-small fields. Output bytes that become identical
  after JPEG processing cannot count as a risky pair. Rejects conflicting labels.

## Private manifest and leakage checks

Output images are private under the Git-ignored `.data/datasets/` directory.
Names are opaque hashes and EXIF is stripped. Raw IC-number strings, real names
and original filenames are absent from console output and generated metadata.
Image content itself is still sensitive and must not be committed or made public.

The CSV records `path,label,base_document_id,split,source_type,side,
manipulation_type,region_class,region_xyxy,variant_id,source_sha256,
image_sha256,capture_profile`. Source type is always `synthetic_manipulation`
for **both** baseline and altered rows, preventing the baseline from being
misreported as a real authenticated marketplace document.

Uses the source `groups.csv` automatically when present, or existing filename/
exact-byte groups otherwise. Selects one representative per proxy source group
to avoid counting source augmentations as independent documents. Shared holder
IDs supplied in a reviewed mapping can consolidate front/back and multiple
photos; no matching identities are inferred from unrelated datasets. Splits
groups before generating pairs, then checks actual generated hashes and groups
for cross-split leakage. At least 20 groups/60 generated images and both classes
in each split are required before a training manifest is published.

Identity-level grouping is **not verified**. Differently named captures from one
holder may still be incorrectly separated. More derivatives cannot fix this.
Generation can leave partial images for inspection after a validation error;
no ready manifest is published on failure, and no recursive cleanup/deletion runs.

## Trainer changes

`train_document_risk.py` remains compatible with legacy `path,label,
base_document_id` CSVs. It additionally honors the generator's declared splits
instead of silently resplitting them, verifies image hashes, rejects duplicate
paths, exact-byte leakage and conflicting labels, and retains source/side/edit
provenance for reporting. A new training seed cannot change declared partitions.

Any synthetic rows (including mixed datasets) cause output to use a separate
research artifact: `models/document_risk_synthetic_efficientnet.pt` and
`metrics/document_risk_synthetic_metrics.json`. The existing runtime default
artifact is never overwritten by this synthetic route. Purpose, source counts,
operation counts, side counts, label definitions and limitations are embedded
inside TorchScript and recorded in metrics; reload checks verify this metadata.
Held-out metrics are synthetic evidence, not MyKad authentication performance.
No production KYC activation or runtime deployment change is included.

## Measured preview of the user's existing combined data

| Preview check | Result |
| --- | ---: |
| Source image files | 470 |
| Available proxy source groups | 192 |
| Groups with supported field boxes | 192 |
| Planned train / validation / test groups | 134 / 29 / 29 |
| Maximum possible paired output images | 1,152 |
| Actually generated from downloaded images | **0** |
| Trained model / accuracy results | **None** |

Actual counts after generation may be lower because ineffective edits are
skipped. Preview eligibility does not prove permissions, genuine sources,
human-reviewed regions, identity-disjoint groups or real-world generalization.

## Commands

From `C:\Users\weith\FYP\services\ai`:

```powershell
# Safe read-only preview, already executed:
.\.venv\Scripts\python.exe -m app.training.generate_document_risk .data/datasets/mykad_front_back_fields_prepared_v1 --dry-run

# ONLY after confirming source permissions; not executed on downloaded images:
.\.venv\Scripts\python.exe -m app.training.generate_document_risk `
  .data/datasets/mykad_front_back_fields_prepared_v1 `
  --output .data/datasets/mykad_synthetic_risk_v1 `
  --acknowledge-source-permission

# After generation, spot-review images and holder grouping, then optional training:
.\.venv\Scripts\python.exe -m app.training.train_document_risk `
  .data/datasets/mykad_synthetic_risk_v1/manifest.csv --epochs 10
```

Generation requires no additional dataset, per-image manual labels, API key or
pretrained download. Training still requires the installed dependencies and may
download ImageNet weights. Existing output directories are never overwritten;
use a new versioned output for another dataset run.

## Follow-up audit and improved training (6 October 2026)

The user subsequently generated the private dataset and trained the original
whole-image classifier. A read-only audit confirmed 1,152 images in 192 proxy
groups, balanced splits (804 / 174 / 174), verified encoded-image hashes and
zero proxy-group/exact-byte leakage. Holder-level independence is still unverified.
The saved TorchScript provenance matched the manifest, and reloaded inference
reproduced the original test metrics exactly:

| Original risk-model test measure | Result |
| --- | ---: |
| Accuracy | 61.49% |
| Precision for risky | 67.24% |
| Recall for risky | 44.83% (39/87) |
| F1 | 0.5379 |
| ROC AUC | 0.6204 |
| Copy-move recall | 27.59% (8/29) |
| Field-erase recall | 55.17% (16/29) |
| TEST-patch recall | 51.72% (15/29) |

Of 576 risky images, 118 annotated target fields become less than eight pixels
high under the original 224-square resize. These are **whole field** sizes; the
actual edit may be smaller. This supports investigating local crops, not claiming
that small size alone explains all failures.

The existing field-detector checkpoint covers eight **front-only** classes, not
the combined 17 classes. It matches the original run's `best.pt`. Its validation
mAP50 is 0.9686, mAP50-95 is 0.5674 and recall is 0.9402; those are not an
independent held-out test or proof of authenticity.

### Implemented improvements

- `--input-mode fields` requires validated image-boundary coordinates on every
  row. Synthetic normal/risky pairs must share coordinates, group, split, side,
  field class, capture profile and image size. Cropping never uses the risk label
  to choose a different region. Bounds/missing metadata fail rather than falling
  back silently to an unrelated full image.
- Crops include configurable context (default 25% of field width/height per edge)
  and use aspect-preserving letterboxing, ImageNet normalization and configurable
  input size. No horizontal flip or random crop can reverse text/remove edits.
- Two default classifier-only warmup epochs, followed by fine-tuning only the
  final two EfficientNet feature blocks. Head LR 0.001, backbone LR 0.00001.
  Frozen blocks remain in evaluation mode and **all backbone BatchNorm statistics
  stay frozen**, including during fine-tuning. `requires_grad=False` alone did not
  prevent their running statistics changing in the earlier trainer.
- Best checkpoint chosen by validation ROC AUC, F1 as tie-breaker; early stopping
  after five unimproved epochs in the post-warmup phase. The test set never chooses
  a checkpoint or threshold. Decision threshold remains 0.5.
- Reloaded **selected** artifact is evaluated, with test side slices and risky
  recall by edit family. Embedded provenance includes complete preprocessing and
  explicitly says annotated field locations are not automatic localization.
- CPU/CUDA selection and batch size controls, visible epoch progress, no-download
  `--dry-run`, versioned `--output-tag` and no-overwrite guards. Explicit
  `--overwrite` is required to replace an existing model or metrics file.
- Field training supports `--require-front-back`, which validates the actual
  prepared YAML, classes, group/hash leakage and front/back image support in
  **each** split before loading YOLO. A tagged combined model preserves the
  existing front-only model. Validation metrics identify their split and classes.

**Annotated-region limitation:** the manifest identifies the edited field. A
field-crop classifier is therefore a research experiment using oracle locations,
not an end-to-end deployed tamper detector. Deployment would need a tested field
localizer to select all eligible fields on both normal/risky inputs without knowing
the label, then a separately validated aggregation/threshold policy. Do not point
the current whole-image runtime at this crop-trained artifact. Its embedded
`runtimeCompatibleWithoutAdapter` is false. No automatic approval is added.

### Run the improved experiments

From `C:\Users\weith\FYP\services\ai`, after permission, grouping and spot review:

```powershell
# Read-only validation; no weights downloaded and no training:
.\.venv\Scripts\python.exe -m app.training.train_document_risk `
  .data/datasets/mykad_synthetic_risk_v1/manifest.csv `
  --input-mode fields --output-tag v2 --dry-run

.\.venv\Scripts\python.exe -m app.training.train_mykad_fields `
  .data/datasets/mykad_front_back_fields_prepared_v1/data.yaml `
  --require-front-back --output-tag front_back --dry-run

# New experiments, preserving the earlier model artifacts:
.\.venv\Scripts\python.exe -m app.training.train_document_risk `
  .data/datasets/mykad_synthetic_risk_v1/manifest.csv `
  --input-mode fields --output-tag v2 --epochs 20 `
  --warmup-epochs 2 --fine-tune-blocks 2 --patience 5

.\.venv\Scripts\python.exe -m app.training.train_mykad_fields `
  .data/datasets/mykad_front_back_fields_prepared_v1/data.yaml `
  --require-front-back --output-tag front_back --epochs 80
```

New outputs:

- `models/document_risk_synthetic_fields_v2_efficientnet.pt`
- `metrics/document_risk_synthetic_fields_v2_metrics.json`
- `models/mykad_fields_front_back_yolo.pt`
- `metrics/mykad_fields_front_back_yolo_metrics.json`

Use a **new** tag (e.g. `v3` / `front_back_v2`) for subsequent runs. The previous
whole-image baseline, front-only detector and user's metrics are untouched.
For an ablation, use `--fine-tune-blocks 0` with a new tag; choose settings on
validation, and avoid repeatedly optimizing against the already inspected test set.
Future real-world claims require a fresh, independent permitted evaluation set.

No new MyKad training was launched in this implementation turn. Toy-model tests
verify the actual warmup/fine-tune phases, frozen BatchNorm statistics, selection
of an earlier validation-best checkpoint, export, slices and preservation of the
baseline. **No improved accuracy is claimed until these experiments are run.**

## Remaining work

Runtime continuation: the user has now trained both new artifacts, and explicitly
requested integration. See `MYKAD_FIELD_RISK_INTEGRATION_RESULT.md` for the current
advisory-only detector-selected crop pipeline and measured results. Earlier
"not integrated" statements above describe the original training-only delivery.

1. Confirm source permission and holder grouping; optionally supply reviewed
   `--groups-csv`. Keep protected application KYC uploads out of training.
2. Spot-review the user's generated samples (`--limit-groups 20` remains supported
   for a new versioned generation run).
3. Train the improved separate research artifact, inspect class/side/manipulation support
   and evaluation, and test transformations not produced by this generator.
4. Obtain an independent permitted MyKad evaluation set before claiming deployment
   readiness. Simple generated artefacts can be easier than realistic tampering.
5. Any FYP runtime integration must explicitly disclose synthetic provenance and
   advisory-only risk. Administrator approval remains the final decision.
6. Whole-card scanner annotations/training remain a separate outstanding task.

## Executed validation

- Follow-up improvement validation: **95 AI tests passed** (42 focused
  generation/training/dataset tests), with the same two third-party warnings.
  Real-data field-risk dry-run validated all 1,152 manifest rows and paired crops;
  combined-detector dry-run validated 470 images / 17 classes with front/back
  coverage 145/180 train, 35/36 validation and 26/48 test. Neither dry-run loads
  pretrained weights or trains. `git diff --check` passed.
- **81 AI tests passed**, including ten new generation/trainer regression tests;
  two existing third-party deprecation warnings remain.
- Synthetic-only fixtures exercise deterministic generation, exact-byte/source
  grouping, balanced capture controls, no-op rejection, source preservation,
  permission/no-overwrite guards, changed-image hashes, contradictory labels,
  declared splits and provenance persistence.
- An offline one-epoch **tiny toy model**, not EfficientNet or a MyKad accuracy
  experiment, exercises the trainer CLI, held-out evaluation and fresh artifact
  reload. It verifies the synthetic model cannot overwrite the default runtime
  artifact. Its temporary metrics are not reported as FYP model results.
- Real combined-source **dry-run** succeeded: 192 eligible groups and zero images
  generated. Source input/data/model artifacts were not modified.
- `git diff --check` passed. No Flutter/API changes required.

Commit message:

```text
feat(ai): generate provenance-labelled synthetic document risk datasets
```

Follow-up commit message:

```text
feat(ai): improve MyKad risk training and front-back detector workflow

- add paired field crops with aspect-preserving preprocessing and provenance
- add low-LR tail fine-tuning with frozen BatchNorm statistics
- select validation-best checkpoints and report side/edit-family test slices
- validate combined field datasets and preserve earlier models with tagged outputs
- add dry-run/no-overwrite guards, regression tests and research limitations
```
