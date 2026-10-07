# MyKad whole-card dataset preparation

Date: 2026-10-07. Scope: local audit, filtering, polygon-to-box conversion and
private grouped copy. **No detector training or accuracy claim was made.**

## Sources and output

Original, preserved without edits:
`services/ai/.data/datasets/mykad_whole_card_raw/KYC DOCUMENT DETECTION.v5i.yolov8/`.

Prepared copy: `services/ai/.data/datasets/mykad_whole_card_prepared_v1/`.
Both are Git-ignored. The prepared folder contains `data.yaml`, `groups.csv`,
aggregate `audit.json`, and `train/`, `val/`, `test/` image/label folders.
Images are copied without image transformations; output names are opaque hashes,
not anonymization. Original image filenames and identity data are not included
in this report. Private images must not be committed or publicly shared.

The downloaded YAML declares Roboflow project `kyc-document-detection`, version
5, licence CC BY 4.0. Source:
[KYC DOCUMENT DETECTION v5](https://universe.roboflow.com/name-address-mykad-number-gender/kyc-document-detection/dataset/5).
This is publisher-declared provenance, not verification of holder consent,
authenticity, or rights to each identity image. Review permitted use and preserve
attribution before training/deployment.

## Filtering and annotation format

Exact normalized class mapping:

| Source ID/name | Prepared ID/name |
| --- | --- |
| 7 / Mykad | 0 / mykad_front |
| 4 / MyKad_Rear | 1 / mykad_back |
| MyPR, MyTentera, My Khas, Passport and their rear classes | Excluded |

Do not assume this export contains detection boxes simply because its folder
ends in `.yolov8`. All **582 selected annotations are segmentation polygons**.
The preparation tool validates finite, normalized, nondegenerate outlines and
converts their actual coordinate extrema to enclosing axis-aligned detection
boxes. It does not invent full-image boxes or merge field boxes into a card box.
Whole-card semantic correctness has **not** been visually verified.

The generic field-preparation reader remains strict box-only by default;
polygon conversion is opt-in for this dedicated whole-card preparation.
Invalid target annotations fail before output. One out-of-bounds polygon on an
excluded `My Tentera Back` image is recorded in the source audit; it is neither
clipped nor included. Unknown class IDs still fail.

Mixed MyKad/other-document images and unreviewed empty labels are excluded,
not turned into background negatives. This particular export has no such images.
One selected image contains both MyKad front/back annotations; both are retained.
This does not establish that the depicted cards belong to the same holder.

## Measured audit

- Source: **2,648 images**, 490 filename/exact-byte proxy groups, 2,400 unique
  image hashes; original folders contain 2,553 train and 95 test images.
- Original source has 20 proxy groups spanning splits (all document classes).
- Selected: **581 images**, **227 proxy groups**, **521 unique image hashes**.
- Excluded: **2,067 other-document images**.
- Front annotations: **305**; back annotations: **277**.
- All selected polygons converted: **582**; no selected box-format annotations.

| Prepared split | Images | Proxy groups | Front-bearing images | Back-bearing images |
| --- | ---: | ---: | ---: | ---: |
| Train | 402 | 159 | 216 | 187 |
| Validation | 94 | 34 | 36 | 58 |
| Test | 85 | 34 | 53 | 32 |

The train split contains the one both-side image, so its side counts sum to 403
while its image count is 402. Split ratios are approximately 70/15/15 by group,
not by image. Seed: 42. A strict re-audit of the written copy confirms **zero
cross-split proxy groups and zero cross-split exact image duplicates**. Both
classes are represented in every split.

## Reproduction and next step

From `services/ai`:

```powershell
# Read-only audit:
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_whole_card `
  ".data/datasets/mykad_whole_card_raw/KYC DOCUMENT DETECTION.v5i.yolov8" --dry-run

# Already run for v1; use a new output version to repeat:
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_whole_card `
  ".data/datasets/mykad_whole_card_raw/KYC DOCUMENT DETECTION.v5i.yolov8" `
  --output .data/datasets/mykad_whole_card_prepared_v1

# Next, ONLY after source permissions, grouping and annotation review:
.\.venv\Scripts\python.exe -m app.training.train_document_yolo `
  .data/datasets/mykad_whole_card_prepared_v1/data.yaml --epochs 80
```

Preparation refuses existing outputs and source/output nesting. Optional
`--groups-csv` accepts a complete private `path,base_document_id` mapping; keep
all photos/derivatives/front-back pairs of a known holder together. A supplied
CSV is an assertion, not proof of holder independence.

Training would export `models/document_yolo.pt`, separate from the existing
field detector and risk classifier. **That scanner artifact is still missing**
after this preparation, so `document detector unavailable` is expected until
training succeeds and the AI process is restarted to load it. Review validation
metrics and separately evaluate the held-out test split/mobile capture slices.
The trainer refuses existing model/metrics outputs rather than silently replacing
them. No automatic training, restart or runtime configuration change was performed.

## Validation and remaining limitations

`python -m pytest tests -q`: **137 passed**, two dependency deprecation warnings.
New tests use synthetic images only and cover exact class mapping, polygon
conversion/validation, strict field-reader behavior, exclusion of unrelated,
mixed and empty examples, invalid excluded vs target annotations, preserved
originals, overwrite/nesting guards, both-side support and split leakage checks.

Filename grouping strips Roboflow augmentation suffixes and unites exact-byte
duplicates. Differently named photos of one holder can still cross splits;
**identity-level grouping is not verified**. The effective independent sample
size is not the augmented image count. Visual box review, capture diversity,
reviewed background/wrong-document/partial-card negatives and unseen-phone
testing remain necessary. Excluding MyPR/MyTentera from training does not prove
the detector will reject them at inference. Rotated polygon enclosing boxes are
looser than corners and do not provide perspective rectification. Localization
does not authenticate a MyKad, prove OCR agreement, or identify real tampering;
administrator review remains required.
