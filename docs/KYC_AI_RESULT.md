# RentHub KYC AI continuation result

Last updated: 5 October 2026

## Outcome

RentHub now has a connected, administrator-controlled KYC workflow:

```text
Flutter mobile camera
-> authenticated Express frame endpoint
-> FastAPI KYC document detector
-> stable auto-capture or explicit manual fallback
-> protected upload references
-> Express reads protected bytes
-> OpenCV + EasyOCR + rule-based spaCy/Regex + risk signals
-> append-only MongoDB verification attempt
-> administrator final decision
-> verified profile/listing badge
```

Flutter does not call FastAPI directly. An AI result named
`approved_candidate` is still stored as `pending`; only an administrator can
approve it. This is AI-assisted forgery-risk and consistency assessment, not
government-grade identity authentication or guaranteed forgery detection.

## Formal-scope matrix

| Scope requirement | Implementation/evidence | Status | Limitation |
|---|---|---|---|
| Live in-app camera | `live_kyc_scanner_page.dart` uses the Flutter camera preview and captures real JPEG frames | Implemented for Android/iOS | Windows desktop shows an honest unsupported state; device QA remains required |
| KYC-specific YOLOv8 | `/verify/document-frame` loads only `DOCUMENT_YOLO_MODEL_PATH` | Runtime implemented, artifact missing | `models/document_yolo.pt` must be trained and evaluated; it never reuses item YOLO |
| Live guidance | No document, closer/farther, align, hold steady, lighting/glare, and ready states | Implemented | Guidance quality depends on the missing detector artifact |
| Stable auto-capture | Requires three consecutive ready analyses; confidence defaults to >= 0.65, normalized area 0.28-0.78, inside guide, acceptable blur/light/glare | Implemented/tested | Thresholds need validation against the final detector dataset |
| OpenCV preprocessing | Perspective crop, grayscale, CLAHE, sharpening, blur, brightness, resolution, glare-ratio checks | Implemented | Glare is detected, not forensically removed |
| Multi-image OCR | Every submitted image is preprocessed and read by EasyOCR `en`/`ms`; per-image confidence is retained | Implemented | OCR model files/runtime must be present on deployment; no accuracy claim is made |
| spaCy/structured extraction | spaCy `EntityRuler` plus document-specific Regex extracts identity number, DOB, expiry, name, address, document type, and MRZ evidence where detected | Implemented rule-based layer | This is not a trained custom Malaysian NER model |
| Format and logical checks | MyKad date segment, document type, profile-name match, minimum age, expiry, and passport MRZ format/check digits | Implemented | Weak OCR routes to manual review; Driving Licence validation remains conservative |
| KYC-specific EfficientNet-B0 | Dedicated loader and leakage-safe grouped trainer output `document_risk_efficientnet.pt` | Runtime/trainer implemented, artifact missing | No risk-model metric or production performance claim until reviewed data is trained |
| Text-region/font indicators | OCR boxes feed height/style and local edge/sharpness inconsistency heuristics | Implemented heuristic | Possible inconsistency only; not proof of edited text or exact font authentication |
| Security-feature presence | Passport MRZ presence, format, and ICAO-style check-digit evidence | Partial | Hologram, stamp, and watermark detection are not implemented without a verified labelled dataset |
| Rescan | Blur, extreme light, low resolution, or severe glare returns `rescan_required`; Flutter supports rescan | Implemented | OCR failure with otherwise usable quality is manual/unavailable rather than a fake pass |
| Real-time safe feedback | Scanner guidance plus high-level submission/review states | Implemented | Detailed forensic bypass information is not exposed |
| Independent documents | MyKad, Passport, and Driving Licence have separate current state and attempt IDs | Implemented/tested | Passport is available as a general identity document but does not silently satisfy a rule requiring MyKad |
| Category requirements | MongoDB settings resolve Devices/Equipment high-value MyKad, Vehicles MyKad + licence, Services MyKad, Books/Clothing optional | Implemented/tested | Default high-value threshold is RM 1,000 and is administrator-configurable |
| Booking enforcement | Express checks effective server rules and approved document types before creating a booking | Implemented/tested | Existing development users may need to submit KYC before older demo flows work |
| Attempt history | Protected references, safe AI evidence/model versions, scores/flags, timestamps, and admin outcome are appended | Implemented/tested | Raw OCR text is deliberately removed before MongoDB persistence |
| Admin module | Pending queue, confidence/document sorting/filtering, evidence, risk flags, history, decision reason, thresholds, age, and category rules | Implemented | Advanced aggregate KYC reporting/export is outside this task |
| Verified badge | Only the administrator-approved aggregate identity state updates Owner listing verification | Implemented/tested | AI alone cannot activate it |

## Category policy

| Category | Default requirement |
|---|---|
| Devices | MyKad only when daily price meets the configured high-value threshold |
| Vehicles | MyKad and Driving Licence at every price |
| Equipment | MyKad only when daily price meets the configured high-value threshold |
| Services | MyKad at every price |
| Clothing | Optional |
| Books | Optional |

Turning off the high-value KYC setting disables only threshold-based Devices and
Equipment rules. It does not disable always-required Vehicle or Service rules.

## Dataset and training truthfulness

Git-tracked provenance manifests are under `services/ai/datasets/manifests/`.
They currently record zero selected/downloaded examples. Raw data belongs under
the ignored `services/ai/.data/datasets/` directory.

- MIDV-2020 is planned for document detection, capture conditions, OCR, and
  field extraction.
- FMIDV is planned for manipulated-document risk research.
- IDNet is optional and must remain labelled synthetic.
- MIDV-Holo remains investigation-only; no source or suitability is asserted.
- No real MyKad images may be scraped or committed. Use synthetic MyKad-like or
  explicitly consented secure samples and report them separately.

`train_document_risk.py` requires `path,label,base_document_id` and groups every
original and derivative of a base document into one split. It reports accuracy,
precision, recall, F1, ROC-AUC, and a confusion matrix. `train_document_yolo.py`
exports detector metrics and records required rotation, perspective,
misalignment, scale, and lighting evaluation slices.

Current artifact state:

| Artifact | Present in repository working environment | Consequence |
|---|---:|---|
| EasyOCR model directory | Yes | OCR can run when the installed runtime is compatible |
| `models/document_yolo.pt` | No | Live UI offers an explicit manual camera/file fallback; no detector confidence is invented |
| `models/document_risk_efficientnet.pt` | No | Risk model is reported unavailable and the submission remains for manual review |

## Verification performed

- Flutter analyzer: no issues after the KYC integration.
- Flutter focused tests cover three-frame stability, independent document
  states, and an honest desktop fallback.
- Express focused tests cover protected-byte forwarding, frame forwarding,
  independent document review/history, category requirements, and Vehicle
  booking enforcement.
- FastAPI tests cover unavailable detector behavior, severe-glare rescan,
  MyKad date validation, passport MRZ checks, and existing API contracts.
- Complete regression totals: Flutter 113 passed with 2 intentional skips;
  Express 125 passed with 3 optional live E2E skips in isolated
  mock-auth/local-storage mode; FastAPI 31 passed with 2 third-party
  deprecation warnings; Android debug APK build succeeded.

Final completion still requires training the two KYC artifacts from reviewed
datasets, retaining their held-out metrics, mobile-device camera QA, and a live
Flutter -> Express -> FastAPI -> MongoDB -> Admin end-to-end run.
