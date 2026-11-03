# Rotation-aware item evidence and Android viewing checks

Implemented and checked 2 November 2026 (Malaysia time). This follows the public
photo pilot. The user connected an Android phone and explicitly allowed navigation
through existing screens, stopping before creating bookings or making demo payments.

## Root cause and changes

The detector tried alternative orientations until it found the requested object
type. Original scene evidence from a model without that requested vocabulary could
be skipped. This allowed a rotated mouse/cable to become headphones/controller,
and a headphone component to become a mouse. A high detection score did not resolve
the conflicting evidence.

- Inspect every available fixed detector in the original orientation before
  target-oriented rotation retries. Retain original context even from models
  whose vocabulary does not contain the requested label.
- Preserve original boxes/confidences when a higher-scoring rotated detection
  replaces the retained representative. Earlier evidence cannot disappear merely
  because a later rotation has a larger score.
- A rotation-only match with a different original-orientation object in the same
  or contained region requires review. Geometry requires at least 80% intersection
  of the smaller region; unrelated nearby objects do not trigger that check.
- Use explicit existing object-type aliases to distinguish hypotheses; no fuzzy
  label matching, target-only prompts, named-image blacklist or new detector labels.
  Person/context classes do not automatically contradict an item. Supporting
  original evidence of the same type prevents a false rotation-only designation.
- Cross-model scores are not compared as calibrated probabilities. The result is
  **ambiguous evidence**, not a wrong-item, forgery or image-quality verdict.
- Retain legitimate sideways detections without contradictory original evidence.
  Inference is still bounded by the existing available models/four orientations;
  confidence stays 0.55 and no model, prompt embedding or weight changed.
- Add separate optional `rotationEvidenceReviewRequired` and
  `depictedContentReviewRequired` context flags. Raw labels/boxes/scores remain
  available for diagnostics, but contested matches no longer contribute to
  category consistency or the aggregate matching score.
- Flutter uses **The item type is unclear in some photos. An admin will take a
  closer look.** and **Item type needs a closer look**. It does not call these
  photos blurry, documents or screen copies. Both notes remain when actual
  document-context uncertainty is also present. Legacy context responses remain
  supported.

Existing endpoint paths, required request fields, adapter contract, manual-review
workflow, item-quality checks and MyKad phone-screening detector selection are
unchanged. Context fields are additive. No catalogue/pricing/Auth0/payment or
blockchain change was made.

## Measured regression results

The earlier public pilot is now a **known development/regression set**, not an
independent holdout after this fix. It has 11 unique photos, nine manually boxed
positives, two detail views and 22 category-negative checks reusing two images.
Only seven subcategories have positives. No full-category accuracy is claimed.

| Variant | Localized positives before → after | False category matches before → after |
| --- | --- | --- |
| Configured + general | 7/9 → 7/9 | 2/22 → 0/22 |
| World alone | 2/9 → 2/9 | 1/22 → 1/22 |
| Production hybrid | 7/9 → 7/9 | 3/22 → 0/22 |

All three previous hybrid false matches become reviewable rather than consistent
type matches. World alone still lacks the fixed-model context needed for one
case; its limitation is preserved in the report. The generic book and all-in-one
desktop still fail localization and stay manual-review cases. No rule pretends
to identify them correctly. New independent photos and targeted data/model work
are required before claiming improved general accuracy or all-22 coverage.

Private traces/reports:

- `services/ai/.data/evaluation/public-photo-pilot-2026-11-01/failure-trace-2026-11-02.json`
- Same directory: `recognition_rotation_fix_2026-11-02.json` (previous result kept).
- `services/ai/.data/evaluation/item-rotation-2026-11-02-live-response.json`

A read-only POST to the running FastAPI `/verify/item` used three distinct public
non-controller photos with expected Gaming/controller. It returned zero matched
views, confidence zero, warning outcome and `accepted=false`; the new context
fields were present. This verifies the running AI had loaded the change. It did
not create uploads/listings or write to MongoDB.

Reproduce from `services/ai` with a new report filename:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/public-photo-pilot-2026-11-01/reviewed_cases.json `
  --training-manifest .data/evaluation/public-photo-pilot-2026-11-01/training_exclusions.csv `
  --report .data/evaluation/rotation-regression-next.json
```

## Actual Android viewing checks

Device: connected Xiaomi Android phone; existing installed debug app,
1440×3200 physical pixels at density 560. Existing USB reverse mapping for API
port 3000 was retained. The PC API readiness endpoint reported database connected;
the running AI health endpoint responded. An optional shell-network probe returned
no parseable payload and is not treated as a connectivity pass or failure; actual
authenticated UI retrieval worked.

| Screen/flow | Observed result |
| --- | --- |
| Explore | Stored cards, photos, blue selected comparison control and pagination rendered |
| Renter Bookings | Seven existing records, readable dates/statuses, amount and paging footer |
| Paid-pending agreement | Opened from the existing booking without a connection error; saved charges, pending status, terms and location privacy notice displayed |
| Agreement scrolling | Charges and responsibilities scroll normally; no booking/payment write was submitted |
| Conversations | Two peer rows combine two/five existing booking threads, rather than repeating peers |
| Chat | Existing text and protected image attachments loaded; no new message sent |
| Chat header | Opened the counterpart's safe profile and verification/trust summary |
| Old own-message long press | Offered Delete for me; timed edit/recall were absent; no deletion selected |
| Share location picker | Opened public map tiles, recipient notice and GPS/search controls; Share stayed disabled without a selected pin; cancelled without sending a location or requesting GPS |
| Renter → Owner | Owner dashboard/Requests did not display the outgoing renter booking; zero incoming requests, no Approve/Reject controls for that outgoing record |
| Owner listings | 21 records; verified 1–10, 11–20 and final 21–21 ranges; returned to first page |

The phone was left on Owner Home. No logout, second-account login, real/demonstration
payment, booking creation/approval/cancellation/return, message send/edit/recall/delete,
listing mutation, GPS reading or notification send was performed. Normal app
read-receipt/session/active-role behaviour may occur while viewing; this is not a
claim that the entire UI has no read-side effects.

The paid-pending agreement check is **not** a new checkout-success → agreement
walkthrough. A full two-account booking/payment/approval/handover/return run,
native camera capture, GPS precision and actual FCM delivery remain outstanding.
No historical records were changed merely to populate that demonstration.

Screenshots are private under `services/api/.data/device-check-2026-11-02`, not
committed or embedded in this document. Names, emails, message contents and raw
identity information are not reproduced here.

## Verification

| Check | Result |
| --- | --- |
| Focused AI detection/context/World/alias tests | 172 passed |
| Full AI suite | 635 passed; four existing dependency/sparse-fixture warnings |
| Flutter photo-review tests | 34 passed, including 360/390/1024 widths and 1.5 text scale |
| Full Flutter suite | 557 passed, three existing opt-in skips |
| Flutter analysis | No issues |
| API listing/health tests | 25 passed with isolated mock auth and external effects disabled |
| Main web build | Passed |
| Administrator web build | Passed |
| Android debug APK build | Passed; not installed over the phone's existing configured app |
| Deployed model/metrics checksum inventory | All 18 unchanged |
| Whitespace check | Passed |

Tests include generic cross-type contradictions, original-context retention,
overlap versus nearby objects, alias support, legitimate sideways photos, missing
boxes, original evidence surviving rotated replacements, separate document/rotation
flags, bounded inference, unchanged thresholds, neutral copy and legacy responses.

Existing Socket.IO WebAssembly dry-run, Cupertino-font and Android Kotlin-plugin
migration warnings remain nonblocking. The initial sandboxed Flutter test could
not access its SDK lockfile; the authorized cache-access rerun passed. No unrelated
Auth0 analyzer error was observed. The default opt-in skips are not device passes.

Reload/restart Flutter through the existing launcher to pick up the new wording.
The freshly compiled APK was not installed with different runtime defines, so the
phone's existing Auth0/Firebase/backend configuration remains intact.

## Commit message

```text
fix(ai): keep conflicting rotation-only item detections under review

- inspect original scene context before searching rotated target matches
- preserve upright evidence when rotated scores replace representative detections
- flag overlapping cross-type contradictions without lowering thresholds
- distinguish uncertain item types from document and photo-quality warnings
- add generic policy regressions and responsive Flutter wording tests
- recheck public-photo failures without claiming independent accuracy
- record actual Android agreement, messaging, role and pagination viewing checks
```
