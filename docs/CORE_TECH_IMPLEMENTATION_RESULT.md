# RentHub core-technology implementation result

Last updated: 2026-10-02

This implementation follows the decisions and gaps recorded in
`SCOPE_ALIGNMENT_AUDIT_RESULT.md`.

## Implemented end-to-end

- Identity documents: protected upload bytes flow from storage through Express
  to OpenCV, EasyOCR and spaCy/regex processing. Results and failure reasons are
  saved with the pending KYC submission and shown to the administrator. The
  administrator remains the legal decision-maker.
- Physical item images: the final Owner form and API require at least three
  images. OpenCV checks quality/duplicates, YOLO checks object/category signals,
  and EfficientNet-B0 provides the trained risk classification when its artifact
  exists. Missing weights create a manual-review result, never a fake pass.
- Recommendations: renter home loads a dedicated authenticated endpoint using a
  60% TF-IDF/cosine content score and 40% Surprise SVD score. Marketplace-wide
  MongoDB interactions support live IDs; a compatible artifact is preferred and
  the response names the rating/popularity fallback during cold start.
- Pricing: the Owner form sends category, specific category, brand, exact model,
  condition, item age, Malaysian state and expected rental duration without
  requiring an Owner-entered price. Express independently derives current active
  and completed-rental evidence from MongoDB through exact-product, brand,
  subcategory, local-category and marketplace-wide tiers. A versioned XGBoost
  pipeline uses this evidence with item and Owner features. The displayed range
  is calibrated from held-out validation residuals and confidence reflects model
  reliability, evidence volume, freshness and feature completeness. If the model
  is unavailable, a labelled median/IQR fallback is allowed only with sufficient
  database evidence; otherwise the UI reports insufficient data. No static
  product prices, category rental multipliers or client-provided market averages
  affect the result. The Owner can accept or ignore the suggestion.
- Blockchain: approving a physical booking deploys and signs a Solidity rental
  agreement on Ganache. Cancellation, return completion, dispute opening,
  resolution and dismissal update the contract and persist transaction hashes.
  Flutter labels these records as local agreements.

## Artifact truthfulness

The repository includes deterministic tabular training/evaluation code and
separate image-model training entry points. Generated weights and synthetic data
are ignored by Git. No production accuracy is claimed without checked-in metrics
from a reviewed run and, for image models, a labelled dataset.

Expected artifacts are documented in `services/ai/README.md`. The default API
mode is `AI_ENFORCEMENT_MODE=advisory`; use `strict` only after the image models
have been trained, evaluated, and installed. Blockchain is disabled by default
outside Docker Compose and can be enabled with `BLOCKCHAIN_MODE=ganache`.

## Verification performed

- Express API: 81/81 tests passed with external blockchain and push adapters
  disabled for the isolated test run.
- Flutter: full analyzer clean. The pricing-focused suite passes 6/6. The broader
  suite currently records 80 passes, two existing conditional skips and one
  unrelated account-page test failure because `SecurityPage` is mounted without
  its required `AuthController` provider. Pricing does not modify authentication.
  Previously verified renter/Owner and separate administrator web builds remain
  unchanged by this implementation.
- Solidity: 4/4 Hardhat tests passed.
- Ganache: deploy/sign, dispute/dismiss, dispute/resolve, complete, and cancel
  smoke lifecycle passed against the JSON-RPC node.
- Python: 13/13 FastAPI, dataset and training tests pass in the Python 3.11
  environment. The latest mixed-source run reports selected-strategy MAE 10.64,
  RMSE 24.43 and R² 0.981 on 784 grouped test rows, with 90.56% interval coverage.
  The dataset contains only 13 real observations versus 5,000 explicitly labelled
  synthetic observations, so these figures are development evidence and not a
  production-accuracy claim.

## Lifecycle automation and health follow-up

On 30 September 2026, the API gained configurable lifecycle automation for
unpaid booking expiry, start/return reminders, overdue physical rentals, and
service completion reminders. Automated notifications use durable deduplication
keys. Administrators can inspect MongoDB, authentication, storage, AI,
blockchain, scheduler state, and operational counts in the live dashboard and
can trigger a guarded manual lifecycle run.

The environment and unfinished-work audit is maintained in
`REMAINING_IMPLEMENTATION_AND_SETUP_CHECKLIST.md`.

The administrator Reports page now also supports persistent daily, weekly, and
monthly schedules plus manual CSV generation for platform summaries, bookings,
payments, users, listings, and disputes. Generated files remain available in
MongoDB for authenticated administrator download. The background worker uses a
schedule lock and deterministic generation key to prevent duplicate scheduled
reports across repeated runs.
