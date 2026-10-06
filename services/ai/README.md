# RentHub AI and image-processing service

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
- `POST /verify/item`: requires at least three images and combines OpenCV quality
  checks, duplicate detection, a trained YOLO detector and an EfficientNet-B0 risk
  classifier.
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

From `services/ai`, create a Python 3.11 virtual environment, install
`requirements.txt`, then run:

```powershell
cd ..\api
npm run export:pricing-data

cd ..\ai
python -m app.training.train_tabular_models --real-export ..\api\.data\pricing_observations.json --synthetic-rows 5000
python -m app.training.train_image_risk path/to/reviewed-risk-images
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
