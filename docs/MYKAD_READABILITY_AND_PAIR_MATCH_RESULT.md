# MyKad readability and front/back matching result

Implemented and verified: 13 October 2026.

## Issues addressed

The old final-capture check required a MyKad front heading and formatted IC number, but not readable name/address regions. Rear capture required registration/address text, not a readable holder IC number or comparison with the selected front. Final submission appended different holder numbers to manual-review reasons, so the API could still place the attempt in the administrator approval queue.

Mandatory MyKad readability/pair validation now runs for final scanner checks and submitted image pairs. A clear card-detection percentage alone can never authorize **Use Image**, submit an approvable MyKad attempt or satisfy administrator approval.

## Delivered behavior

### Required fields

The existing whole-card detector and combined field detector are reused without retraining or new dependencies:

- Front: MyKad heading/side, IC-number format, identity-number region, name region and address region.
- Back: MyKad rear/registration evidence and identity-number region.
- Field detection uses the existing `MYKAD_FIELD_DETECTION_THRESHOLD` (default 0.50).
- Whole-card detection uses `DOCUMENT_DETECTION_THRESHOLD` (default 0.65).
- Only OCR lines with finite confidence at least 0.60 contribute required details.
- Names accept Unicode letters and legitimate punctuation; there is no person-name blacklist.
- Name/address extraction is spatial, not dependent on printed NAME/ADDRESS labels.
- Address evidence requires at least three readable words in its detected field; a standalone state or capture overlay does not count. Missing address components are never guessed. This is a readability floor, not postal-address correctness/completeness verification.
- Known capture-overlay/watermark-only lines do not supply name/address content. A privacy watermark elsewhere is not itself a rejection.
- Missing or unreadable fields require rescan. Unavailable/misconfigured models or OCR fail closed with retry guidance.
- Fractional YOLO boxes are rounded to valid NumPy pixel bounds.
- Full-scene and field OCR use uncropped preprocessing: the old automatic document crop must not hide browser context or crop away selected-field text.
- Whole-card predictor calls are serialized to avoid concurrent mutation of its retained predictor state.

The mandatory field-detector loader is independent of the optional synthetic-risk classifier. Disabling/missing advisory risk classification cannot bypass readability checks; it also does not unnecessarily disable a functioning mandatory field detector.

### Screen-copy evidence

Full-scene OCR looks for independently readable browser/image-search cues, including visual-search text, browser context, image-result navigation and standalone Share/Save actions. Rejection requires at least two cue groups, including a strong browser/search group.

One icon, watermark, name, weak OCR line or risk score does not prove a screen copy. Readable browser overlay text inside a required field also prevents that field from being treated as unobstructed.

This is evidence-based screening, not screen-replay/liveness certification. Cropped or poorly readable screen copies may have no recognizable UI cues. Their missing/unreadable required fields still block acceptance; a readable copy without detectable context may remain indistinguishable and requires administrator scrutiny.

### Pair matching

IC candidates are extracted only from the detected identity-number regions. Spaces/hyphens are normalized; leading zeros are preserved. No letter-to-digit guessing is performed.

Each side must yield exactly one confidently readable 12-digit candidate. Multiple candidates, missing text and low-confidence text require rescan. Different numbers require rescan—not manual approval. A conflicting rear number is not discarded just because its birth-date segment is invalid.

Matching sides produce structured `matched` evidence and remain **pending administrator review**, never automatic identity approval.

## API and client contracts

Existing endpoint paths are preserved.

- `POST /api/v1/users/me/verification/scan-frame` accepts optional `frontDocumentRef` only for a final MyKad back check.
- The reference must be an owned `upload://UPL-...` verification-document upload. Foreign, missing, wrong-purpose and remote references are rejected before AI analysis.
- Express reads the stored front bytes and sends internal `reference_front` image data to FastAPI. A client-supplied reference IC number is not accepted.
- Without a usable front reference, the back scan cannot enable **Use Image**.
- FastAPI scanner contract is now `opencv-document-yolo-v4`; mandatory validation method is `mykad-required-fields-v1`.
- Scanner `capture_validation` includes required-field flags, screen-copy flags and back `pairMatch` evidence. It contains no field text/full IC number.
- Submission evidence includes `mandatoryMykadValidation` and `mykadSidesConsistent`.
- API readiness adds `mykad-readability-pair-v1`, retaining existing capability names.
- Older AI scanner contracts are rejected by Flutter with restart guidance.
- Final capture requests have a bounded 75-second AI timeout and 80-second Flutter check timeout. MyKad submission analysis has a 90-second AI timeout to accommodate CPU OCR/field inference. Live lightweight frame checks and other document-analysis timeouts retain existing behavior.

The API requires complete, current mandatory evidence for MyKad submission and approval, including matched sides, required readable fields and no detected screen copy. Missing/malformed evidence and `mykadSidesConsistent=false` fail closed. Uploading files or bypassing Flutter does not bypass final checks.

Failed attempts retain protected history and use `resubmission_required`, including unavailable mandatory analysis. An old pending attempt lacking current evidence cannot be approved; request a new submission. Existing approved identities are not migrated, automatically revoked or silently re-evaluated.

The existing identity fingerprint is derived only after a valid MyKad pair; raw OCR/IC text remains masked/removed from stored evidence and scanner responses. Raw AI transport errors are removed from presented/stored evidence. No submitted private images/crops are saved by the new AI module.

### Flutter draft and recovery

MyKad images have explicit front/back slots. Removing the front never relabels a retained back as front. Replacing/removing the front invalidates draft pair confirmation, and final submission rechecks both images. Generation checks ignore late scan/upload replies after draft changes, rescan and document-type changes.

Front guidance says **Required details are readable**. A matched back says **Front and back numbers match**. Both retain **Administrator review is still required**.

Failed mandatory checks keep **Use Image** disabled, while rescan/retry remain available. Failed capture uploads retain checked bytes in a preview with explicit **Retry photo upload**. Busy controls reset after failure and prevent competing upload edits. Existing successfully uploaded references are retained on failed scans/submissions.

After resubmission is required, a draft image can be detached/replaced even if its upload is protected by verification history. The API still refuses deletion of that historical file; only the temporary draft reference is removed. Other upload failures are not suppressed.

Passport and driving-licence/MyJPJ policies remain unchanged. In particular, the MyKad physical-card policy does not prohibit the existing administrator-reviewed MyJPJ screenshot workflow.

## Private screenshot reproduction

Both user-supplied screenshots were inspected read-only using the installed whole-card/field models and EasyOCR. No screenshots, crops, full OCR strings or document numbers were committed, copied into datasets or used for training.

| Provided image | Safe observed result |
| --- | --- |
| Image 1 (1.20.58 PM) | `accepted=false`, `unreadable_fields`; required name/address regions were not detected |
| Image 2 (1.20.57 PM) | `accepted=false`, `unconfirmed`; required front heading/number evidence was not read confidently |

Screen-copy cues were **not detected** confidently in these low-resolution screenshots. They were blocked by required-detail validation; this must not be reported as successful screen-replay detection. These are screenshots of the scanner UI, not the original camera bytes, so this check is not a substitute for the Android camera walkthrough.

## Verification

| Check | Result |
| --- | --- |
| Full AI suite | 309 passed |
| Focused AI readability/capture/classification/field-risk suites | 117 passed |
| Focused API MyKad/user/identity-access suites | 60 passed |
| Full API suite | 286 passed, 3 skipped, 0 failed |
| Focused Flutter readability/scanner/account/driving/identity-access suites | 34 passed |
| Application analysis (`flutter analyze lib`) | Passed |
| Full Flutter analysis | Two pre-existing Auth0 test errors |
| Web build | Passed |
| Android debug APK build | Passed |
| Standalone PowerShell launcher regression checks | Passed |

New tests cover required-field presence/confidence, obscured address and watermark-only content, Unicode names, full-scene screen cues, single-cue limits, number ambiguity/normalization/leading zeros, invalid-date rear conflicts, unavailable models/OCR, fractional YOLO bounds, frame/reference pair gating, mandatory final submission, upload ownership/purpose, malformed/legacy approval evidence, retained-photo upload retry, stale draft generations and front/back slot identity.

Flutter checks include disabled actions and recovery layout at 360/390 logical pixels with 1.3x text scaling. Old tests that treated heading-only captures or unreadable back numbers as sufficient were updated to the strict policy; classification/risk tests isolate mandatory checks with synthetic evidence fixtures, while the new readability suite tests that pipeline separately.

Unrelated full-analysis errors remain:

- `test/auth0_persistence_test.dart:41`: undefined `latestLinkProvider` named parameter.
- `test/auth0_persistence_test.dart:43`: undefined `mobileLinkPollInterval` named parameter.

Existing warnings remain for Starlette/Click deprecations, socket_io_common WebAssembly compatibility, Cupertino icon font availability and Android plugin Kotlin Gradle migration. Standard web and Android debug builds succeeded. Full-project Flutter test cleanliness is not claimed while the existing Auth0 test compilation errors remain.

## Restart and Android walkthrough

### Launcher compatibility follow-up

The launcher initially still required scanner contract v3 after the AI/scanner moved to v4. Uvicorn therefore printed successful startup, but the launcher rejected every healthy v4 response and timed out. The launcher now accepts v4, requires the API's `mykad-readability-pair-v1` capability, and reports the observed/required scanner contracts on readiness failure.

Launcher tests compare its compatibility helper with the actual Python contract constant, reject old v3 and unhealthy responses, and check the new API capability. They passed using `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\run_renthub_launcher_test.ps1` from the Flutter directory. This changes execution policy only for that test process, not the user's saved policy. Tests do not read credentials, start services or kill real processes. A full live launcher run was not performed.

Restart **both Express API and FastAPI AI services**, then rebuild/restart Flutter using the existing RentHub launcher. Old processes can retain old schemas/model caches; hot reload of Flutter alone is insufficient. FastAPI health should show `document_frame_contract: opencv-document-yolo-v4`, and API readiness should include `mykad-readability-pair-v1`.

No `.env` credentials, trained artifacts, datasets or live user records were changed. No retraining is required for this fix.

Use an unverified/resubmission-required test account and permissioned documents:

1. Scan a clear physical MyKad front with its heading, IC number, full name and address visible. Confirm readable-details guidance.
2. Cover a required field: confirm **Use Image** stays disabled and targeted rescan guidance appears.
3. Scan its matching back: confirm pair-match guidance, then submit. Confirm pending administrator review, not automatic approval.
4. Substitute a different back IC number: confirm **Use Image** stays disabled. Repeat through file upload: confirm resubmission and blocked admin approval.
5. Make the back number unreadable: confirm rescan rather than a presumed match.
6. Try a screen showing browser/image-search controls; also test readable privacy-watermarked physical-card evidence. Inspect results without assuming all screen copies can be detected.
7. Replace/remove the front while retaining a back: confirm the back label remains correct and the pair is rechecked.
8. Interrupt photo upload: confirm retained preview and explicit retry, without losing the existing front reference.
9. Test AI outage/restart and normal model recovery. Confirm no manual/admin bypass of missing mandatory results.

A hands-on Android physical-card/screen-copy walkthrough was **not performed** in this workspace. It remains necessary to assess real camera readability, false-negative rates and response latency. Automated fixtures verify control flow, not independent OCR accuracy or authenticity.

## Commit message

```text
fix(kyc): enforce MyKad readability and front-back identity matching

- require spatial OCR for front IC, name/address and back IC fields
- inspect full-scene browser cues without treating watermarks as forgery proof
- compare normalized side numbers and require rescan for uncertain or mismatched pairs
- verify owned front-image references during final back capture checks
- fail closed on missing, legacy or malformed mandatory approval evidence
- preserve explicit front/back draft slots and checked-photo upload retries
- bump scanner contract and add AI, API and Flutter regressions
- document private screenshot results, restart steps and detection limitations
```

