# Expanded item-recognition candidate

Prepared 25 October 2026 using existing local pretrained weights. This is an
isolated candidate, **not deployed**, with **no real-photo accuracy evaluation**.
It does not complete legitimacy/authenticity verification.

## Changes

Added a versioned `expanded_v2` vocabulary while retaining the original
`baseline_v1` prompts and hash. Older artifacts without a profile field still
validate as the baseline. Unknown profiles, mismatched vocabulary hashes,
incorrect class names and incompatible text-embedding shapes remain rejected.
Runtime inference still does not encode prompts, download weights or force only
the requested category to compete.

The candidate adds concrete targets for mouse, keyboard, monitor, camera lens,
audio mixer, VR headset, walkie-talkie, video capture, smartwatch, electric and
mobility scooters, electric unicycle, sander, grinder, camping tent, sleeping bag,
golf clubs, paddleboard, life jacket, snorkelling set, exercise machines, tripod,
PA system, fabric-cleaning extractor, formal jacket, hanfu, kurta and raincoat.
Paper, screen, illustration and other competing context prompts are retained.
The generic `power_tool`, `formal_wear` and `traditional_costume` routes remain
under manual review rather than adding umbrella prompts to make coverage pass.

Preparation supports `--profile` and an explicit `--candidate-output` under
`.data/candidates`. Expanded preparation requires that separate output. Existing
candidate files/reports/pending work and active configured artifacts cannot be
selected as a new candidate output. Preparation records source checksums and a
report and does not change environment settings or activate the model.

The evaluator accepts `--world-candidate` to substitute only its World branch,
preserving configured/general detector precedence and photo-context checks.
Reports distinguish candidate detection from the actual production hybrid.
No API paths, prices, Flutter presentation or approval rules changed.

## Actual preparation

Private artifact:
`services/ai/.data/candidates/item-world-expanded-v2/model.pt`.
Report: `model.report.json` in the same directory.

| Property | Active baseline | Separate candidate |
|---|---:|---:|
| Text prompts | 66 | 96 |
| Distinct canonical detection labels | 65 | 95 |
| Defined object-type routes with matching labels, combined with existing detectors | 62/92 | 89/92 |
| Real evaluation photos | 0 | 0 |

The two book prompts map to the same canonical label; prompt count and distinct
label count differ. These figures describe vocabulary, not trained-category
counts, sensitivity, calibrated accuracy or complete catalogue coverage.
No classifier/detector fine-tuning was performed.

- YOLO-World source: existing cached `yolov8s-worldv2.pt`.
- Text encoder: existing cached `ViT-B-32.pt`; checksum verified.
- No network downloads or new dependencies.
- Candidate SHA-256:
  `9a06716011535cddd587718dc38a0529dc650c3d2b4fe73957969d38015796aa`.
- Vocabulary SHA-256:
  `7077d66d84da516f1bd6255a61ddd4013116b12e8266d3f1cc1d7e0dd84115ae`.
- Active custom/general/World/risk artifact checksums remained unchanged.
- Ultralytics profile settings/cache writes were denied by the sandbox, but
  preparation, local loading and inference succeeded without broader access.

## Bounded negative diagnostics

Generated three diagnostic fixtures locally: a blank light image, seeded random
noise (seed 42), and a simple flowchart. Each was checked against smartphone,
monitor and VR-headset routes: **nine negative domain cases per configuration**.
These are generated smoke checks, not permissioned real rental photos, training
images or a representative false-positive benchmark.

| Configuration | Baseline branch false-positive cases | Hybrid false-positive cases | World-only false-positive cases | Hybrid unavailable cases |
|---|---:|---:|---:|---:|
| Active | 0 | 0 | 0 | 0 |
| Candidate | 0 | 0 | 0 | 0 |

No positive photos were evaluated. Therefore recall, missed-object behaviour,
real-photo false-positive rates and benefit over the active model are unknown.
These nine cases do not reproduce every screenshot/wallpaper or prove that
depicted objects can be distinguished from physical objects.

Private results and generated fixtures:
`services/ai/.data/candidates/item-world-expanded-v2/diagnostics/comparison.json`.
The candidate remains undeployed. Existing risk analysis and mandatory
administrator review remain separate from object recognition.

## Reuse and next evaluation

From `services/ai`, inspect the isolated candidate without reading real photos:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --coverage-only `
  --world-candidate .data/candidates/item-world-expanded-v2/model.pt
```

After actual permissioned photos and annotations are available:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/item-subtype-readiness-v1/reviewed_cases.json `
  --world-candidate .data/candidates/item-world-expanded-v2/model.pt
```

The reviewed file is currently empty, so that second command correctly refuses
evaluation. Do not mark slots reviewed or fabricate boxes to make it run. Include
real whole-object/alternate-angle positives, close-up limitations, and unrelated
photos for each assessed type, with physical items held out from training.
Compare the active and candidate models using the same cases before a deployment
decision. Candidate prompt expansion is not evidence that fine-tuning is no
longer needed. Fine-grained book genres, traditional garments and generic bundle
types may need additional context or targeted training data.

## Verification

Regression checks cover baseline compatibility, explicit profiles, unchanged
baseline vocabulary, concrete targets, retained context classes, isolated output,
existing-work preservation, evaluator branch substitution and offline candidate
inference. Local optional-artifact checks skip in environments without the private
candidate. Final suite results are recorded below.

- Full AI suite: **599 passed**, four existing dependency/imputation warnings.
- Actual local candidate loaded with networking and runtime prompt encoding
  forbidden; blank-image inference returned no detections.
- Profile/hash mismatch guards passed using the real local candidate.
- Active custom/general/World/risk SHA-256 checks repeated after tests: unchanged.
- `git diff --check`: clean.
- No Flutter or Express presentation/endpoint code changed in this increment;
  their suites/builds were not repeated. Prior API/Flutter results remain in the
  separate catalogue/type-alignment result documents.

Suggested commit:

```text
feat(ai): prepare isolated expanded YOLO-World recognition candidate

- retain baseline vocabulary compatibility with explicit prepared profiles
- add concrete targets for remaining catalogue object types
- protect active artifacts and existing candidate outputs during preparation
- support candidate-only evaluation without runtime configuration changes
- verify offline inference, profile/hash guards and negative smoke behaviour
- document unmeasured real-photo accuracy and deployment prerequisites
```
