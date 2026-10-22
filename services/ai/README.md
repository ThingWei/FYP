# RentHub AI and image-processing service

22 October: CASIA and AutoSplice can be prepared with
`python -m app.training.prepare_public_item_risk --casia ROOT --autosplice ROOT --output .data/datasets/NEW`.
The importer writes metadata only and keeps pending usage review blocked from training.
See [actual preparation results and commands](../../docs/PUBLIC_ITEM_RISK_DATASET_RESULT.md).

For CPU-only candidate training, `train_image_risk` additionally accepts
`--cache-frozen-features --cpu-threads 4`. This computes the deterministic,
frozen EfficientNet features once per image, retaining the same two-class head,
eight-epoch default, validation-loss selection and held-out test split. Features
stay in RAM; the exported candidate remains a complete image-input model.
Progress is printed during extraction and after every epoch. This does not
authorize downloads, acknowledge source rights or deploy the resulting artifact.
See [the completed candidate's results and limitations](../../docs/ITEM_RISK_TRAINING_RESULT.md).
The user-authorized local deployment now uses `models/image_risk_efficientnet.pt`;
synthetic-trained risk remains advisory with administrator review required.

This service uses real, artifact-backed pipelines. It never substitutes random or
hard-coded confidence values when a model is missing.

## Runtime endpoints

- `POST /verify/document`: OpenCV document preparation, EasyOCR extraction and
  spaCy/regex field parsing, MRZ checks, text-region consistency heuristics, and
  the KYC-specific EfficientNet risk signal when its artifact exists. Automated
  output is advisory; an administrator still makes the final KYC decision.
- `POST /verify/document-frame`: KYC-specific YOLOv8 document presence,
  alignment, size, quality, and glare guidance for the Flutter live scanner.
  A missing detector returns `available: false` and never invents confidence.
- `POST /verify/item`: requires at least three images, reports OpenCV quality and
  within-submission duplicate signals, category-aware YOLO object evidence and
  item-specific EfficientNet-B0 risk assistance when a compatible artifact exists.
  The local `yolov8n.pt` can be used as a clearly labelled general pretrained
  fallback; requests never download weights. Unsupported object classes and missing
  risk models require manual review, not a fabricated pass. This is not an
  ownership/authenticity, exact model, book genre or condition assessment.
- `POST /recommend/items`: 60% TF-IDF/cosine content score plus 40% Surprise SVD
  collaborative score. It uses a compatible evaluated artifact, can fit a
  deterministic request-time SVD from sufficient live marketplace interactions,
  and otherwise names its rating/popularity cold-start fallback.
- `POST /recommend/price`: loads an evaluated XGBoost pipeline. If the artifact is
  absent, the endpoint returns `available: false` rather than a guessed price.
  The response includes held-out evaluation metadata, a suggested daily price,
  calibrated uncertainty range, evidence-based confidence and human-readable
  explanation. Express derives active-listing and completed-rental evidence from
  MongoDB using a narrow-to-wide comparable hierarchy. Client-provided market
  aggregates are not trusted. If AI is unavailable, Express only returns a
  clearly labelled median/IQR fallback when enough marketplace evidence exists.

## Create the local research artifacts

### Optional broader item detector and separate risk-data preparation

The existing trained/general item detectors remain first. A prepared local
YOLO-World artifact can supply advisory fallback evidence; prompted matches never
automatically pass a listing. No request/launcher downloads weights or changes
text prompts. One-time setup (roughly 400 MB) from this directory:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-item-world.txt
.\.venv\Scripts\python.exe -m app.training.prepare_item_world --download
.\.venv\Scripts\python.exe -m app.training.audit_item_coverage
```

Set `ITEM_WORLD_ENABLED=false` to disable it; the default prepared path is
`models/item_world_offline.pt`. This artifact is already prepared on the current
workstation, not committed to Git. Prompts are configured for 22 subcategories,
not claimed as successful real-photo validation for all 22.

Read-only evaluation and synthetic ITEM risk preview:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition --dataset-yaml .data/datasets/open_images_items_v1/data.yaml --per-class 3
.\.venv\Scripts\python.exe -m app.training.prepare_item_risk .data/datasets/open_images_items_v1/data.yaml --per-class 3
```

The risk preview creates/trains nothing. Generation requires an explicit opt-in,
source permission and subsequent pair/group review. Synthetic-only risk scores
remain experimental and cannot clear a candidate. See the
[full setup, measured results and remaining data gaps](../../docs/ITEM_WORLD_AND_RISK_PREPARATION_RESULT.md)
before generation or training. MyKad weights/data are not item-risk substitutes.

### Existing training commands

21 October: item-risk training writes only to a NEW isolated candidate directory;
it never replaces deployed weights. Initialization must be cached unless
`--allow-download` is explicitly supplied. Image permissions remain pending for
the current user dataset. See the [validation/readiness handoff](../../docs/AI_VALIDATION_AND_DEMO_READINESS_RESULT.md)
and [real-data collection guide](../../docs/AI_VALIDATION_COLLECTION_GUIDE.md).

Pricing also has a non-deploying forward-time evaluator:
`python -m app.training.evaluate_pricing --real-export FILE --report .data/evaluation/NEW.json`.
Both API export commands accept `--summary-only`, bounded `--limit N` and
`--staged-users PRIVATE_JSON`, and refuse to overwrite existing export files.

From `services/ai`, create a Python 3.11 virtual environment, install
`requirements.txt`, then run:

```powershell
cd ..\api
npm run export:pricing-data

cd ..\ai
python -m app.training.train_tabular_models --real-export ..\api\.data\pricing_observations.json --synthetic-rows 5000
python -m app.training.train_image_risk .data/datasets/item-risk/manifest.csv --output .data/candidates/item-risk-round1 --acknowledge-source-permission
python -m app.training.train_yolo path/to/dataset.yaml
python -m app.training.train_document_risk .data/datasets/kyc-risk-manifest.csv
python -m app.training.train_document_yolo .data/datasets/document-yolo/data.yaml
```

The export contains no direct user identifiers and computes every market feature
from observations strictly earlier than its target row. The training command
labels real and synthetic provenance, uses product-grouped train/validation/test
splits, compares against a median baseline, calibrates its interval on validation
residuals, and writes the model atomically only after a fresh-load smoke test.
Synthetic evaluation must be identified as such in the FYP report. The image
models require labelled datasets; the repository intentionally does not invent
those results.

The item-risk trainer now requires a permissioned CSV manifest with
`path,label,item_id,split,source_type` (paths relative to the CSV). Use
`normal`/`risky` labels, `train`/`validation`/`test` splits, and
`reviewed_real`/`synthetic_manipulation` provenance. Keep all views and derivatives
of one item in the same split. It rejects repeated content and cross-split item
groups, selects the best validation epoch, reports held-out test metrics, and
embeds the runtime contract in its TorchScript export. Caller-supplied grouping
and labels still need independent review. MyKad risk datasets/weights must not
be substituted. See [item verification result](../../docs/ITEM_LEGITIMACY_VERIFICATION_RESULT.md).

Expected runtime files:

```text
models/price_xgboost.joblib
models/recommendation_svd.pkl
models/image_risk_efficientnet.pt
models/item_yolo.pt
models/document_risk_efficientnet.pt
models/document_yolo.pt
models/easyocr/                 # downloaded separately or with explicit opt-in
metrics/*.json
```

## Open Images item-detector dataset

From `services/ai`, inspect available RentHub mappings without downloading photos:

```powershell
.\.venv\Scripts\python.exe -m app.training.prepare_open_images --list-classes
```

The helper can select a bounded subset, create image lists and YOLO labels, and
export `data.yaml` after download validation. Large metadata and photo downloads
require separate opt-ins. **The training annotation CSV alone is about 2.26 GB**,
even with a small photo quota. See the
[step-by-step preparation guide](../../docs/OPEN_IMAGES_ITEM_DATASET_RESULT.md)
before downloading. This prepares object-detection data, not authenticity/risk
labels, and does not run model training. Your existing `downloader.py` is unchanged.

## Recommendation dataset and artifact

The recommendation export is separate from pricing data and includes only a
hashed user ID, listing ID, canonical rating, interaction type, timestamp, and
provenance label:

```powershell
cd ..\api
npm.cmd run export:recommendation-data

cd ..\ai
.\.venv\Scripts\python.exe -m app.training.train_recommendation
```

The trainer uses a reproducible per-user chronological holdout, reports RMSE,
MAE, Precision@5, Recall@5, and HitRate@5, and labels marketplace, demo-seed,
and deterministic synthetic rows separately. It saves the SVD artifact only
after atomic write, reload, and smoke inference succeed. See
`../../docs/RECOMMENDATION_AI_RESULT.md` for the current measured results and
cold-start limitations.

For a safe offline check without replacing the running recommendation artifact:

```powershell
.\.venv\Scripts\python.exe -m app.training.train_recommendation --evaluate-only
.\.venv\Scripts\python.exe -m app.training.train_recommendation --evaluate-only --no-synthetic
```

Reports separate marketplace, demo and synthetic evidence and include a separate
marketplace-only experiment. Optional `--report .data/new-evaluation.json` creates
a new file only (existing files and deployed models/metrics/data are protected).
The input defaults to the existing API export, not a fresh MongoDB export.
Do not remove `--evaluate-only` unless intentionally training and deploying.
Pricing exports support `npm.cmd run export:pricing-data -- --summary-only` in
`services/api` for a bounded read-only count, including eligible external asking
prices without turning them into transactions. See
`../../docs/PRICING_AND_RECOMMENDATION_EVIDENCE_RESULT.md` for measured limitations.

Set `EASYOCR_ALLOW_DOWNLOAD=true` only when an intentional first-run model
download is acceptable. All uploads are sent to this service as authenticated
base64 bytes by the API; private storage URLs are not exposed.

## Advisory MyKad field risk

MyKad `/verify/document` analysis now uses the combined field detector and
synthetic field-crop classifier when the quality/OCR gates pass. Default artifacts:
`models/mykad_fields_front_back_yolo.pt` and
`models/document_risk_synthetic_fields_v2_efficientnet.pt`. Optional process
settings: `MYKAD_FIELD_RISK_ENABLED`, `MYKAD_FIELD_MODEL_PATH`,
`MYKAD_FIELD_RISK_MODEL_PATH`, `MYKAD_FIELD_DETECTION_THRESHOLD` (default 0.5).
Existing default filenames require no configuration changes. A plain AI `.env`
is not automatically read by the launcher: pass overrides to its process environment.

Evidence lives in `extracted_fields.documentFieldRisk` and always identifies
synthetic provenance, uncalibrated field scores and administrator review. Missing,
partial, disabled or incompatible models do not grant clearance. All synthetic
MyKad results remain `manual_review`; Express keeps the attempt pending and the
admin UI displays the coverage and advisory signal. Driving evidence, passport
and whole-card live scanning remain separate. Do not set `DOCUMENT_RISK_MODEL_PATH`
to this crop artifact. Health presence flags are not performance/compatibility proof.
Restart the AI service and Flutter after updating; existing attempts are not
automatically reanalysed. See
`../../docs/MYKAD_FIELD_RISK_INTEGRATION_RESULT.md` for validation and limitations.

KYC dataset provenance manifests are tracked in `datasets/manifests/`; raw
datasets stay under ignored `.data/datasets/`. The KYC risk trainer groups all
derivatives by `base_document_id` so one identity document cannot leak across
train, validation, and test. No KYC model accuracy is claimed until the missing
artifacts and held-out metrics have been produced from reviewed data.
