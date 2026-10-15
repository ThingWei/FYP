# Paid pending requests and listing photo selection

Implemented 15 October 2026. Existing uncommitted item-verification presentation
changes were preserved; no live booking/payment records were modified by this work.

## Paid requests and expiry

`expiresAt` is the deadline to complete payment, not the rental end date or an
Owner-response deadline. Unpaid requests retain the configured 60-minute default.
After successful demo payment, requests remain pending for Owner approval.

- A successful authorization clears `expiresAt` atomically with its booking update.
- Existing authorized pending records remain approvable and block same-renter,
  same-item overlapping requests even if their historical payment deadline passed.
  No migration is required.
- When legacy duplicates coexist, duplicate recovery prefers the authorized request
  over a newer unpaid request, avoiding an unnecessary second payment.
- Recovery can reconcile a durable authorization recorded before the payment deadline
  even when the interrupted booking update is retried after that deadline. It does
  not create another payment or revive cancelled/expired terminal bookings.
- The unpaid-expiry job now claims the still-unpaid, elapsed request atomically,
  avoiding overwriting a concurrently authorized booking's state.
- Different renters' pending requests remain soft holds. Approval still requires
  payment, ownership, identity eligibility and actual availability. Competing
  pending requests still expire/release demo holds when another request is approved.

This fixes the observed mismatch where a paid request remained visibly pending
but was ignored by duplicate checking and rejected by approval after its timer.
Old duplicate requests are not automatically cancelled or removed; renters can
cancel unwanted ones using normal controls. No new deadline for paid Owner approval
was introduced.

## Listing camera and multiple photos

**Add photos** on the live create/edit physical-item and service forms opens:

- **Take a photo**: an in-app rear-camera capture, followed by review before upload.
- **Choose photos**: one multi-file selection, followed by a shared batch preview.

Uses the already-installed `camera` and `file_picker` packages; no new dependency,
service, credentials or launcher process is needed. Android already declares camera
permission. Permission is requested only on opening the camera. The new camera
screen is independent of MyKad/KYC scanning and never applies document checks.

Native Windows does not have a camera implementation in the installed camera
package, so its camera choice is disabled with an explanation; multi-file selection
remains available. Browser camera availability depends on browser permissions and a
secure context. No iOS build or physical-device capture is claimed.

The batch preview shows local photo thumbnails and allows enlargement/removal before
upload. Explicit confirmation is required. Photos use the existing `listing_image`
upload purpose and public listing-photo references. Original listing photos remain.

- Keeps the existing 10-photo listing maximum and three-photo physical-item review
  minimum. Over-selection reports the remaining capacity instead of silently choosing
  a subset. JPEG/PNG/WebP and a 10 MB client photo limit are enforced; server upload
  validation remains authoritative.
- Uploads are sequential and keep the selected bytes after failures. Retry uploads
  only failed/unuploaded entries, not successes. **Use uploaded photos** preserves
  successful references when the user finishes a partial batch.
- Cancellation before upload makes no upload requests. Busy controls prevent
  overlapping pickers/saves or accidental dismissal mid-upload.
- Camera resources are released on pause/close, initialization/disposal is serialized
  and late callbacks are ignored. Camera failures show safe retry/file-selection
  guidance, without raw exception text.
- Session changes stop further batch requests and prevent old-account responses from
  attaching photos to the new account's draft. Existing Auth0 behaviour is unchanged.

## Verification

| Check | Result |
| --- | --- |
| New camera/batch Flutter suite | 10 passed |
| Full non-live Flutter suite | 389 passed, 3 skipped |
| Full API suite against ephemeral MongoDB | 364 passed, 3 skipped |
| Source/new-test analysis | No issues |
| Flutter web build | Passed |
| Android debug APK build | Passed |

Flutter tests cover explicit capture, denied permission/retry, late initialization,
partial upload/retry without duplicate success uploads, invalid-image rejection,
removal/cancellation, account changes, actual form multi-selection in one picker
call and capacity enforcement. Batch layouts cover 360/390 pixels with 1.5x text.

API regressions cover historical paid deadlines, duplicate redirection to the paid
request, successful payment deadline removal, interrupted in-time payment recovery,
paid Owner approval and the unpaid-only lifecycle job. Tests used process-local test
configuration and MongoDB memory-server, not live bookings or payment records.

The previously identified full-analyzer errors in `test/auth0_persistence_test.dart`
(`latestLinkProvider` / `mobileLinkPollInterval`) are unrelated and untouched.
Web retains existing Socket.IO WebAssembly dry-run/Cupertino-font warnings; Android
reports the existing plugin Kotlin Gradle migration warning. Hardware camera and
native multi-selection still require a real-device check.

## Handoff

Restart the API and hot-restart Flutter via the existing configured launcher. Open
the older paid request: Owner approval should work if all other requirements and
availability still pass; another same-renter overlapping request should link back
to it. Creating an unpaid request must still have a payment deadline.

On Android, open a listing form, tap Add photos, take a photo and confirm its preview.
Then choose several photos together, remove one, upload, inspect the saved previews
and verify the count. Deny camera permission once to check recovery. Retry an upload
after interrupting connectivity, confirming successful entries are not reuploaded.

```text
fix(bookings): retain paid requests and improve listing photo uploads

- apply the pending expiry timer only to unpaid requests
- keep legacy paid requests approvable and prevent overlapping duplicates
- clear payment deadlines and recover interrupted in-time authorizations
- atomically claim unpaid expirations without overwriting paid state
- add in-app listing camera capture and multi-photo file selection
- preview batches with removal, partial success and failed-photo-only retry
- preserve listing photo limits, session safety and existing KYC behaviour
- add API/camera/upload regressions and document build/device limitations
```
