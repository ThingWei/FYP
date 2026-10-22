# CASIA and AutoSplice item-risk preparation

Prepared 22 October 2026. This imports **metadata only**, not training or deployment.
Usage review remains pending; downloading public data is not treated as a permission
acknowledgement. No source photos, masks, models, KYC data or live records were modified.

## Delivered

- Added `app.training.prepare_public_item_risk`, using existing Pillow and Python
  standard-library dependencies. No network, model downloads, training or image copies.
- CASIA `Au` maps to `normal`, `Tp` to `risky`. AutoSplice `Authentic` maps to
  `normal`, `Forged_JPEG75` to `risky`; matching JPEG75 was selected because the
  source README documents its originals at that quality. This does not eliminate
  all codec/source confounding, particularly between CASIA file formats.
- Excluded CASIA `Gt`, AutoSplice `Mask`/`Caption` and JPEG90/100 alternatives from
  photo rows. Masks remain annotations, not original/risky image examples.
- Full decode checks, raw SHA-256 and canonical RGB-content hashes detect unreadable
  files, exact binary duplicates, exact decoded duplicates and conflicting labels.
  Invalid/ambiguous images are quarantined as metadata, not deleted or repaired.
- CASIA donor **and** recipient filename IDs join originals and their edits into
  transitive connected components. AutoSplice originals, numbered edits and known
  variants share their original ID. Raw/decoded duplicates also join components,
  including across datasets. Missing originals retain virtual reference nodes.
- Size-aware deterministic seed-42 splitting targets 70/15/15 by dataset and label,
  without breaking source families. Ratios are approximate; a large component is
  never split merely to achieve a prettier ratio.
- Manifest entries keep dataset identity, source path/encoding, relationship-derived
  group, dimensions and checksums. The trainer now checks optional source checksums
  and reports classification metrics separately by dataset as well as source type.

Both benchmarks use `source_type=synthetic_manipulation`: controlled edits of source
photos, **not independently reviewed real marketplace incidents**. CASIA's filename
operation tag is retained as an unverified benchmark label; AutoSplice's generative
origin is explicit. No content is assigned an invented RentHub product subcategory.

## Actual local import

Read existing extracted folders in Downloads directly:

- `C:\Users\weith\Downloads\CASIA2.0_revised_corrected\casia`
- `C:\Users\weith\Downloads\AutoSplice\AutoSplice`

New ignored output: `services/ai/.data/datasets/public_item_risk_casia_autosplice_v1/`.
Contains `manifest.csv`, `preparation_result.json`, `duplicates.json`,
`quarantine.json` and `README.md`. Photos remain at their original paths; keep the
extracted directories in place. Deleting the ZIP archives does not affect these
references, but deleting/moving the extracted photos does.

| Check | Actual result |
|---|---:|
| CASIA original / edited files discovered | 7,491 / 5,123 |
| AutoSplice original / JPEG75 edited files discovered | 2,273 / 3,621 |
| Candidate photos / successful full decodes | 18,508 / 18,508 |
| Exact decoded duplicates omitted | 196 |
| Quarantined images | 0 |
| Selected manifest photos | 18,312 |
| Connected source components | 8,608 |
| Largest connected component | 3,898 photos |
| Source IDs without a corresponding original file | 10 |
| Group / raw-hash / decoded-hash cross-split overlaps | 0 / 0 / 0 |

| Dataset | Train normal/risky | Validation normal/risky | Test normal/risky |
|---|---:|---:|---:|
| CASIA | 5,107 / 3,650 | 1,094 / 737 | 1,094 / 736 |
| AutoSplice | 1,591 / 2,535 | 341 / 543 | 341 / 543 |
| Total | 6,698 / 6,185 | 1,435 / 1,280 | 1,435 / 1,279 |

Fingerprint: `2c9e2d9729a43d0c8c1f9686b56b7279304e8d846b38b395b31d3365d73f0345`.
It identifies this selected content/group/split plan, not verified authorship or rights.

## Permission and training gates

The manifest deliberately has `usage_review=pending` and the report has
`trainingReady=false`. The loader refuses it even if a trainer permission flag is
accidentally supplied. Legacy manifests without this new optional column retain
compatibility. No permission was acknowledged on the user's behalf.

After reviewing the dataset terms, attribution and source relationships, explicitly
re-import into a **new** directory with acknowledgement; existing review files
are never overwritten. From `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_public_item_risk `
  --casia 'C:\Users\weith\Downloads\CASIA2.0_revised_corrected\casia' `
  --autosplice 'C:\Users\weith\Downloads\AutoSplice\AutoSplice' `
  --output .data/datasets/public_item_risk_reviewed_v2 `
  --seed 42 --workers 2 --acknowledge-source-permission
```

The command above is guidance, **not executed approval**. Omitting `--output`
performs a read-only audit. Output is confined to a new directory under `.data`;
imports refuse existing output, unexpected nested layouts and out-of-root links.
Inspection is bounded to 30,000 candidates, 64 MiB/file, 32 million pixels/image,
single-frame photos and at most four workers (default two).

After that review, a separate explicit candidate-training run is possible:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_image_risk `
  .data/datasets/public_item_risk_reviewed_v2/manifest.csv `
  --output .data/candidates/item-risk-public-round1 `
  --epochs 8 --seed 42 --acknowledge-source-permission
```

This was not run. Initialization must already be cached, unless a download is
separately authorized with `--allow-download`. Training writes only a new candidate;
deployment is a later intentional action. The manifest verifies unchanged source
bytes before fitting; moved, missing or altered sources stop clearly.

## Limits and verification

- Zero exact/link-based leakage does not prove near-duplicate or physical-item
  independence. CASIA links can be incorrect/incomplete; ten unresolved original
  IDs and the large component need review. No missing originals were invented.
- These are benchmark/news photos, not a reviewed sample across all 22 RentHub
  subcategories. Their heldout metrics would measure this benchmark experiment,
  not external marketplace performance, authenticity, ownership or condition.
- JPEG variants are deliberately not counted as independent training cases.
  Photographic source/encoding bias remains possible and needs separate evaluation.
- Real listing-photo evaluation and administrator review remain necessary. A low
  risk score must not mean genuine or automatically approve a listing.
- Focused importer/manifest/trainer suites: **30 passed**. Fixtures test transitive
  source grouping, cross-dataset decoded duplicates, missing originals, unknown
  names, corruption, conflicting labels, deterministic splits, excluded masks,
  permission blocking, source preservation/checksum changes and existing-output guards.
- Full AI suite: **508 passed**. Four non-failing warnings remain: two existing
  third-party deprecations and two expected empty-feature warnings from the unrelated
  controlled sparse-pricing fixture. All deployed model/metrics SHA-256 hashes are
  unchanged before/after the run. `git diff --check` passes and the manifest is
  confirmed Git-ignored. No dataset-dependent model training was executed.
- No Flutter/API/public contract change; their builds/tests are not applicable.

## Commit message

```text
feat(ai): prepare grouped CASIA and AutoSplice risk manifests

- import benchmark labels without copying images or starting training
- keep CASIA donor-recipient families and AutoSplice derivatives in one split
- decode and deduplicate photos with raw and canonical RGB checksums
- quarantine unreadable, unknown and conflicting-label inputs
- block pending usage reviews and detect changed manifest source files
- retain benchmark provenance and report future metrics separately by dataset
- document actual import counts, split integrity and remaining review requirements
```
