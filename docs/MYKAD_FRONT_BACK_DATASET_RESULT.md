# MyKad front/back field dataset organization

## Delivered

Organized the rear download and a combined front/back field dataset without
moving, deleting or modifying any originals. Existing front-only preparation,
trained model artifacts and user-edited training metrics remain untouched. No
training, OCR inference, identity extraction or upload ran during organization.

All dataset files stay under Git-ignored `services/ai/.data/datasets/`:

```text
mykad/c4rd2.v1i.yolov8/                      original front export
mykad_back/MYKAD REAR.v3i.yolov8/             original rear export
mykad_fields_prepared_v1/                    earlier front-only preparation
mykad_back_fields_prepared_v1/               new rear-only preparation
mykad_front_back_fields_prepared_v1/         new combined preparation
  data.yaml
  audit.json
  groups.csv
  train/images/ and train/labels/
  val/images/ and val/labels/
  test/images/ and test/labels/
```

## Actual audit results

| Dataset | Images | Filename/byte proxy groups | Train | Validation | Test |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original front | 206 | 82 | 186 | 4 | 16 |
| Original rear | 264 | 110 | 239 | 0 | 25 |
| Prepared rear-only | 264 | 110 | 195 | 41 | 28 |
| Prepared combined | 470 | 192 | 325 | 71 | 74 |

Combined split groups: 134 / 29 / 29; seed 42. By side:

| Side | Train | Validation | Test |
| --- | ---: | ---: | ---: |
| Front | 145 | 35 | 26 |
| Back | 180 | 36 | 48 |

Rear has **240 unique file hashes**, with 24 duplicate files retained and grouped
within their split. Combined has **446 unique hashes**, not 470 independently
captured documents. Duplicate removal was not performed, avoiding arbitrary
choices between potentially different annotations. Training/evaluation must
disclose repeated files and source-group support.

Both source audits passed image decode, label existence, YOLO class/coordinate
and image-boundary checks. Original exports showed zero filename-group and
exact-byte cross-split overlaps. Combined output was re-read with its exported
group manifest and confirmed **zero group or exact-file cross-split overlap**.
This does not detect visually near-identical captures under different names.

## Class mapping

Class IDs in the combined YAML are sorted and stable for this class set:

| Combined ID | Canonical field | Source class |
| --- | --- | --- |
| 0 | back_chip_logo | Chip logo |
| 1 | back_coat_of_arm | Coat of Arm |
| 2 | back_identity_number | MyKADNumber |
| 3 | back_king_crown | King Crown |
| 4 | back_klcc_tower | KLCC Tower |
| 5 | back_pengarah_pendaftaran | Pengarah Pendaftaran |
| 6 | back_serial_number | Serial Number |
| 7 | back_signature | SIgnature |
| 8 | back_tng_logo | Tng Logo |
| 9 | front_address | Address |
| 10 | front_face | Face |
| 11 | front_face_watermark | Face Watermark |
| 12 | front_identity_number | MyKad Number |
| 13 | front_name | Name |
| 14 | front_religion | Religion |
| 15 | front_sex | Sex |
| 16 | front_states | States |

Front and rear identity fields deliberately have separate classes; the rear
serial field must never be interpreted as the holder's IC number. Source labels
are remapped while their coordinates are preserved. No inferred regions or
authenticity labels were added. Side-specific names also avoid treating an
unannotated shared field on one side as a negative example for the other side.

## Grouping and permissions

The default source filename groups are namespaced by side. It would be unsafe
to assume that `image001` from two unrelated downloads represents one holder.
The downloaded front/rear images are **not known matching pairs**. To prevent
identity-level leakage, review source-relative `path,base_document_id` CSVs for
each export and pass both maps with common synthetic group identifiers:
`--front-groups-csv ... --back-groups-csv ...` using a new output version.
Do not put raw IC numbers in group identifiers. An input CSV is an assertion,
not proof that a human verified grouping; the tool never reports verified
identity-level ground truth. Pairing must not be fabricated through filenames.

The export YAML declares CC BY 4.0; consent, provenance and permitted usage are
still human review tasks. Being public is not proof of permission to process
every depicted identity. Only aggregate counts/class names appear in this report.
Images, local paths, raw holder data and manifests are not committed or uploaded.

## Remaining limitations

- All nine rear classes appear in each prepared rear-only split. The combined
  validation/test still have **zero front_face_watermark annotations**; only four
  such annotations exist, all in training. No reliable watermark accuracy claim.
- These are field annotations, **not whole-card boxes or normal/risky labels**.
  Whole-card scanner and tamper model still need separately reviewed datasets.
- No trained field detector was changed or integrated with EasyOCR. IC matching
  continues using the existing OCR pipeline until separately implemented/tested.
- A field detector identifies locations, not text values or document authenticity.
- New combined training must be followed by held-out evaluation per side/class.

## Reproduction and training

From `C:\Users\weith\FYP\services\ai` (use a new output directory for another run):

```powershell
.\.venv\Scripts\python.exe -m app.training.organize_mykad_fields `
  --front .data/datasets/mykad/c4rd2.v1i.yolov8 `
  --back ".data/datasets/mykad_back/MYKAD REAR.v3i.yolov8" `
  --output .data/datasets/mykad_front_back_fields_prepared_v1

# OPTIONAL: after permissions and holder-group review; not executed here.
# Validates actual front/back coverage and preserves the front-only model.
.\.venv\Scripts\python.exe -m app.training.train_mykad_fields `
  .data/datasets/mykad_front_back_fields_prepared_v1/data.yaml `
  --require-front-back --output-tag front_back --epochs 80
```

The follow-up training improvements export `models/mykad_fields_front_back_yolo.pt`
and `metrics/mykad_fields_front_back_yolo_metrics.json`. Add `--dry-run` to validate
class/side support, group/hash leakage and the self-contained prepared YAML without
loading weights. Existing outputs are protected unless `--overwrite` is explicit;
prefer a new output tag. Neither the scanner nor EasyOCR is automatically changed.

## Validation

Synthetic regression tests cover numeric class remapping, IC versus serial
separation, preservation of original coordinates/files, source-name collisions,
common supplied holder groups, split leakage, wrong-side exact duplicates,
normalization collisions and safe no-overwrite behavior. No MyKad model accuracy
is claimed by these tests. Dataset CLI output and generated reports are aggregate
only; raw identity files remain ignored by Git.

Executed results: **71 AI tests passed**, including 18 dataset/preparation tests,
with two existing third-party deprecation warnings. `git diff --check` passed;
`git check-ignore` confirmed the generated YAML, report and group manifest are
ignored. No API/Flutter changes required. Existing pricing/recommendation metrics,
the user's front-field training metrics and downloaded pretrained weight file
were already changed/untracked before this task and were not modified here.

Commit message:

```text
feat(ai): organize MyKad front and rear fields with safe class remapping
```
