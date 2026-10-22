# Item-photo risk candidate: actual training results

Completed 22 October 2026 after the user's explicit instruction to train.
**Trained and benchmark-evaluated; not deployed.** No source images were edited,
generated, copied, deleted or committed. No existing model, metric, environment
setting, database record or running-service configuration was changed.

## Permission acknowledgement and attribution

The user's go-ahead after the attribution discussion was recorded as
`sourcePermissionAcknowledgedByCaller=true`. This is a caller acknowledgement,
not independent verification of rights. The original pending-review preparation
pack remains unchanged; a new acknowledged manifest was created.

- AutoSplice's downloaded `README.txt` permits academic, noncommercial research
  and supplies its citation. See the [publisher's licence/citation section](https://github.com/shanface33/AutoSplice_Dataset#license-and-citation).
  Cite Shan Jia et al., *AutoSplice: A Text-prompt Manipulated Image Dataset for
  Media Forensics*, CVPR Workshops, 2023, pp. 893–903. Its source photographs come
  from Visual News; retain that provenance and consult the upstream requirements
  before redistribution or a different use.
- CASIA's [corrected mirror](https://github.com/SunnyHaze/CASIA2.0-Corrected-Groundtruth#cite)
  and [ground-truth project](https://github.com/namtpham/casia2groundtruth) supply
  citation/acknowledgement information: Dong et al., *CASIA Image Tampering
  Detection Evaluation Database* (2013), and Pham et al., *Hybrid Image-Retrieval
  Method for Image-Splicing Validation* (2019). A clear standalone usage licence
  was **not established** from the mirror/extracted files. Citation does not
  resolve that uncertainty. Do not interpret this run as commercial-use approval
  or redistribute these images/weights without resolving applicable rights.

The separate Open Images synthetic-generation permission remains pending. This
run used the existing CASIA/AutoSplice benchmark labels, not that generator,
private uploads, MyKad images or driving-licence images.

## Data and training configuration

New ignored manifest:
`services/ai/.data/datasets/public_item_risk_acknowledged_v2/manifest.csv`.
It references the existing extracted Downloads folders; keep those files in place.
See [the preparation report](PUBLIC_ITEM_RISK_DATASET_RESULT.md) for inventories,
deduplication, grouping and original paths.

| Split | Normal | Risky | Total |
|---|---:|---:|---:|
| Train | 6,698 | 6,185 | 12,883 |
| Validation | 1,435 | 1,280 | 2,715 |
| Test | 1,435 | 1,279 | 2,714 |

The importer inspected 18,508 photos, omitted 196 exact decoded duplicates and
selected 18,312 rows. Known source-family, raw-hash and RGB-hash cross-split
overlaps: **zero**. Near-duplicate and physical-item independence remain unverified;
ten source IDs lack originals and the largest intact connected component has
3,898 photos. No group was split to improve metrics.

- EfficientNet-B0, locally cached ImageNet initialization; no downloads.
- Frozen feature extractor, including evaluation-mode BatchNorm; only the
  two-class classifier head is trained. This is not full-backbone fine-tuning.
- Seed 42, eight epochs, batch 16, AdamW learning rate 0.001, cross-entropy.
- Deterministic RGB resize to 224×224 and ImageNet normalization, unchanged.
- CPU-only, four threads; Python 3.11.5, PyTorch 2.5.1+cpu, torchvision 0.20.1+cpu.
- Optional RAM feature caching avoids repeating the frozen deterministic backbone.
  Each split stays separate, test features are extracted only after model
  selection, and the exported model still accepts images, not cached vectors.
  Cached/non-cached runs use different random-number consumption; do not claim
  identical training trajectories. The configuration records this option.
- Training/export elapsed time: **167.09 seconds**, excluding preparation,
  tests and the separate full-image export verification.
- Checkpoint selected solely by minimum validation loss: **epoch 2**, loss
  **0.613509**, validation accuracy **67.26%**. Epoch 8's higher validation
  accuracy did not override the preselected loss criterion. No test tuning.

Content/group/split fingerprint (importer):
`2c9e2d9729a43d0c8c1f9686b56b7279304e8d846b38b395b31d3365d73f0345`.

Manifest plus source-byte fingerprint (trainer):
`5099335e15fdb0aa882f1f20949909a9dc5df6184d8c5fd1f05cb9c80ece146a`.
These are deliberately different fingerprint definitions, not conflicting checksums.

## Held-out benchmark results

Both datasets retain `source_type=synthetic_manipulation`: controlled photo edits,
not verified real marketplace incidents or counterfeit goods. Test predictions
use the two-logit argmax without threshold tuning.

| Cohort | Samples | Accuracy | Macro precision | Macro recall | Macro-F1 |
|---|---:|---:|---:|---:|---:|
| Combined | 2,714 | 68.64% | 0.6853 | 0.6845 | 0.6848 |
| CASIA | 1,830 | 66.72% | 0.6533 | 0.6521 | 0.6526 |
| AutoSplice | 884 | 72.62% | 0.7128 | 0.7177 | 0.7147 |
| Reviewed real marketplace cases | 0 | Not evaluated | — | — | — |

For context, always predicting the combined test majority class (`normal`) gives
52.87% accuracy. This descriptive baseline is not a new deployment threshold.

Confusion matrices: rows = true `normal`, `risky`; columns = predicted `normal`,
`risky`.

| Cohort | True normal → normal / risky | True risky → normal / risky |
|---|---:|---:|
| Combined | 1,030 / 405 | 446 / 833 |
| CASIA | 798 / 296 | 313 / 423 |
| AutoSplice | 232 / 109 | 133 / 410 |

Combined risky-class precision is **67.29%**, recall **65.13%**, F1 **0.6619**.
The model missed **446 of 1,279** labelled altered test photos and flagged
**405 of 1,435** unaltered benchmark photos. These substantial errors rule out
using this candidate as an automatic approval/rejection or authenticity gate.

## Candidate files and verification

Candidate directory: `services/ai/.data/candidates/item-risk-public-round1/`:

- `image_risk_efficientnet.pt`: complete TorchScript image-input model, embedded
  `renthub-item-risk-v1` metadata, classes, preprocessing and provenance.
- `image_risk_metrics.json`: test/cohort metrics and all eight epoch results.
- `configuration.json`: reproducibility settings and elapsed time.

Artifact SHA-256:
`6913286b4a82ddebffb0027542663248d1beaacd1b8d46a3a4a1a9d427eea02d`.

- Focused preparation/manifest/trainer tests: **32 passed**.
- Full AI suite: **510 passed**, four existing warnings (two third-party
  deprecations and two expected sparse-pricing fixture warnings).
- Export smoke check passed: finite two-class output and matching eager logits.
- Separately reloaded the exported TorchScript artifact and inferred **all 2,714
  test images through the full image model**. All aggregate metrics/confusion
  counts exactly matched the cached-feature evaluation.
- Cached-feature tests cover label/order retention, logits equivalence, isolated
  candidate export, permission gates, source cohorts and overwrite prevention.
- SHA-256 inventories of **all deployed models and metrics are unchanged**.
  Candidate/data files stay Git-ignored. No API/Flutter contract or presentation
  changes; their builds are not applicable to this training-only task.

Reproduce as a **new** candidate from `services/ai` (never overwrite round1):

```powershell
.\.venv\Scripts\python.exe -u -m app.training.train_image_risk `
  .data/datasets/public_item_risk_acknowledged_v2/manifest.csv `
  --output .data/candidates/item-risk-public-round2 `
  --epochs 8 --seed 42 --acknowledge-source-permission `
  --cache-frozen-features --cpu-threads 4
```

The manifest is machine-local because it contains absolute source paths. New
data or group assignments require a new preparation pack and evaluation record.

## Remaining gates

This is an experimental manipulation-risk baseline, **not completed real-world
item-risk validation**. News/benchmark photos do not represent every RentHub
subcategory; source/encoding confounds and incomplete family links remain possible.
Normal is not proof of ownership, condition, authenticity or absence of editing.
CASIA and AutoSplice are subsets of one mixed training experiment, not mutually
unseen cross-dataset evaluations.

Before any explicit advisory-only deployment, review the rights uncertainty and
false positives/negatives, collect permissioned independently reviewed listing
photos, evaluate that untouched real cohort separately, and check runtime copy.
Do not reuse the held-out benchmark for tuning and still describe it as untouched.
Administrator review stays mandatory. No environment setting or deployment has
been changed, so the app does **not** automatically start using this candidate.

## Commit message

```text
feat(ai): train isolated CASIA and AutoSplice item-risk candidate

- add optional deterministic frozen-feature caching for CPU training
- report extraction progress, epoch metrics and reproducibility settings
- test cache equivalence, split order and candidate-only export safeguards
- record eight-epoch benchmark metrics and full-image TorchScript verification
- document caller acknowledgement, CASIA licence uncertainty and real-data gaps
- preserve source photos, deployed models and synthetic-only advisory limits
```
