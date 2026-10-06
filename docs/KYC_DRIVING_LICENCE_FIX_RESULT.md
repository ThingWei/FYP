# Malaysian driving-licence KYC classification fix

Updated: 6 October 2026

## Root cause and outcome

`_extract_document_fields` previously assigned `documentType = mykad` as soon
as it found an IC-format number. Malaysian driving licences can print the same
holder identity number, so valid licence OCR produced a false type mismatch.

The IC number is now extracted independently of document classification.
Classification uses deterministic OCR signals; it does not claim to be a
trained document classifier or proof of authenticity. Administrator approval
remains mandatory, including for `approved_candidate` results.

| Input | Before | After |
|---|---|---|
| Licence headings + IC number | MyKad / false mismatch | Driving licence; holder IC retained; no false mismatch |
| MyKad heading submitted as licence | Mismatch | Still mismatch / manual review |
| IC number only | MyKad, regardless of selected type | Unclassified / manual review |
| Conflicting document headings | Number-driven classification | Ambiguous / manual review |
| Approved licence only | Could incorrectly make aggregate identity approved | Licence approved independently; aggregate identity unverified, tier none |
| Approved MyKad + pending licence | Identity approved | Unchanged; vehicle requirements still missing licence |
| Approved MyKad + approved licence | Both credentials approved | Unchanged; no missing vehicle documents |

## Implementation

- `services/ai/app/services/image_intelligence.py`: separate document signals,
  resolution and identifier extraction; licence class, labelled holder name,
  expiry and Malay `TARIKH LUPUT`; preserve OCR line breaks for MRZ; ignore
  unrelated long printed lines before MRZ; conservative uncertainty, invalid
  IC birth segment and unavailable-risk-model handling.
- `services/api/src/modules/user/user.service.js`: aggregate identity approval
  requires approved MyKad/passport, never a licence alone. Existing independent
  document records, attempts, administrator review and PII masking are retained.
- `services/ai/tests/test_document_classification.py`: synthetic extraction and
  endpoint regressions.
- `services/api/test/user.test.js`: independent document approvals, vehicle
  requirements at each approval stage, licence-only/global status, passport
  identity approval and raw-OCR/identity-number masking in response and MongoDB.
- `docs/KYC_AI_RESULT.md`: links this fix and its validation report.

No Flutter, API schema, upload ownership, frame detector, training pipeline or
category-policy changes. `kycRequirements.js` is unchanged: Vehicles requires
MyKad **and** driving licence at every price. Passport can verify global identity
but does not replace a rule specifically requiring MyKad.

## Explainable classification

`documentTypeSignals` contains heuristic weights and signal labels only; these
are not confidence probabilities and do not contain copied identity numbers.
`documentTypeResolution` is `resolved`, `insufficient_evidence` or `ambiguous`.
An unresolved result omits `documentType` and requires manual review.

- MyKad: explicit MyKad / Kad Pengenalan / Identity Card heading, weight 4.
- Passport: Passport/Pasport heading or `P<` MRZ heading, weight 4 each.
- Licence: Driving Licence/License or Lesen Memandu heading, weight 4;
  class field, weight 2; labelled validity date, weight 1; Malaysia, weight 1.
  Common narrow OCR substitutions in headings are tolerated, for example
  `DR1V1NG L1CENCE` and `LES3N MEM4NDU`.
- A score of at least 4 is required. Selected licence context permits a score
  of 3 only when **both class and validity date** are present. Context alone,
  IC number alone or Malaysia alone cannot classify a document.
- Conflicting document headings, or competing qualifying scores less than 2
  apart, stay ambiguous. A selected type cannot override a clear other heading.

MyKad-format numbers still undergo birth-date validation on licences too.
Name, class and expiry are extracted only when readable labelled fields exist;
missing values are not invented. Wrong-type evidence, invalid IC date segments,
invalid detected passport MRZ and expired documents keep results manual-review.
OCR confidence continues to describe OCR only, not authenticity or absent models.

## Tests executed

PowerShell commands executed from the indicated service directories:

```powershell
# C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m pytest tests/test_document_classification.py tests/test_contracts.py -q
# Initial focused run: 32 passed, 2 third-party deprecation warnings.

.\.venv\Scripts\python.exe -m pytest -q
# Final full AI run: 49 passed, 2 third-party deprecation warnings (5.61s).

# C:\Users\weith\FYP\services\api
$env:NODE_ENV='test'; $env:AUTH_MODE='mock'; $env:STORAGE_MODE='local'; $env:FCM_MODE='disabled'; $env:BLOCKCHAIN_MODE='disabled'; node --test test/user.test.js
# Initial user run: 22 passed, 0 failed.

$env:NODE_ENV='test'; $env:AUTH_MODE='mock'; $env:STORAGE_MODE='local'; $env:FCM_MODE='disabled'; $env:BLOCKCHAIN_MODE='disabled'; node --test test/user.test.js test/ai-client.test.js test/upload.test.js test/booking_rental.test.js
# Final focused API run: 46 passed, 0 failed, 0 skipped (5.20s).

# Repository root
git diff --check
```

The API tests use an isolated in-memory MongoDB and test-only authentication;
these settings do not change the application's `.env`. Existing checks also
cover protected byte forwarding, unavailable AI, private upload authorization,
live-frame forwarding and actual Vehicle booking enforcement. No real document
images or identity data were added. Controlled OCR tests use explicit stubs,
not a claimed live EasyOCR accuracy measurement. Flutter/device QA was not run
because this fix makes no Flutter changes.

## Remaining limits and rollout

- `services/ai/models/document_yolo.pt` and
  `services/ai/models/document_risk_efficientnet.pt` are still absent in this
  working environment. EasyOCR's model directory is present, but deployment
  runtime compatibility and real camera/OCR quality require separate validation.
- Missing risk artifacts explicitly report unavailable and keep the document
  manual-review. No YOLO predictions, risk probabilities or accuracy metrics
  are fabricated. The existing detector's manual-capture fallback is unchanged.
- Classification is conservative textual interpretation, not a trained
  Malaysian document classifier or official identity/licence validation.
  Unlabelled fields, severe OCR corruption, arbitrary spelling errors, layouts
  with only an unlabelled validity range and damaged MRZ can require manual review.
- There is no historical MongoDB migration. Stored old AI evidence remains
  historical; new analyses use the fixed extraction. Existing incorrectly
  approved licence-only aggregate records need an administrator/data-maintenance
  review; do not silently rewrite previous approvals.
- Restart the AI service and API to load the fix, then test a new submission
  using securely handled, explicitly consented Malaysian document samples.

Suggested commit message:

```text
fix(kyc): distinguish Malaysian driving licences from MyKad identity numbers

- classify documents using explainable OCR evidence and selected-type context
- extract licence fields without treating holder IC numbers as document types
- preserve wrong-document checks, MRZ validation and manual-review fallbacks
- prevent licence-only approval from granting global identity verification
- cover independent vehicle KYC, passport regressions and PII masking
```
