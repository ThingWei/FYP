# Catalogue usability, delivery fees and Android push

Updated: 15 October 2026. This extends the live application, not the older mock screens.

Follow-up: [Home, square cards and notification navigation](HOME_CARDS_NOTIFICATIONS_RESULT.md) supersedes the card presentation and recommendation-refresh behaviour described here. Delivery charges and local Firebase setup remain intact.

## Delivered

- Home recommendation sections default to horizontal swipe cards. Home and Explore have icon-only view controls: swipe (Home), grid and list. Grid is two columns on mobile, three on intermediate widths and four on wide screens; section See all pages start with up to 16 items and offer Show more. Four columns are deliberately not forced onto a 360-pixel phone.
- Category chips, nearby centre/radius and sorting live inside the filter page. The main toolbar has accessible filter/comparison icons and active-count badges. Search has an explicit clear (X) button. Filtered refreshes preserve selections; superseded search responses are ignored.
- Saved hearts are red on catalogue cards and listing details. Existing wishlist and comparison actions remain available in every view. Photos, approximate-area labels and recommendation explanations remain; card height is measured against available width/text scaling instead of creating a nested vertical scroller.
- The listing's unavailable-date summary hides expired ranges, sorts upcoming ranges and clips ongoing ranges to today in Malaysia. Availability checks retain the original ranges and confirmed-reservation rules; this is not a change to pending soft holds.
- Application settings no longer expose a language selector. Saved language preferences and API compatibility are retained; notification and account settings remain.

## Owner-set delivery charge

Owners can enter one fixed **Delivery fee (RM)** per physical listing. Zero means free delivery. The existing shared numeric formatter and API money validator enforce finite nonnegative amounts, two decimal places and a maximum of RM 100,000. Services do not acquire physical delivery fees.

The fee is included only for `owner_delivery`, once per booking, regardless of rental length. Pickup uses zero. Express saves it as `pricing.deliveryFee` and includes it in the authoritative total. Flutter shows the selected delivery charge and includes it in its estimate; checkout and agreement use the saved server breakdown. Owner settlement includes this charge. Client-provided totals do not control it.

Existing listings/bookings without a fee read as zero. An Owner changing today's listing fee does not alter an existing booking's charges or an idempotent booking replay. No live records were backfilled. Delivery charges are separate from rental base amounts, so they do not become AI daily-price evidence. There are no distance-based fees or new refund rules.

The API advertises `listing-delivery-fees-v1`; the launcher rejects an older running API without this capability instead of silently using the old pricing path.

## Current-location shortcut

Live shared location fields on Android offer **Use current location** directly. This opens the picker and starts one foreground GPS read, rather than making the user open the map and press GPS again. The final **Use this location** action is pinned to the bottom of the screen.

Nearby discovery can label this search centre `Current area` and confirm immediately after the user checks the map. A search centre is not a postal address. Physical pickup/delivery/service destinations still require a meaningful address/pickup-point label; GPS does not invent one. Required locality checks on submission remain intact.

GPS accuracy warnings, denial/timeout recovery, pin adjustment and cancellation remain. Cancelling preserves the parent draft. Private GPS coordinates are not automatically reverse-geocoded. The optional public-place address lookup still requires explicit sharing consent; mapped addresses can be incomplete or differ from an actual entrance.

## Firebase setup completed locally

The supplied Admin credential was validated as a service account for the same project as the existing Android `google-services.json`. It was **moved**, not copied or deleted, from the Android source directory to `services/api/.data/firebase/service-account.json`. The destination and local `.env` are ignored by Git. The ignore pattern also covers project-prefixed Admin key filenames.

Local API `.env` now sets `FCM_MODE=firebase`, the matching Firebase project ID and an absolute `GOOGLE_APPLICATION_CREDENTIALS` path to that ignored file. No private key is committed, printed or passed to Flutter. Supabase storage is unchanged.

Verified without sending a notification:

- Firebase Admin obtained an authentication token successfully; only `{provider, credentialAuthenticated, deliveryTested}` was reported, never the token.
- The launcher's actual Android public client configuration resolves to enabled Firebase defines and the matching project, excluding server credentials. Example placeholder client values no longer override a valid Android JSON file.
- `npm.cmd run preflight` now includes a push check: it distinguishes disabled messaging, Android client JSON used by mistake, mismatched projects and Admin authentication failure. Authentication success is explicitly **not** proof of message delivery.

Restart the existing API/launcher, not merely hot reload:

```powershell
cd C:\Users\weith\FYP\apps\renthub_flutter
.\run-renthub.ps1 -Device YOUR_ANDROID_DEVICE_ID
```

If another terminal already owns the API, stop it with Ctrl+C first. The launcher does not kill an unrelated server or reload another process's environment.

On Android, open **Profile → Application settings → Push notifications**, enable it, grant Android permission and save. With consenting test accounts, send a message or create a booking update; separately verify foreground feedback, background delivery and notification-tap navigation. Windows uses the in-app notification centre, not Android push. The API still needs to run and be reachable; this work does not add hosting or background phone tracking.

References: [Firebase Admin setup](https://firebase.google.com/docs/admin/setup), [Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). Real-device delivery, notification permissions and device token registration remain device-verification steps, not completed claims.

## Verification

- Full Flutter suite: **339 passed, 3 skipped**. Coverage includes horizontal sections, grid columns/list switching, compact category filters, clear search, selected hearts, 360/390/wide screens with increased text size, hidden past dates, Owner numeric fee entry, delivery selection/checkout, GPS shortcut confirmation, cancellation and existing privacy/retry regressions.
- Full API suite with isolated temporary databases: **333 passed, 3 skipped**. Added money validation/defaults, pickup versus delivery, saved fee/replay stability, charge breakdown and settlement, and safe Firebase setup checks. Existing booking/payment/location privacy tests pass. Tests disabled real push delivery and background jobs; no live marketplace database was mutated.
- Launcher syntax/readiness/public Firebase configuration tests pass.
- `flutter analyze lib` and changed Dart tests: clean. Full analysis still reports the two existing undefined Auth0 test parameters (`latestLinkProvider`, `mobileLinkPollInterval`) in `test/auth0_persistence_test.dart:41/43`; no Auth0 code was changed.
- Web build passes, with existing socket_io_common Wasm-dry-run and Cupertino-font warnings.
- Android push-enabled debug APK build passes, using public Firebase client options. Archive inspection found zero Admin/service-account file entries. Existing Firebase/shared-preferences Kotlin-plugin warnings remain. No hardware visual/GPS or delivered-push claim is made by widget/build checks.

## Commit message

```text
feat(discovery): polish catalogue views and add Owner delivery fees

- add horizontal Home sections, responsive grid/list views and compact filters
- add clear search, red saved hearts and upcoming-only blocked-date summaries
- add validated per-listing delivery charges through booking, checkout and settlement
- streamline Android GPS selection while retaining pin/privacy confirmation
- remove the out-of-scope language selector without changing saved preferences
- add Firebase Admin preflight and safer launcher client configuration
- extend UI, API and launcher regressions and document device verification
```

Local `.env` and credentials are intentionally not part of the commit.
