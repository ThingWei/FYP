# RentHub AI and image-processing service

This service uses real, artifact-backed pipelines. It never substitutes random or
hard-coded confidence values when a model is missing.

## Runtime endpoints

- `POST /verify/document`: OpenCV document preparation, EasyOCR extraction and
  spaCy/regex field parsing. Automated output is advisory; an administrator still
  makes the legal KYC decision.
- `POST /verify/item`: requires at least three images and combines OpenCV quality
  checks, duplicate detection, a trained YOLO detector and an EfficientNet-B0 risk
  classifier.
- `POST /recommend/items`: 60% TF-IDF/cosine content score plus 40% Surprise SVD
  collaborative score. It uses a compatible evaluated artifact, can fit a
  deterministic request-time SVD from sufficient live marketplace interactions,
  and otherwise names its rating/popularity cold-start fallback.
- `POST /recommend/price`: loads an evaluated XGBoost pipeline. If the artifact is
  absent, the endpoint returns `available: false` rather than a guessed price.
  The response includes the held-out evaluation metadata, a suggested daily
  price, uncertainty range and human-readable feature explanation. Express adds
  live marketplace coverage and reduces confidence when comparable or completed
  rental evidence is unavailable. The Express pricing orchestration can blend
  an exact-product prediction with dated Malaysian market references. Direct
  short-term rentals receive more weight than category-adjusted resale evidence;
  installment, subscription and rent-to-own prices are excluded.

## Create the local research artifacts

From `services/ai`, create a Python 3.11 virtual environment, install
`requirements.txt`, then run:

```text
python -m app.training.train_tabular_models
python -m app.training.train_image_risk path/to/reviewed-risk-images
python -m app.training.train_yolo path/to/dataset.yaml
```

The first command produces deterministic synthetic-data artifacts and held-out
metrics for pricing and collaborative filtering. Synthetic evaluation must be
identified as such in the FYP report. The image models require labelled datasets;
the repository intentionally does not invent those results.

Expected runtime files:

```text
models/price_xgboost.joblib
models/recommendation_svd.pkl
models/image_risk_efficientnet.pt
models/item_yolo.pt
models/easyocr/                 # downloaded separately or with explicit opt-in
metrics/*.json
```

Set `EASYOCR_ALLOW_DOWNLOAD=true` only when an intentional first-run model
download is acceptable. All uploads are sent to this service as authenticated
base64 bytes by the API; private storage URLs are not exposed.
