# KYC dataset provenance

Only manifests are tracked. Raw datasets belong under
`services/ai/.data/datasets/`, which is ignored by the repository-wide
`**/.data/` rule. Do not commit real MyKad images or other personal identity
documents.

The manifests intentionally report zero selected records until the applicable
licence/access conditions have been reviewed and data has actually been
downloaded. Update counts, subsets, labels, provenance, and grouped split counts
before training. Malaysian validation must use synthetic MyKad-like samples or
explicitly consented, securely handled samples.

For `train_document_risk.py`, create a local CSV containing `path`, `label`, and
`base_document_id`. All originals and manipulated derivatives of one document
must share the same `base_document_id`.

## Local MyKad field dataset

The user-supplied `c4rd2.v1i.yolov8` export contains field boxes, not whole-card
boxes or tampering labels. Prepare a separate private copy without modifying it:

```powershell
cd C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_dataset .data/datasets/mykad/c4rd2.v1i.yolov8
.\.venv\Scripts\python.exe -m app.training.prepare_mykad_dataset .data/datasets/mykad/c4rd2.v1i.yolov8 --output .data/datasets/mykad_fields_prepared_v1
```

Preparation refuses to overwrite an existing output. Use a new versioned folder
for another run. The CLI only writes under ignored `.data/datasets/`. Local
`audit.json`, `groups.csv`, images and labels stay private. Dataset paths in the
original YAML are not trusted; preparation scans its split folders and exports
a YAML with an explicit absolute dataset root.

The default grouping combines the original filename before `.rf.<augmentation>`
with exact-byte duplicate detection. It cannot prove that differently named
documents belong to different identities. To merge front/back, different photos
and derivatives of the same identity, prepare a reviewed private CSV containing
`path,base_document_id` with **every** source-relative image path, then pass
`--groups-csv .data/datasets/mykad/reviewed_groups.csv` and a new output directory.
Never use raw IC numbers as group identifiers. Splits are deterministic and
approximately 70/15/15 **by group**, not by image. Inspect per-class support;
group integrity takes precedence over making every rare class appear in a split.

After licence/consent and grouping review, field research training is:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_mykad_fields .data/datasets/mykad_fields_prepared_v1/data.yaml --epochs 80
```

This exports `models/mykad_fields_yolo.pt`, **not** `document_yolo.pt`. It is not
automatically wired into OCR or live verification. The live scanner continues to
use only its whole-document model/manual fallback. Scanner training now rejects
field-class datasets before any weight download. Training runs (which may contain
identity-image previews) are private under `.data/training_runs/`.

For the scanner, a human must label the complete visible card rectangle on each
image in a **separate** dataset (e.g. `mykad_front` and `mykad_back` classes).
Do not substitute the union of text/face boxes or assume the entire image is the
card. Add reviewed background/partial-card and mobile-condition examples, and
keep holder/derivative groups together. Back-side coverage has not been verified
in the supplied field dataset. Authenticity/tamper detection still needs its own
reviewed `normal/risky` manifest; neither field nor card detection proves validity.

See `../../../docs/MYKAD_DATASET_PREPARATION_RESULT.md` for measured audit results
and remaining work. No detector training or accuracy claim is made during preparation.
