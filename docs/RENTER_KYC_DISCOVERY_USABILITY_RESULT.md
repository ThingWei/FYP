# Renter verification, location and discovery fixes

Date: 5 November 2026

## Changes

### Verification photos

- Verification-document multipart uploads accept up to **20 MiB** by default. `MAX_VERIFICATION_UPLOAD_BYTES` configures the API limit, bounded to 40 MiB; the current Flutter client supports 20 MiB. Ordinary uploads retain their existing 10 MiB limit.
- Multipart transport allows the larger bounded verification payload even when the file precedes its purpose field. The service independently enforces the correct purpose-specific limit. Ownership, private document access and supported image formats are unchanged.
- Check selected-file size before reading/previewing it. Decode previews at a bounded width instead of decoding every camera image at full resolution twice. Uploaded original bytes are preserved. Failed uploads retain the preview and explicit retry.
- Size errors explain the applicable limit without exposing server information.
- For a confidently detected MyKad, measure sharpness, exposure and glare inside its detected card region. A black table/background must not by itself make an otherwise readable card too dark. Keep the existing resolution rule and quality thresholds; do not guess a card crop when the detector is unavailable or uncertain.
- Full original captures still undergo mandatory required-field readability, screen-copy checks, side checks and front/back-number matching. A readable photograph is not proof of authenticity and still requires administrator review. Passport/driving-licence image-quality behaviour is unchanged.

### Status and review guidance

- Shared status badges match complete words and negative states before positive ones. `unverified`, `not verified` and `inactive` no longer inherit the green colour from `verified`/`active`.
- Display driving-licence and MyKad notes in separate review-update panels labelled **Update from RentHub verification**. This identifies the source without incorrectly claiming every automatic validation message was written by an administrator.

### GPS and search

- Home/Explore filter GPS and map pins now request the nearest mapped address, instead of deliberately skipping lookup and substituting `Current area`.
- Keep the selected coordinates unchanged when filling the mapped name and available city/state/postcode. Do not move the pin to the provider's nearby map feature.
- Retain cancellation, stale-response, private-pin, permission-denial and lookup-failure handling. A lookup failure preserves the draft and allows retry/manual correction.
- The main rental search dropdown includes typed **Search this area** suggestions alongside product results. Only public city/state data from eligible active listings is used. Selecting an area applies a location filter and clears the product text query.
- Own, blocked, restricted and unpublished listings remain excluded. No private unit/street address or exact coordinates appear in search suggestions. Legacy result fields remain available to existing API callers.
- The map picker's explicit Search shows its result list directly below the search button in a bounded selectable panel. Selecting a result fills the pin/address and closes the list.
- Public Nominatim searches remain explicit and retain existing caching/rate limits. No external geocoder receives keystroke autocomplete requests. See the [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/).

### Retained filtered results

- Home and Explore have separate account-scoped screen state and request generations, including query, filters, selected area, view mode, page size, successful results and refresh time.
- Retain a successful filtered result when recommendation sections refresh. An empty feed section must not replace a separate successful filtered query.
- Restore screen state if a page is recreated, refresh incomplete/failed/stale searches, ignore superseded requests and clear stored state when the account changes/logs out. Existing Home feed ranking and eligibility rules are unchanged.

## Storage diagnosis and live configuration

Read-only inspection found API ordinary/verification limits of 10/20 MiB but the existing Supabase bucket still limited every file to **10 MiB**. This independently blocked larger camera JPGs.

The existing bucket limit was raised to **20 MiB**, preserving its visibility and allowed MIME types. A generated noise-only JPEG of **15,218,293 bytes** uploaded and downloaded successfully with matching checksums. The temporary cloud object was deleted successfully. No identity image, account, listing, booking or verification-attempt record was used or created by this probe.

This bucket setting is shared across laptops. A separately provisioned bucket must also allow at least the API's verification limit. Higher bucket transport capacity does not bypass the API's ordinary-upload limit or document validation.

## Verification

- API: **80 tests passed** across upload, environment, search/message compatibility, MyKad readability/approval guards, map adapter and location/privacy suites. Databases were isolated MongoMemoryServer instances; child-process configuration used mock authentication/AI and local test storage.
- AI: **131 tests passed** across capture quality, mandatory readability, front/back matching, screen screening and whole-card handling. Added synthetic black-background and missing-detector quality cases. Updated orchestration fixtures to avoid consulting local detector artifacts. One existing spaCy/Click deprecation warning remains.
- Flutter focused KYC/photo/GPS/Home regressions passed. Added status, safe size errors, attributed review notes, area dropdown, account isolation, retained filtered results and late-response regression cases.
- Flutter full suite: **593 passed, 3 existing opt-in skips**. Layout cases cover 360/390-pixel screens with increased text size; existing explicit map-search cases also cover 1024 pixels.
- Flutter analysis: **no issues found**. Android debug APK and web builds passed. Existing nonfatal Kotlin-plugin migration, WebAssembly dry-run and optional Cupertino-font warnings remain; no Auth0 analyzer errors were present in this run.

## Limitations and device handoff

- The user's original rejected JPG and exact error were not provided. The black-background and size-limit defects were reproduced with synthetic inputs; no claim is made that every camera-photo rejection has the same cause.
- Reopen the updated app and retry the original file. Keep all card corners and required details visible. Blur, glare, unreadable details, wrong sides, mismatches and screen copies must still be rejected.
- GPS accuracy and OpenStreetMap address coverage vary. A mapped address can be incomplete or refer to a nearby feature; check its label and the pin before confirming. Never invent missing unit numbers/postcodes.
- Local area autocomplete only offers public localities represented by eligible RentHub listings. Use the map's explicit public-place search for other towns/landmarks. This change does not import an external address database.
- Filter state is in-memory for the current session, not persisted across app restarts. Signing out clears it.
- Verify physical-camera capture, file selection and live GPS on Android after rebuilding/reopening the app. No live identity submission or approval was performed during these checks.

## Suggested commit message for these fixes

```text
fix: improve renter verification uploads and preserve discovery filters

- support private verification photos up to 20 MiB with bounded previews
- assess detected MyKad lighting and sharpness independently of backgrounds
- correct negative status colours and attribute verification review updates
- fill nearby GPS labels with mapped addresses without moving selected pins
- add privacy-safe area suggestions and clearer map search results
- isolate Home and Explore state and ignore stale discovery responses
- cover upload limits, identity guards, GPS recovery and filter retention
```
