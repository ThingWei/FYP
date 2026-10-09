# Open Images item-detector dataset preparation

## Purpose and status

`services/ai/app/training/prepare_open_images.py` selects a bounded Open Images
subset, produces downloader-compatible image lists, downloads selected photos
only with explicit permission acknowledgement, and converts bounding boxes to
Ultralytics YOLO format. The existing user-downloaded `downloader.py` is unchanged.
The helper uses Python's standard HTTP library and existing Pillow/PyYAML packages;
it does not require an AWS account, credentials, or another boto3 installation.

This work prepares data, **not a trained model**. The initial implementation
checked the small public class list: 601 boxable classes, with 22 explicit
RentHub mappings. After the user's download, the MPO/coverage fix recovered the
existing local dataset offline: 1,803 usable images, no failures or exact-content
duplicates, and a generated `data.yaml`. All 1,802 previously accepted images
retained their original hashes. No external downloads or training were run during
this recovery.

Open Images supports object-type detection. It does not establish authenticity,
ownership, condition, exact product model, or normal/risky image labels. The
item-specific EfficientNet risk classifier needs a separate reviewed manifest;
do not reuse MyKad datasets or label every Open Images photo as genuine/normal.

## Run from PowerShell

Use the same virtual-environment Python consistently:

```powershell
cd C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m app.training.prepare_open_images --list-classes
```

### 1. Download metadata and preview selection

**Large download:** the official training bounding-box CSV alone is approximately
2.26 GB (2,258,447,590 bytes observed). Validation/test metadata adds more, and
photos require additional space. A small photo quota does not shrink that CSV.
The first download cannot resume partial metadata; completed cached files are
reused. Allow enough disk space and a stable connection. No large download occurs
without `--download-metadata`.

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_open_images --download-metadata
```

This scans the annotations twice per split using bounded-memory sampling. It
writes `selection.json` and `image_lists/*.txt`, prints actual class counts, and
does not download photos or create a trainable `data.yaml`.

The default selection targets are 100 train, 20 validation, and 20 test image IDs
per class across 16 classes: **at most 2,240 photos**, not exactly that number.
Overlapping classes and rejected images can reduce the total. Individual class
counts may exceed a quota when photos contain multiple selected classes.

For a smaller photo trial, replace the previous command with:

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_open_images `
  --download-metadata --output .data/datasets/open_images_items_small_v1 `
  --train-per-class 25 --val-per-class 5 --test-per-class 5
```

The metadata download is still large. To use metadata downloaded elsewhere, put
the official class and bounding-box CSVs in a directory with these names and pass
`--metadata-dir <directory>`:

```text
classes.csv
train-boxes.csv
validation-boxes.csv
test-boxes.csv
```

### 2. Download the selected photos and export YOLO labels

After checking source permission/licences and preview counts:

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_open_images `
  --download-images --acknowledge-source-permission
```

Use exactly the same classes, quotas, seed, metadata and output directory as the
preview. For the smaller example, repeat its `--output`, `--train-per-class`,
`--val-per-class` and `--test-per-class` arguments in this command. Different
selections cannot overwrite a non-empty dataset directory; use a new directory.

Already verified JPEG/MPO files resume locally, including complete `.incoming`
files left by an earlier rejection. Both structural verification and primary-frame
pixel decoding must pass. MPO bytes are preserved: no rotation, resizing or
recompression changes the bounding-box coordinate space. The installed YOLO
loader supports MPO; the recovered primary frame also decoded with OpenCV.
Unsupported containers and corrupt/truncated images remain errors. Downloads and
cached images have byte/pixel caps; downloads use retries and atomic replacement.

Failed downloads, duplicate content, missing training/validation classes, or an
entirely empty split prevent export. A class absent only from the test split does
**not** block training, but is explicitly recorded as **not evaluated**. No images
are moved between splits, no test labels are fabricated, and the class remains in
the training vocabulary. Inspect
`preparation_result.json`; `trainingReady: true` means preparation checks passed,
not that dataset quality or model accuracy is proven. Corrupt cached photos are
reported and not automatically deleted. If rechecking invalidates an existing
export, its YAML is retained as `data.previous.yaml`, not left trainable.

Coverage reporting includes `missingSplitClasses`, `blockingMissingSplitClasses`,
`unevaluatedTestClasses`, `testClassCoverage`, `testClassCoverageComplete`, and
`testEvaluationPerformed`. Even classes with test examples have no measured
performance until an actual held-out evaluation runs.

For the current downloaded dataset, the official test annotation CSV contains no
hammer rows. Preparation therefore reports `trainingReady: true`,
`unevaluatedTestClasses: ["hammer"]`, `testClassCoverageComplete: false`, and
`testEvaluationPerformed: false`. Do not claim hammer test accuracy. A later
evaluation needs a separately reviewed, independent hammer test set. Several
other tools also have very few evaluation examples:

| Class | Train images | Validation images | Test images |
| --- | --- | --- | --- |
| hammer | 99 | 1 | 0 |
| drill | 95 | 1 | 10 |
| screwdriver | 42 | 2 | 1 |
| wrench | 54 | 1 | 1 |

These counts establish presence, not sufficient evaluation quality. Very small
validation/test samples cannot support strong generalization or accuracy claims.

### 3. Train separately

Only after `trainingReady: true` and a visual annotation/licence review:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_yolo `
  .data/datasets/open_images_items_v1/data.yaml --epochs 60
```

Use the smaller output path if selected. The trainer rejects marked Open Images
preparations without a successful preparation report. It starts from
`yolov8n.pt`, saves training runs, and exports the best checkpoint to
`models/item_yolo.pt`. This replaces an existing item detector when training
finishes; keep a copy first if you need the previous model. Training time depends
on hardware. Review held-out test performance before claiming accuracy, then
restart the AI service to load the new artifact.

## Classes and normalization

The default classes are Camera, Headphones, Laptop, Mobile phone, Microphone,
Drill (Tool), Hammer, Screwdriver, Wrench, Car, Motorcycle, Bicycle, Book, Chair,
Table and Tent. Additional supported selections are Tennis racket, Dumbbell,
Dress, Suit, Clothing and Tablet computer.

Class selection is exact and case-insensitive, not generic text search. Pass
`--classes "Camera" "Mobile phone" "Car"` to restrict the dataset. This also
restricts the trained detector; it does not cover every RentHub category.

| Open Images name | Runtime label |
| --- | --- |
| Mobile phone | cell phone |
| Drill (Tool) | drill |
| Tablet computer | tablet |
| Other supported names | lowercase name |

Every configured target label is checked against the runtime item ontology.
Cars, motorcycles, bicycles, tools, electronics, books and event objects can
therefore provide category evidence without claiming exact brand/model identity.
Gaming equipment and other unsupported identities remain manual-review cases.

## Output, provenance and limitations

```text
.data/datasets/open_images_items_v1/
  selection.json
  image_lists/{train,validation,test}.txt
  images/{train,val,test}/*.jpg
  labels/{train,val,test}/*.txt
  preparation_result.json
  provenance.json
  data.yaml                         # only after successful preparation
```

Dataset/cache files live under ignored `.data/` and must not be committed.
Source image IDs, public URLs, split and downloaded-content hashes are recorded;
individual photographer attribution is not automatically collected.

- Original official splits are retained. Selected IDs overlapping splits are
  rejected, and duplicate downloaded content blocks export. This does not prove
  independence of near-duplicates, photographers or underlying physical items.
- All selected-class boxes are collected, including non-contiguous CSV rows.
  Invalid coordinates, unverified boxes, grouped instances and depictions are
  not converted into misleading individual-object labels. An image containing
  such a selected-class instance is excluded entirely, without automatic
  backfilling. A class can therefore be underrepresented or absent.
- Non-selected classes are outside this detector's scope. Annotation omissions
  and hierarchical classes still require visual review; automated conversion
  does not establish label completeness or an adequate training sample size.
- The source publishes annotation and photo licensing information separately.
  Permission acknowledgement is not licence verification. Check image-specific
  terms and attribution before reuse or publication. See the official
  [downloads](https://storage.googleapis.com/openimages/web/download_v7.html) and
  [licensing information](https://storage.googleapis.com/openimages/web/factsfigures.html).

## Validation

Offline regression tests cover official/headerless class lists, exact mappings,
coordinate validation, grouped/depicted boxes, non-contiguous annotations,
reproducible bounded sampling, split overlap rejection, preview safety, output
ownership, resume, failed downloads, content duplicates, export contents,
recovery YAML, byte caps, and permission/large-download opt-ins. Additional tests
cover multi-frame MPO acceptance without byte changes, pixel decoding, unsupported
containers, offline incoming recovery, invalid incoming redownloads, absent test
class reporting, required train/validation coverage, and empty-test blocking.

```powershell
.\.venv\Scripts\python.exe -m pytest tests/test_open_images_preparation.py -q
```

Result: 38 passed using artificial CSV/JPEG/MPO fixtures. The public class-list
check also passed. The complete AI suite passed: 267 tests, with two dependency
deprecation warnings. These are software checks, not a trained detector's
accuracy result.
