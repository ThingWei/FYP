# MyKad scanner frame and quality consistency fix

Date: 2026-10-07. Scope: scanner geometry, capture settings, shared AI quality
gating and actionable rescan reasons. No model retraining, KYC auto-approval,
credential changes or unrelated Auth0 changes.

## Findings

The visible Flutter guide subtracted equal margins from an already sized
1.58-ratio container, changing the actual border ratio to approximately 1.74 at
358 logical-pixel width. The camera preview was tightly expanded into the
available space instead of explicitly preserving its oriented aspect ratio.
The backend alignment rectangle was unrelated to the displayed card guide.

Resolution validation accepted a 640x480 image but rejected its 480x640 rotated
copy. Live readiness omitted resolution gating although final verification
included it. Final rescan messages combined blur, lighting, resolution and glare
into a generic sentence even when only one flag failed.

The user's reported 98% front / 97% back values are **detector confidence**, not
measured OCR accuracy, sharpness or identity-authentication confidence. A detector
can confidently locate a card whose text is unreadable.

## Changes

- `KycScannerViewport` fits the oriented preview without stretching or cropping.
  Captured review uses `BoxFit.contain` rather than cropping with `cover`.
- `kycDocumentGuide` defines the **visible border** at width/height ratio 1.586,
  centered within the actual preview. Maximum width is 88% of preview width;
  maximum height is 68% of preview height. No internal margin alters the ratio.
- The AI guide uses the same geometry on decoded image dimensions and exposes
  optional normalized `guide_box` coordinates. Existing Express frame forwarding
  needs no request changes. Flutter currently calculates the matching guide
  locally; physical preview/still-image aspect alignment needs device validation.
- Move-closer/farther checks use occupancy of that guide (65% minimum area,
  105% maximum); alignment has a 0.01 normalized edge tolerance. This avoids the
  old fixed whole-image area requirement that was unattainable inside a typical
  portrait guide. These are capture heuristics, not trained/calibrated metrics.
- Camera preset changes from medium (~480p) to high (~720p); requested JPEG
  quality changes from 70 to 90. Actual supported dimensions depend on the device.
  Capture bytes are still uploaded unchanged, not resized or upscaled.
- Usable resolution checks `long edge >= 640` and `short edge >= 400` independent
  of orientation.
- `_quality_issues` is shared by live readiness and document submission. A frame
  cannot become ready with any submission-quality failure, regardless of detector
  confidence. The same checked JPEG bytes are retained on automatic capture.
- Live guidance identifies the first issue. Final submission reports all issues
  per image, with `MyKad front`/`MyKad back` labels for the existing ordered
  two-image upload flow; quality metadata includes stable issue codes. These
  labels refer to submitted positions, not an assertion that OCR verified the side.
- Scanner copy says `Detection confidence` and explicitly distinguishes that
  percentage from sharpness and identity validity.

Existing blur, brightness and glare thresholds were **not lowered** to force
acceptance: Laplacian variance <75, mean brightness <40 or >225, and bright-pixel
fraction >0.12 remain. These checks currently measure the entire decoded image,
so background, compression, resolution and naturally bright card regions can
affect them. They are not a calibrated real-world MyKad quality classifier.

## Validation

- `python -m pytest tests -q`: **150 passed**, two dependency deprecation warnings.
  New synthetic-image tests cover portrait/landscape resolution parity, guide
  ratios, good-frame readiness, all quality-failure families, side-specific
  rescan messages, detector-unavailable behavior and rejection at **98% detector
  confidence** when an image is blurry.
- `flutter test --no-pub -r expanded`: **135 passed, 2 skipped**. Scanner widget
  checks at 360/390 logical-pixel screen widths verify preview/border geometry
  and captured-image guide removal. No real camera/device was used.
- Direct Dart analysis of changed scanner/test files: **no issues**.
- Full `flutter analyze`: two **existing** undefined named parameters in
  `test/auth0_persistence_test.dart` (`latestLinkProvider`,
  `mobileLinkPollInterval`) against the conditionally selected Auth0 stub. The
  existing HEAD stub lacks these parameters; unrelated code was not modified.
- `flutter build web --no-pub`: **passed**. Existing Socket.IO WebAssembly dry-run
  incompatibility and Cupertino font warnings remain; this was a normal JS build.
- Changed Dart files formatted; `git diff --check` passes.

## Phone verification still required

Restart/reload the AI process and fully restart the Flutter app (not only hot
reload), then scan **new** front/back photos. Previously uploaded low-quality
photos do not improve when the code changes. No detector retraining is required
for this fix, and the API need not restart for unchanged forwarding code.

Check that the preview is not stretched, the border fits the card, and lighting,
focus and glare guidance is understandable. Hold steady until three consecutive
ready frames. If quality still fails, inspect non-identifying quality values
(`width`, `height`, `blurVariance`, `brightness`, `glareRatio`, `issues`) rather
than assuming a high detection percentage proves a sharp image. Do not share IC
numbers, OCR text or unredacted identity images. Actual phone focus behavior,
preview/still-image alignment and quality-threshold calibration are not proven
by synthetic regression tests. Manual/admin review requirements remain intact.

## Follow-up: repeated "Move document closer"

A read-only local probe using a synthetic gray image found that the service on
port 8001 still returned `adapter=opencv-document-yolo-v1`, with no `guide_box`
and no `quality.issues`, although updated source included both. The running
process had not loaded the geometry/quality changes. This explains a concrete
way the app can show a new guide while the service uses the old whole-frame
size thresholds; actual user-photo coordinates were not available for audit.

The updated service now identifies its frame contract as
`opencv-document-yolo-v2`. Flutter refuses automatic capture from an available
service reporting an older/missing contract, clears stale confidence feedback,
and shows an explicit AI restart instruction with a Retry button. It does not
weaken size or quality thresholds and does not bypass an outdated service via
the manual-capture button. Detector-unavailable/manual fallback remains separate.

Follow-up validation: **28 focused AI tests passed**, **8 focused scanner Flutter
tests passed**, changed-file analysis clean. The earlier full-suite/build results
above apply to the preceding geometry/quality patch; physical camera testing
after service restart remains required.

The launcher reuses an already healthy AI service rather than reloading its
code. Stop the current AI terminal with Ctrl+C (or the original launcher that
owns it), then restart. Do not start a second server on the occupied port.
For standalone development, use:

```powershell
cd C:\Users\weith\FYP\services\ai
.\.venv\Scripts\python.exe -m uvicorn app.main:app `
  --host 127.0.0.1 --port 8001 --reload --reload-dir app
```

`--reload-dir app` limits development code watching to application sources,
not private identity datasets/training outputs. Restarting only Flutter or
Express does not reload the separately running AI Python process. Restart the
updated Flutter app as well to load its new contract guard.

## Launcher update

`apps/renthub_flutter/run-renthub.ps1` now starts new AI services with
`--reload --reload-dir app` by default. Existing API, blockchain, Auth0 and device
arguments are unchanged. Use `-NoAiReload` for a stable/demo run without automatic
code reload. Models/datasets are intentionally not watched; changing loaded
model artifacts still requires restarting AI.

AI health publishes `document_frame_contract` from the same constant used in
frame responses. The launcher reuses only a healthy service reporting the current
v2 contract. It rejects outdated health responses, or an occupied port without
compatible health, **before spawning another AI process**. Its error explains
how to stop the original service. It does not automatically terminate another
terminal's or launcher's server. A compatible service started externally is
reused and remains under its original owner's reload/shutdown control.

Shutdown records the initial AI supervisor's PID and start time and uses verified
PID-tree cleanup (`taskkill /PID <owned-root> /T /F`) for processes this invocation
started. This covers the Windows virtualenv Python wrapper, Uvicorn reloader and
its worker. A reused PID is left untouched; no process is terminated by the broad
`python.exe` image name. Existing/reused AI services are never cleaned up by this
invocation. Cleanup warns rather than masking the original launcher error if it
cannot complete. Force-closing the entire PowerShell host may prevent `finally`
from running; prefer normal launcher exit/Ctrl+C. A root that already exited is
not used to guess ownership of unrelated/orphan processes.

Usage from `apps/renthub_flutter`:

```powershell
.\run-renthub.ps1
.\run-renthub.ps1 -Device <ANDROID_DEVICE_ID>
# Optional stable run:
.\run-renthub.ps1 -NoAiReload
```

Stop any older service once before switching to the updated launcher; repeatedly
running the launcher will not replace an independently running old server.

Validation:

- PowerShell launcher parsed without errors; standalone readiness, reload-option
  and cleanup/PID-reuse guard tests passed.
- Disposable integration test confirmed a created Python root/supervisor/child
  tree was fully stopped. It did **not** start/stop any actual RentHub service or
  bind port 8001.
- Full AI regression suite: **150 passed**, two dependency deprecation warnings.
- Full launcher execution with the user's credentials/services was deliberately
  not run; no .env values, running API, AI, MongoDB or blockchain were modified.

Reproduce launcher checks without invoking its application body:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\test\run_renthub_launcher_test.ps1
# Optional disposable process-tree integration check (Windows process inspection required):
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\test\run_renthub_launcher_test.ps1 -Integration
```

The execution-policy setting is limited to that test PowerShell process; no
system-wide policy change is needed or performed.
