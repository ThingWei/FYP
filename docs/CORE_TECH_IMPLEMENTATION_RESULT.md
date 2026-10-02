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
  condition, item age, Malaysian location and expected rental duration without
  first requiring an Owner-entered price. Express matches exact local listings
  and completed rentals, and blends the XGBoost result with dated Malaysian
  market comparables when an exact product reference exists. Direct rental
  evidence receives the highest weight. When a category such as books has no
  rental evidence, resale asking prices can be converted through a documented
  category rental factor at lower confidence. Financing and rent-to-own prices
  are excluded. Comparable source URLs and observation dates remain in the
  response for auditability. The UI shows the
  suggested price, range, adjusted confidence and explanations, and the Owner
  can accept or ignore it. Missing artifacts leave the entered price unchanged.
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

- Express API: 54/54 tests passed.
- Flutter: analyzer clean; 72 tests passed and two environment-dependent tests
  remained skipped by their existing conditions. Both renter/Owner and separate
  administrator web entry points built successfully; existing socket.io WASM and
  Cupertino font warnings remain non-blocking.
- Solidity: 4/4 Hardhat tests passed.
- Ganache: deploy/sign, dispute/dismiss, dispute/resolve, complete, and cancel
  smoke lifecycle passed against the JSON-RPC node.
- Python: the FastAPI contract suite passes 4/4 in the Python 3.11 virtual
  environment. The local XGBoost artifact returns real inference output and its
  retained synthetic held-out metrics (MAE 4.37, RMSE 6.57, R² 0.985). These
  metrics describe the deterministic synthetic FYP dataset, not production
  marketplace accuracy.

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
