# MyKad readability, screen screening and account binding result

Implemented and verified: 13 October 2026.

Current follow-up adds enclosing-phone screening and one-MyKad-per-verified-account binding. Scanner contract: `opencv-document-yolo-v6`; required-field contract: `mykad-required-fields-v2`; API capability: `mykad-screen-account-binding-v1`.

**Local rollout is not yet enabled:** the bounded read-only audit found the identity key unset and one approved legacy MyKad account with no usable fingerprint. No secret, live binding or approval was changed. See setup and legacy coverage below.

## Issues addressed

The old final-capture check required a MyKad front heading and formatted IC number, but not readable name/address regions. Rear capture required registration/address text, not a readable holder IC number or comparison with the selected front. Final submission appended different holder numbers to manual-review reasons, so the API could still place the attempt in the administrator approval queue.

Mandatory MyKad readability/pair validation now runs for final scanner checks and submitted image pairs. A clear card-detection percentage alone can never authorize **Use Image**, submit an approvable MyKad attempt or satisfy administrator approval.

### Follow-up: front guidance appearing during a back scan

The back's mandatory fields contain only `back_identity_number`; it does not require a name/address. However, final back validation also rechecks the stored front bytes. A failing front check previously supplied its generic “name, IC number and address” guidance without identifying which photo failed, making a correct back scan look responsible.

Pair responses now provide safe `failedSide` metadata. A front failure explicitly refers to the **saved front photo**, with retry/replace guidance; back-number failures retain back-specific wording. Back scanner recovery offers **Review front photo**, returning to the unchanged document draft so the front can be reviewed/replaced. Pair mismatches remain blocked and still require the same identity on both sides; no readability or screening requirement was removed.

Initial capture now uses the same floor/ceiling pixel-bound rounding as saved-front/submission checks. Previously its right/bottom edges were truncated instead, allowing a one-pixel crop difference to influence field-detector/OCR results. This inconsistency is fixed; it has **not** been established as the cause of this user's particular physical-card rejection. No new real-card image was inspected. Models may still reject a genuine but insufficiently readable capture; real-device verification remains necessary.

Follow-up checks: 335 full AI tests passed; 19 focused API readability tests passed; 41 focused Flutter KYC tests passed; application analysis passed. Mobile recovery tests cover 360/390 pixels at 1.3x text scaling, blocked use, retry and front-review controls. Prior unrelated Auth0 test-analysis errors remain unchanged.

### Follow-up: replacing the front after a matched pair

Root cause: front removal/replacement already cleared `pairChecked`, but the form's submission gate checked only the number of photos. Adding a new front alongside the retained old back did not run a new draft-pair check. Final submission already reanalysed the current uploaded pair; the missing check was immediate draft feedback/gating, not permission to approve a known mismatch.

The draft match now belongs to a specific generation and ordered front/back references. Removing/replacing either side invalidates it. The back keeps its explicit slot/label. The form checks the current pair after adding a replacement front or completing manual uploads; **Submit for Review** remains disabled until the current pair is matched. Mismatch/unavailable responses keep both draft photos and offer replacement/retry. Late responses after removal, replacement or document-flow changes cannot restore the old match. A normal back scan that already compared its exact saved front retains that current match without an unnecessary duplicate OCR request.

New authenticated, read-only `POST /api/v1/users/me/verification/check-pair` accepts only distinct `frontDocumentRef`/`backDocumentRef` upload references. Express checks ownership and verification purpose, loads both stored images in front/back order, and reuses final AI validation. The response contains safe match status/guidance and checked references, not IC numbers, fingerprints or OCR. It writes no verification history, settings, approval or identity binding. Missing/outdated analysis fails closed. Final submission independently rechecks the current bytes; draft-check results are never accepted as approval authority.

API/launcher readiness now additionally requires `mykad-current-draft-pair-v1`. Restart the API and rebuild/restart Flutter through the launcher; no model retraining is needed. API tests reproduce matched old front/back, a different replacement front plus retained back, mismatched preflight and resubmission-required final submission. They also cover foreign/wrong-purpose/missing refs, authentication, unavailable/legacy analysis, client match claims and private/read-only output. Flutter tests cover removal/replacement, fresh requests, mismatch, unavailable retry preserving photos, old-response suppression, re-enabling only after a current match, and layouts at 360/390 pixels with 1.3x text scaling.

Latest verification: **310 API tests passed, 3 skipped; 45 focused Flutter KYC tests passed; app analysis, launcher checks, web and Android debug builds passed.** Full analysis still reports only the two pre-existing Auth0 test parameter errors below. AI code was unchanged in this replacement follow-up; its prior full run passed 335 tests. Real Android camera verification of the user's replacement scenario remains a handoff check; no real IC photos were added as fixtures.

### Follow-up: clear front photos rejected by required-field checks

The user confirmed the rejection was the name/IC/address message, not a blur/alignment warning. That message indicates missing field regions or inadequate field OCR; no new physical-card image was inspected, so the exact failing region/accuracy gain has not been measured.

Required-field detection now makes one 960-pixel inference retry if its normal 640-pixel pass misses a required region. It retains the same configured detection floor (default 0.50), checks original-image bounding boxes and never substitutes guessed fixed-layout crops. Only missing classes are recovered; unresolved detections still block acceptance. Predictor calls remain serialized and reset the first-pass size explicitly.

For detected fields whose first sharpened OCR pass is unreadable, one bounded alternative uses plain grayscale, aspect-preserving enlargement (maximum 3x, bounded target dimensions) and a blank border. It uses **only the same field pixels**, with no neighbouring scene text or invented details. Successful fields are not retried. OCR confidence remains **0.60**. Names/addresses must have a coherent sufficient reading from one pass; two inadequate passes cannot be assembled into a purported readable address. All confident IC candidates and UI cues are retained: ambiguity/obstructions cannot be erased by retrying. Missing models, missing regions, low-confidence details, covered text, wrong sides, screen copies and mismatched pairs remain blocked.

Safe field evidence adds `ocrRetryUsed` and `failedFields`; rescan guidance identifies which required details remain unreadable. No field text or IC number is added to scanner diagnostics. No training, model downloads, new dependencies, secret changes or live identity mutations were performed. Restart the AI service and retest a permissioned physical card, a covered address, the prior screen-copy example and a mismatched pair. A genuine-card false-rejection rate cannot be claimed from synthetic fixtures alone.

Verification for this follow-up: **347 full AI tests passed; 96 focused AI readability/screen/capture tests passed; 39 focused API readability/binding tests passed.** Flutter/API implementation code did not change in this follow-up, so prior app analysis/build results below belong to the earlier replacement work. New tests cover confident OCR recovery, below-threshold retry rejection, no merging of weak address readings, obstruction/ambiguity retention, missing detections, bounded pixel transforms and unchanged detector confidence.


### Follow-up: replacement front still enabled Use Image

The user clarified this occurred on the **scanner Use Image screen**, not the two-photo form. The previous fix rechecked the current pair after upload, but front capture itself only validated front readability. A readable different front could enable **Use Image** even though the subsequent form pair check would reject it. Readability was not proof of matching identity; the missing early counterpart comparison is now implemented.

- When a saved back is retained, the front scanner sets `requirePairMatch=true` and submits `backDocumentRef` for final capture validation. Express verifies ownership/document purpose, privately loads those back bytes and sends internal `reference_back` to FastAPI. Client-supplied IC numbers remain forbidden.
- FastAPI checks the replacement front and saved back, in front/back order, then compares their independently read number-region values. A mismatch/unreadable/unavailable saved side blocks **Use Image** immediately. The normal first front capture still requires no absent back image.
- **Review back photo** is available for a mismatch or failed saved-back check. To change the MyKad, return and remove the old back, then capture both new sides. Cancel/review navigation preserves the draft; no mismatched front is silently uploaded.
- Pair matching explicitly requires two canonical 12-digit private values and a valid front-number format. `None == None`, empty strings and malformed private values cannot establish a match, even if surrounding metadata incorrectly says accepted. No numbers are added to public responses/logs.
- Post-upload draft rechecking, generation/reference guards, final submission and administrator approval checks remain. Screen screening and OCR confidence thresholds are unchanged.

Contracts are coordinated: AI/Flutter/launcher use **`opencv-document-yolo-v6`** and API readiness additionally requires **`mykad-bidirectional-capture-pair-v1`**. Launcher regressions reject v5 and compare the helper with the Python service constant. A pre-change read-only health check confirmed the running API had the earlier draft-pair capability and AI reported **v5**. Fully restart/relaunch the stack and app to use v6; hot reload of an already-open scanner is not sufficient.

Latest verification: **359 full AI tests passed; 108 focused AI readability/screen/capture tests passed; 315 API tests passed, 3 skipped; 51 focused Flutter KYC tests passed.** App analysis, launcher checks, web and Android debug builds passed. Full analysis retains only the two pre-existing Auth0 test errors. Tests cover replacement front versus matching/different saved-back numbers, failed saved-back checks, missing private numbers, owned-back API forwarding, rejected foreign/wrong-purpose references, front-only reference rules, actual scanner route wiring, disabled Use Image and back recovery at 360/390 pixels with increased text size. Real-camera verification remains pending; no real identity photos were committed or used for training.

Retest: match A-front/A-back, remove A-front, scan B-front while A-back remains. **Use Image must stay disabled**, with mismatch guidance and back-photo recovery. Remove A-back to change identity intentionally, then scan both B sides. Repeat with a matching replacement and unavailable OCR/model checks.

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

Full-scene phone detection now uses the installed item YOLO detector, shared predictor lock and compatible phone vocabulary. A detected phone blocks capture only when **all** these conditions hold: confidence >=0.85, at least 90% of the MyKad box enclosed, phone area >=1.5 times card area, and long/short aspect ratio >=1.8. Nearby/non-enclosing phones do not reject a physical card. Known UI phrases fragmented by whitespace/line breaks are normalized without lowering the 0.60 OCR threshold or using generic fuzzy text similarity.

The required check runs during final capture and submission, not the lightweight live alignment loop. Missing/incompatible artifacts or inference failure produce an unavailable check and retry guidance, not a physical-card pass. No model download is attempted. Structured `screenCopy.phoneScreen` includes method/status and, for a detected enclosing phone, confidence/containment/area/aspect evidence only. **Use Image** stays disabled with: “Scan your physical MyKad, not an image on another screen.”

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
- FastAPI scanner contract is now `opencv-document-yolo-v6`; mandatory validation method is `mykad-required-fields-v2`. Older contracts and missing phone-screen evidence cannot satisfy Flutter or API approval guards.
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
| Image 1 (1.20.58 PM) | `accepted=false`, `screen_copy`; phone confidence 0.8531, containment 100%, area ratio 4.6385, aspect ratio 2.0095 |
| Image 2 (1.20.57 PM) | `accepted=false`, `screen_copy`; phone confidence 0.8955, containment 100%, area ratio 4.6338, aspect ratio 2.0137 |

Independent OCR browser cues remained insufficient in both screenshots. The new enclosing-phone check rejected both before required-field OCR. These are screenshots of the scanner UI, not the original camera bytes; this proves the observed reproduction is blocked, not that all screen copies are detected. Android camera verification remains necessary.

## One-MyKad-per-account policy

- The existing keyed HMAC format/namespace is reused. Only a successfully validated matching pair supplies identity data. Each validated MyKad history attempt saves a private `identityFingerprint` snapshot.
- Submission checks another verified account for early feedback. Pending attempts do not reserve an identity; two different accounts may submit the same pair before either is approved.
- Approval uses the latest pending attempt's private snapshot, not mutable profile/licence-comparison data. An atomic conditional MongoDB update records approval and `verifiedIdentityFingerprint` together. A unique partial index named `verified_mykad_identity_unique` covers populated string values.
- Two simultaneous approvals for different accounts cannot both bind the same fingerprint. Stale attempts, missing/current-key-incompatible snapshots, missing key/index and existing conflicting bindings fail clearly.
- Same-account resubmissions after rejection/resubmission use fresh snapshots. Existing pending-attempt and already-approved resubmission restrictions remain; no second identity or account is created. Renter/Owner roles share the account.
- Duplicate responses say: “This MyKad is already linked to another account. Use your existing account or contact support.” They reveal no other account identifier, name or email.
- Suspension, banning and deactivation retain the binding. No release, identity transfer, merge or key rotation is implemented.
- Hidden fields are excluded from normal Mongoose selections and explicitly removed from JSON serialization, including history snapshots. API response regressions cover own/admin views. Audit output contains aggregate counts only, never raw IC numbers/fingerprints. No raw OCR is added to logs.
- Approved legacy accounts retain approval. Readable screen checks, matching numbers and uniqueness do **not** establish authenticity, rightful ownership or government verification. Administrator review remains mandatory.

## Stable key and index setup

1. If a matching key already exists in another environment, recover/reuse that exact key. Do not generate a replacement for a populated fingerprint database.
2. For a first-time local setup only, run the following yourself in PowerShell. It copies a random 64-character secret to your local clipboard without printing it:

   ```powershell
   node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))" | Set-Clipboard
   ```

3. Paste it into the existing `KYC_IDENTITY_MATCH_SECRET=` entry in `services/api/.env`. This file is git-ignored. Keep a secure backup; clear the clipboard afterward. Never paste the value in chat, commit it, print it in reports, or put it in Flutter flags. Minimum accepted length is 32 characters; random bytes are preferable to a memorable password.
4. Restart the API and AI through the launcher, then run `npm.cmd run preflight` from `services/api`. The added `mykad_identity_binding` check must pass. The normal User model declares the unique index; approval/submission checks inspect it and never silently bypass a missing index.
5. If index auto-creation is disabled in your deployment, have the database maintainer create precisely this index on `users`, then rerun preflight:

   ```javascript
   db.users.createIndex(
     { verifiedIdentityFingerprint: 1 },
     { name: 'verified_mykad_identity_unique', unique: true,
       partialFilterExpression: { verifiedIdentityFingerprint: { $type: 'string' } } }
   )
   ```

   Do not drop other indexes, choose duplicate winners, or use `syncIndexes` as a bulk cleanup. Index/key problems block new MyKad approvals, not revoke existing ones.

Once bindings exist, changing the secret requires a separately reviewed migration. Current-key checks reject incompatible populated bindings and usable approved legacy fingerprints rather than silently creating another namespace.

## Legacy audit and opt-in binding

From `services/api`:

```powershell
# Default: bounded, read-only; no index/collection initialization or writes.
npm.cmd run audit:identity-bindings -- --limit=1000

# Only after reviewing nonconflicting candidates and key/index readiness:
npm.cmd run audit:identity-bindings -- --limit=1000 --apply --acknowledge-reviewed
```

Limits are whole numbers 1–10,000; truncated apply refuses all writes. The command uses a raw MongoDB client so importing schemas does not initialize Mongoose indexes. Applying requires a current stable key, correct unique index and explicit review acknowledgement. Missing fingerprints are skipped; duplicate groups are quarantined, never assigned a winner. Conflicting stored/key-incompatible fingerprints prevent apply. Each write rechecks approval/fingerprint state and conflicting owners; concurrent conflicts are counted without overwriting another account. Repeated application is idempotent.

Actual configured-database audit (13 October 2026): **1 approved account inspected, 0 already bound, 1 missing usable fingerprint, 0 detected duplicate groups, 0 writes; key configured: false; not truncated.** “0 detected duplicates” does not prove uniqueness when fingerprints are absent. This legacy identity cannot be reconstructed from masked evidence and remains a detection gap until an authorized reviewed re-enrolment/migration supplies a current-key fingerprint. Existing approvals were not revoked and the opt-in apply command was **not** run on the live database.

## Verification

| Check | Result |
| --- | --- |
| Full AI suite | 359 passed |
| Focused AI screen/readability/capture suites | 108 passed |
| Full API suite | 315 passed, 3 skipped, 0 failed |
| Focused Flutter replacement/readability/scanner/account/driving/identity-access suites | 51 passed |
| Application analysis (`flutter analyze lib`) | Passed |
| Full Flutter analysis | Two pre-existing Auth0 test errors |
| Web build | Passed |
| Android debug APK build | Passed |
| Standalone PowerShell launcher regression checks | Passed |

New tests cover required-field presence/confidence, obscured address and watermark-only content, Unicode names, full-scene screen cues, single-cue limits, number ambiguity/normalization/leading zeros, invalid-date rear conflicts, unavailable models/OCR, fractional YOLO bounds, frame/reference pair gating, mandatory final submission, upload ownership/purpose, malformed/legacy approval evidence, retained-photo upload retry, stale draft generations and front/back slot identity.

Follow-up regressions cover enclosing/nearby phone geometry, exact thresholds and just-below boundaries, fragmented browser phrases, missing/incompatible phone artifacts, final-submission parity, missing phone metadata/old contracts, friendly private errors and screen-copy guidance at both mobile widths. API binding tests cover concurrent approvals, two pending accounts, duplicate submissions, same-account retries, attempt/profile snapshot independence, stale attempts, missing key/index, key mismatch, private serialization and retained bindings. Legacy tests cover read-only/dry-run preservation, duplicates, explicit review, limits, index/key checks, conflicting snapshots and repeat application. Isolated API tests use temporary MongoDB, not the live database.

Flutter checks include disabled actions and recovery layout at 360/390 logical pixels with 1.3x text scaling. Old tests that treated heading-only captures or unreadable back numbers as sufficient were updated to the strict policy; classification/risk tests isolate mandatory checks with synthetic evidence fixtures, while the new readability suite tests that pipeline separately.

Unrelated full-analysis errors remain:

- `test/auth0_persistence_test.dart:41`: undefined `latestLinkProvider` named parameter.
- `test/auth0_persistence_test.dart:43`: undefined `mobileLinkPollInterval` named parameter.

Existing warnings remain for Starlette/Click deprecations, socket_io_common WebAssembly compatibility, Cupertino icon font availability and Android plugin Kotlin Gradle migration. Standard web and Android debug builds succeeded. Full-project Flutter test cleanliness is not claimed while the existing Auth0 test compilation errors remain.

## Restart and Android walkthrough

### Launcher compatibility follow-up

The earlier launcher mismatch required v3 after the AI/scanner moved to v4. This follow-up upgrades both sides together to **v6**, retains `mykad-readability-pair-v1` and adds required API capability `mykad-screen-account-binding-v1`. Readiness errors report observed/required scanner contracts.

Launcher tests compare its compatibility helper with the actual Python contract constant, explicitly reject v4/v5 and unhealthy responses, and check required API capabilities. They passed using `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\run_renthub_launcher_test.ps1` from the Flutter directory. This changes execution policy only for that test process, not the user's saved policy. Tests do not read credentials, start services or kill real processes. A full live launcher run was not performed.

Restart **both Express API and FastAPI AI services**, then rebuild/restart Flutter using the existing RentHub launcher. Old processes can retain old schemas/model caches; hot reload of Flutter alone is insufficient. FastAPI health should show `document_frame_contract: opencv-document-yolo-v6`, and API readiness should include `mykad-readability-pair-v1`, `mykad-screen-account-binding-v1`, `mykad-current-draft-pair-v1` and `mykad-bidirectional-capture-pair-v1`.

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
10. Rephotograph a phone displaying the supplied Google page. Confirm the enclosing-phone result and disabled **Use Image**; repeat with a nearby phone not containing the physical card. Test a tightly cropped readable copy and document limitations honestly.
11. After key/index setup, use permissioned test identities/accounts to verify two pending submissions are possible, only one can be approved, a duplicate receives private guidance, and a rejected attempt can be retried on its own account. Never use real personal IC data as committed test fixtures.
12. After matching two photos, remove the front and add a front with another number. Confirm the retained back stays labelled **MyKad back**, a fresh current-pair check runs and a mismatch disables submission. Replace the incorrect photo with the correct side, retry and confirm only a fresh match re-enables submission.

A hands-on Android physical-card/screen-copy walkthrough was **not performed** in this workspace. It remains necessary to assess real camera readability, false-negative rates and response latency. Automated fixtures verify control flow, not independent OCR accuracy or authenticity.

## Commit message

```text
fix(kyc): screen phone copies and bind verified MyKad to one account

- add enclosing-phone geometry screening with installed item YOLO
- normalize fragmented browser cues while preserving OCR confidence thresholds
- fail closed on missing screen artifacts and outdated mandatory evidence
- save private per-attempt fingerprints and atomically bind MyKad approval
- enforce a unique partial identity index and guard key/index readiness
- allow competing pending requests while preventing duplicate verified accounts
- retain bindings after account restrictions and preserve legacy approvals
- add bounded read-only legacy audit and reviewed opt-in binding command
- coordinate scanner/API/launcher contracts and friendly private guidance
- identify saved-front failures during back scans and provide front-photo recovery
- use consistent card-crop rounding for capture and saved-image rechecks
- recheck retained MyKad drafts after photo replacement and gate submission on the current pair
- add read-only owned-upload pair checks and ignore stale match responses
- compare replacement front captures against the saved back before enabling Use Image
- reject missing private number equality and coordinate bidirectional v6 scanner contracts
- retry missed small fields and unreadable field OCR without lowering confidence floors
- retain obstruction/ambiguity evidence and show targeted unreadable-field guidance
- add AI, API, Flutter and launcher regressions for screening and binding races
- document screenshot results, stable-key setup, legacy gaps and device checks
```

