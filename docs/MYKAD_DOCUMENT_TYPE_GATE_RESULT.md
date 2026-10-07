# MyKad submission document-type gate

Implemented 7 October 2026. This is document-type assistance, not MyKad authenticity verification, a counterfeit verdict, or a government identity check.

## Cause and scope

The whole-card detector is used to position a card for capture. Its closed-set training on MyKad front/back does not teach reliable rejection of every other card. A high detection confidence therefore does not prove that a credit card is MyKad.

Previously, unclassified OCR could produce `manual_review` and Express mapped every outcome except `rescan_required` to `pending`. A readable unrelated card could enter the ordinary identity review queue.

The submission fix runs through the existing Flutter -> Express -> FastAPI verification flow. A subsequent capture fix checks each MyKad image before enabling **Use Image**, as described below. No retraining, new dependencies, production database migration, or unrelated listing/pricing changes are required.

## Capture acceptance and front/back correction

The previous submission-only fix did not prevent selecting a captured image: the scanner returned bytes immediately when Use Image was pressed and discarded the detector class. This is now corrected.

- Flutter supplies the machine-readable expected side (`front` or `back`) for the selected slot through Express's existing scan-frame API. The detector's `mykad_front` / `mykad_back` label is checked during live framing. A wrong-side detection is not ready to capture.
- After three stable frames, the exact captured bytes receive a one-off `validateCapture: true` check. Live frames do not run EasyOCR; the captured card crop does. The result includes side/type validation metadata only, not raw OCR text or numbers.
- A front requires matching detector side, readable MyKad heading/type and valid-format IC evidence. A rear requires matching side plus registration/address OCR evidence. A rear's incidental mention of MyKad is allowed when registration text is present; a front heading alone is not valid rear evidence.
- Payment-card cues and other known document types fail the check even at 98% whole-card confidence. Unknown/low-confidence OCR, unknown detector labels, missing expected side, missing models, exceptions, timeouts and outdated contracts cannot enable Use Image.
- Use Image is disabled while checking and on failure. Rescan and Retry Image Check are available. Manual camera capture passes the same check; it cannot bypass it. Stale validation results after rescan/navigation cannot accept another image.
- Capture validation is not authenticity approval. The final submitted MyKad still requires administrator review. File-upload and final-submission behavior remain separate from scanner acceptance; the scanner does not claim to make an uploaded document genuine.
- The frame contract is now `opencv-document-yolo-v3`. The API advertises `mykad-capture-validation-v1`. The launcher requires both and reports an outdated occupied service instead of silently reusing it. OCR capture calls get at least 45 seconds (live frame and unrelated AI timeouts unchanged); Flutter releases its checking state after a 50-second timeout.

## Gate behavior

| Evidence on submitted MyKad images | AI result | Express document/attempt status |
| --- | --- | --- |
| Clear credit/debit/payment-card evidence, a passport or driving-licence heading, MyPR/MyTentera/MyKAS, student or membership card | `wrong_document` | `resubmission_required` |
| Front lacks positive MyKad heading/type evidence or a valid IC birth-date/number format; a side lacks readable OCR; not two sides | `rescan_required` / `unconfirmed` | `resubmission_required` |
| Plausible MyKad front with readable rear and no strong other-document evidence | Existing `manual_review` with `plausible_mykad` metadata | `pending` for administrator inspection |

Wrong-document cues use OCR lines with confidence at least 0.60. A payment logo or long number alone is not a hard wrong-document verdict. Unknown readable cards still request rescan when positive MyKad front evidence is absent. Low-confidence text is not used to claim that another document type was definitively detected.

IC text may use hyphens or spaces. Number-format/DOB validation is not proof that the number is issued, belongs to the submitter, or matches government records. `authenticityVerified` is always false. Plausible MyKad remains manually reviewed even if synthetic field-risk signals are low.

The API also prevents approval of known-invalid pending attempts, including legacy pending MyKad attempts explicitly identified as a different document type. They can still be rejected or sent back for resubmission. Newly blocked attempts do not establish an identity-match fingerprint. Review reasons are limited to the schema's 500 characters; complete AI reasons remain in protected evidence.

## Privacy and holder comparison

Wrong-document responses contain cue names and side/type metadata only, not OCR text, PANs, CVVs, names or identity numbers extracted from the wrong card. Rescan responses omit raw OCR text. Express continues its existing protected evidence handling and identity-number masking.

If only the front contains a readable IC number, `mykadSidesConsistent` is now null (not proven), rather than incorrectly true. If both sides supply the same valid-format number it is true; differing numbers are flagged for manual review. The rear must still be inspected by the administrator; absence of a strong wrong-document cue is not positive proof of a genuine MyKad rear.

## Validation

All automated fixtures use synthetic OCR and generated images, including a published test payment-card number. No private MyKad or actual payment-card images were used.

- Focused document-classification/field-risk tests: 59 passed.
- Full AI suite after capture changes: 182 passed, two dependency deprecation warnings.
- User/KYC and AI-client API suites against a disposable MongoMemoryServer/local fixture server: 40 passed with mock authentication, local storage, disabled external delivery/blockchain integrations, and the project's namespaced Auth0 claim names.
- Full Flutter tests: 138 passed, two pre-existing skips. Scanner-focused tests: 10 passed. Changed Flutter files analyze cleanly; launcher syntax, old-service rejection and compatibility tests pass.
- Flutter Web build passed; existing Socket.IO WebAssembly dry-run and Cupertino font warnings remain. A physical Android camera retest is still required; automated checks do not establish camera/OCR accuracy on real documents.
- Coverage includes payment front/back, MyKad front plus payment rear, licence/passport/other ID mismatches, unknown cards, missing/reversed/unreadable sides, invalid DOB format, low-confidence cues, privacy, spaced IC numbers, unconfirmed rear holder match, persisted resubmission status, fingerprint suppression, and blocked legacy approval.

## Limitations and rollout

- OCR evidence is a conservative heuristic, not a trained open-set classifier. Cards with convincing printed MyKad-like text may still require human inspection; no claim of perfect rejection is made.
- Final-submission AI/OCR/network outage behavior is retained: `unavailable` can enter manual review with an explicit warning (for example through file upload). It is not type-validated or auto-approved. Scanner **Use Image** now fails closed instead: an unavailable capture check must be retried or rescanned. Administrators must visually inspect protected images in the submission fallback.
- Existing historical attempts are not reprocessed or deleted. Results apply to new submissions; an old unavailable result stays unavailable until a fresh submission.
- No phone-camera end-to-end accuracy or real-world counterfeit detection was measured by the synthetic tests.
- Stop the current launcher normally, then restart it **and rerun/rebuild Flutter** to load the new scanner. Restart any separately started API/AI terminals too; do not start a second API on port 3000. In a new scan, the capture preview should show Checking before Use Image can enable. Back-in-front and front-in-back checks should show the selected-side guidance. A readable payment card should stay blocked.
- The administrator's pending filter excludes newly resubmission-required attempts; prior saved attempts are unchanged.

Suggested commit: `fix(kyc): validate MyKad type and side before enabling image acceptance`
