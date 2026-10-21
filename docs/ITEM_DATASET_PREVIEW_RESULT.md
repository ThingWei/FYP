# Item-risk dataset preview and recognition review preparation

Prepared: 21 October 2026. User selected **previews only; permission pending**.

## What is prepared

The private review pack is at:

`services/ai/.data/evaluation/item-preparation-preview-v1/README.md`

It contains metadata only, not copied or altered images:

- `risk_preview.json`: planned size, splits, limitations and explicit pending permission.
- `source_review.json`: original image paths, SHA-256 source-image proxy groups and object regions.
- `coverage.json`: every current physical-item subcategory and its collection checklist.
- `source_test_annotations.json`: 235 held-out source-annotation cases, clearly not independent review.
- `reviewed_cases.json`: an empty starting file for genuinely reviewed evaluation cases.

The pack stays under ignored `.data`; it contains local paths and must not be
committed. The CLI rejects output outside `services/ai/.data` and refuses existing
output directories, preserving any review drafts. Preparation does not load model
weights, perform inference, generate training photos, download anything or train.
No KYC images, private uploads, live database records or deployed models changed.

## Actual local preview

The existing local Open Images dataset has 1,803 prepared photos. A broad read-only
preview capped at 100 sources per largest-object class per split selected 1,790
distinct source-image hash groups. The **saved starter plan** uses a smaller cap of
25 and selects **839 groups**: 400 train, 219 validation and 220 test.

Two alteration operations with matched normal/risky pairs would produce **at most
3,356 images**, not a guaranteed final count: no-op and duplicate outputs are
skipped. **Actual images generated: zero. Training started: no.** These counts do
not establish source rights, authenticity or physical-item-level independence.

| Category | Specific category | Selected risk source groups | Annotated test cases |
|---|---|---:|---:|
| Devices | Smartphones | 63 | 20 |
| Devices | Cameras | 65 | 20 |
| Devices | Computers | 61 | 20 |
| Devices | Audio | 128 | 40 |
| Devices | Gaming | 0 | 0 |
| Devices | Other devices | 0 | 0 |
| Vehicles | Cars | 73 | 20 |
| Vehicles | Motorcycles | 59 | 18 |
| Vehicles | Bicycles | 55 | 15 |
| Vehicles | Other vehicles | 0 | 0 |
| Equipment | Tools | 115 | 12 |
| Equipment | Sports equipment | 0 | 0 |
| Equipment | Event equipment | 173 | 57 |
| Equipment | Other equipment | 0 | 0 |
| Books | Textbooks | 0 | 0 |
| Books | Reference books | 0 | 0 |
| Books | Fiction | 0 | 0 |
| Books | Other books | 47 | 13 |
| Clothing | Formal wear | 0 | 0 |
| Clothing | Costumes | 0 | 0 |
| Clothing | Traditional wear | 0 | 0 |
| Clothing | Other clothing | 0 | 0 |

Risk selection assigns the largest supported object per image. Test cases may
include several classes in one image and use a separate cap of 20 per class;
case counts are not distinct photo counts. Tools have no held-out hammer example.
Existing generic book annotations do not establish textbook, reference or fiction
identity. All 22 rows still have zero **new independently reviewed** cases. No new
recognition accuracy measurement is claimed; earlier bounded results remain in
[the detector preparation report](ITEM_WORLD_AND_RISK_PREPARATION_RESULT.md).

## What you need to review next

1. Review the selected images' licences, permitted use and attribution. The local
   provenance records download URLs/hashes, but lacks individual photographer and
   licence verification. Downloading a dataset is not permission confirmation.
2. Review near duplicates and whether different photographs show the same physical
   item across splits. Exact hashes alone cannot establish item-level independence.
3. Collect permissioned whole-object, alternate-angle, detail and unrelated photos
   across all 22 rows, particularly the 12 with no source examples. A small smoke
   set can reveal failures but cannot establish production accuracy.
4. Add actual reviewed cases to `reviewed_cases.json` using the existing evaluator
   schema. Positive cases need a correct canonical object label and real normalized
   object boxes; do not copy illustrative boxes or invent absent-object labels.
   Keep final evaluation items separate from training and development.
5. After separate permission confirmation, generate a synthetic research dataset
   in a new folder, inspect the resulting alterations and validate its manifest.
   Training/deployment remain separate decisions; neither runs from this review tool.

Synthetic `normal` means no controlled alteration, not genuine. `risky` means a
known procedural edit, not real counterfeit. Real item manipulation performance
needs independently reviewed real evidence; do not reuse MyKad risk weights or
present synthetic held-out scores as real-world authenticity accuracy.

## Reproduce safely

From `services/ai`, with a **new** output directory:

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_item_review `
  .data/datasets/open_images_items_v1/data.yaml `
  --output .data/evaluation/item-preparation-preview-v2 `
  --per-class 25
```

After collecting and reviewing real evaluation cases (not while the file is empty):

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/item-preparation-preview-v1/reviewed_cases.json
```

No generation/training command was executed or permission flag supplied here.

## Verification

- Focused preparation/manifest suites: **14 passed**. Covers metadata-only output,
  source preservation, all-22 coverage, no invented genre coverage, pending rights,
  empty reviewed cases, existing-draft preservation, private output guard, synthetic
  pairing/manifest checks and leakage rejection.
- Full AI suite: **485 passed**, with two existing third-party deprecation
  warnings (Starlette/AnyIO and spaCy/Click). `git diff --check` passed;
  the generated private pack is confirmed ignored by Git.
- Flutter/API/build checks are not applicable: no application or service contracts changed.

## Commit message

```text
feat(ai): prepare metadata-only item dataset review packs

- inventory grouped item-risk sources without generating images or training
- prepare all-22 recognition coverage and photo-collection checklists
- separate source annotations from independently reviewed evaluation cases
- retain permission and attribution review gates and protect existing drafts
- test source preservation and document local counts and remaining data gaps
```
