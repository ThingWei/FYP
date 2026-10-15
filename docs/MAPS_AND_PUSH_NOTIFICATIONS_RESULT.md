# Precise live locations and Android push notifications

Verified: 12 October 2026.

## Delivered

- One shared **Choose on map / Search location** picker covers the live listing, address, booking and Explore workflows below. It supports explicit public-place search, map adjustment, zoom controls, address preview and confirmation.
- Search is not autocomplete. Typing alone makes no geocoding request. Empty/failed searches allow map selection if the map is usable. Cancellation/failure preserves the existing location/draft. New or changed physical locations cannot silently fall back to text-only submission.
- Confirmed pins save private exact coordinates/address details. Public listing responses expose only a deterministic approximate grid centre and locality. Editing an address invalidates confirmation; unrelated edits preserve it. Legacy unpinned records remain readable and accept unrelated edits.
- Authentication is required for map configuration/search. Invalid query lengths and malformed/out-of-range coordinates are rejected by Express. Provider errors have safe, readable UI messages, and stale search responses are ignored.
- Existing Android FCM registration is now connected to `run-renthub.ps1`. It checks public Android configuration, includes client Dart defines, creates the Android notification channel and displays honest device-registration/permission/configuration status in Settings.
- Push registration requires device permission, an enabled API provider and successful authenticated device registration. Token refresh is user-scoped; sign-out invalidates pending registration. Cleanup failure does not prevent logout. Preferences saved without successful push registration produce a visible warning instead of silently implying delivery works.

No live database migration, account configuration, push delivery or service-account creation was performed. The actual `.env` remains unchanged; FCM is disabled until the setup below is completed. Supabase storage and Auth0 behavior are preserved.

## Maps: contracts and operational limits

| Endpoint / field | Contract |
| --- | --- |
| `GET /api/v1/maps/config` | Authenticated; enabled flag, HTTPS tile template, attribution, explicit search mode, country `MY` |
| `GET /api/v1/maps/search?q=...` | Authenticated; trimmed 2–160-character query; normalized label/state/coordinates, at most six results |
| `POST /api/v1/maps/resolve-pin` | Authenticated; finite numeric `coordinates` and `publicPointConfirmed: true`; explicit public-place lookup only. Returns a nearby mapped address or `item: null`, retaining the submitted pin. |
| Listing `coordinates` / `locationDetails` | Private exact point and structured details for owners/admins; finite latitude/longitude, text, optional five-digit postcode and optional GPS accuracy. New/changed physical locations require a pin. Public serialization replaces coordinates with an approximate point and omits private details. |
| Listing `location` / `state` | Existing endpoint/payload fields retained; public `location` is derived from city/state, never the private entrance/address. Owner/admin responses retain the stored location and private details. |

Flutter calls the RentHub API for search with a 35-second UI timeout and no automatic retries. Express calls the configured Nominatim provider with `countrycodes=my`, a meaningful application User-Agent and a ten-second provider timeout. Results are normalized, invalid coordinates/non-Malaysian results are excluded, duplicate in-flight queries coalesce, successful results (including empty lists) are cached for 24 hours, and cache size is limited to 500 queries. Failed responses are not cached. A timed-out UI search can finish on the server and populate its cache, but cannot overwrite a newer user selection.

The shared queue limits upstream starts to at most one per second, with at most 20 pending distinct queries. This limit is **per API process**, appropriate to the current single-process FYP demo. Multiple workers/servers must use an application-wide shared limiter/cache or a different geocoding service before using public Nominatim at scale. This implementation does not promise production-scale geocoding availability.

Map tiles load directly through `flutter_map` 8.3.2 (requested constraint `^8.2.2`) and `latlong2`. Native requests identify `com.weith.renthub`; web requests use the browser's normal headers. The library's native/browser tile caching is retained. There is no bulk download/offline mode; extra pan/keep buffers are zero. The picker displays an OpenStreetMap attribution link. Failed tiles offer explicit retry without discarding the selection.

Public-service requirements are documented in the [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/) and [OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/). Only search public towns/landmarks: do not submit confidential addresses or personal document details. Exact address labels and pins are private; only city/state and approximate grid centres are marketplace-facing. KYC data must never be used for geocoding. See also [flutter_map caching guidance](https://docs.fleaflet.dev/layers/tile-layer/caching).

Configuration in `services/api/.env`:

```dotenv
MAPS_MODE=openstreetmap
MAP_TILE_URL=https://tile.openstreetmap.org/{z}/{x}/{y}.png
OPENSTREETMAP_NOMINATIM_URL=https://nominatim.openstreetmap.org
OPENSTREETMAP_USER_AGENT=RentHub/1.0 (contact: YOUR_MAINTAINER_CONTACT)
OPENSTREETMAP_MIN_INTERVAL_MS=1000
```

Use a real maintainer contact rather than the example placeholder. Restart the owning API/launcher after changing configuration. Tiles/geocoding need internet access. Provider URLs are configured by the server, allowing replacement without rebuilding the app; an alternative tile provider must use compatible OSM data/attribution and satisfy its own terms.

## Live field coverage

| Workflow | Delivered behavior |
| --- | --- |
| Physical-item create/edit | Confirmed entrance/pickup pin; private exact address separate from public city/state. Changed address requires reconfirmation. Legacy unchanged locations may remain unpinned. |
| Service create/edit | Owner-location, renter-location and flexible service modes require a physical listing pin; online-only services do not. Switching an unpinned online listing to a physical venue is rejected until pinned. |
| Saved addresses | Add/edit through the picker. Address lines, city/state, string postcode, default flag and MongoDB address ID are preserved. Changing address fields requires reconfirmation. Existing second lines remain retained, including delivery snapshots. Missing public-search details remain blank for confirmation; no house/unit/postcode guesses. |
| Service booking | Owner-location snapshots the owner point; renter-location/flexible require a renter-confirmed venue; online needs no pin and rejects a physical venue payload. |
| Owner-delivery booking | Pinned saved address or newly confirmed destination. Old unpinned addresses require a new pin before use. Saved address IDs remain stable during profile updates and foreign/duplicate IDs are rejected. |
| Explore | Optional centre plus radius 5/10/25/50 km, default 10. Centre is a search filter, not a rental destination. Empty/text browsing remains available. |
| Public listing / wishlist / comparison | Approximate area labels and optional area map only; exact coordinates are removed server-side. |
| Renter/owner booking cards | View booking locations through authenticated participant-specific snapshots, with map and address recovery if tiles/configuration fail. |

Old mock/prototype screens are intentionally excluded. There is no background tracking, routing/directions, distance sorting, or automatic reverse geocoding.

## Android GPS and precision

### Address-label and pin-lookup correction (12 October)

Search previously copied Nominatim's entire `display_name` hierarchy into the location field. A suburb, neighbouring administrative town, district and state appeared as one long place name. Results now use the selected feature's name (or a street/house number explicitly supplied by the provider) as the main label. City/state appear separately for disambiguation; county/country chains are not appended to the selected name. Distinct places with the same name can still appear as separate suggestions: confirm the correct result on the map rather than assuming text alone proves identity.

Moving a pin or obtaining a new GPS reading previously retained old city/state/postcode without checking whether they belonged to the new coordinates. It now clears these stale structured values, keeps the private address draft, displays the selected coordinates and warns that the draft must be checked. Cancellation still preserves the caller's previous location.

**Find address for this pin** offers an explicit privacy confirmation before contacting the provider. It is for public streets/buildings/pickup points, not confidential home positions. Choosing **Keep private / enter manually** sends no lookup. GPS and map movement never automatically send a reverse-geocoding request. A lookup previews the nearest mapped address; **Use this mapped address** explicitly fills the address/city/state/postcode without moving the pin or guessing missing unit numbers/postcodes. Failures/unmapped/state-only results retain the draft and offer retry/manual entry. New pin/text edits invalidate in-flight lookup results.

Search and pin lookup share the existing bounded 1-request/second queue, 24-hour/500-entry cache and in-flight coalescing. Failed provider calls are not cached. Coordinate lookup uses POST so private coordinates are not in RentHub access-log URLs. Public-listing coordinate filtering and booking unlock rules are unchanged; an existing public listing may still show only its state if it has no saved city. This fix does not bulk-geocode or rewrite existing listings.

Nominatim returns the nearest suitable mapped object, **not a guaranteed exact address for a coordinate**; it can select another street in densely mapped areas. Review the street/entrance and enter missing details manually. See [Nominatim reverse-geocoding behaviour](https://nominatim.org/release-docs/latest/api/Reverse/) and its [usage/privacy policy](https://operations.osmfoundation.org/policies/nominatim/). Public service use remains explicit, cached, attributable and single-process rate-limited; it is not a production-scale availability guarantee.

Follow-up verification: 21/21 focused API tests (maps adapter/routes and precise-location/privacy/booking regressions) and 35/35 focused Flutter tests (including nine new address-lookup tests) passed. These cover concise hierarchical labels, preserved pin coordinates, state-only/unmapped handling, authentication/strict numeric/public-place confirmation, shared cache/queue, private draft/retry, no automatic GPS lookup and stale responses. Picker tests use a fake map canvas/provider, including 360/390/1024 widths at 1.3 text scaling; real Android/OSM address accuracy still needs manual checking. Full Flutter analysis still reports only the two pre-existing Auth0 test parameter errors below. No live database or `.env` changes were made.

To verify on your device: restart `run-renthub.ps1`/API and rebuild/relaunch the Android app, search a known public area and check that its name is not the whole district/state chain. Move the pin, choose **Find address for this pin**, review the public-place sharing notice, preview and explicitly apply the mapped address. Check that the pin stays fixed. For private destinations use manual address details, without the external lookup. Old stored addresses are not automatically cleaned up; edit and reconfirm them as needed.

Changed-file Flutter analysis is clean. Web JavaScript and Android debug builds passed after this correction; existing Wasm/socket_io_common, missing Cupertino font and Kotlin plugin migration warnings remain unrelated. The debug APK is a compile check, not a newly configured production deployment or a real-device accuracy test.

Follow-up commit message:

```text
fix(maps): clarify place labels and resolve public pin addresses explicitly

- separate selected place names from administrative address hierarchies
- add authenticated, validated public-pin address lookup with shared rate limiting and caching
- preview nearby mapped addresses without moving pins or replacing drafts automatically
- clear stale locality on pin changes and ignore stale lookup responses
- preserve public coordinate privacy and keep private GPS lookup opt-in
- add API and responsive Flutter address-resolution regressions and document provider limits
```

`geolocator` 14.1.1 is the only newly added positioning dependency (the installed packages provided maps but no device positioning). The GPS shortcut is Android-only; Windows/Web retain search and manual map adjustment. Foreground coarse/fine permissions are requested **only after tapping Use my current location**. It checks disabled location services, denial and permanent denial with manual-pin/settings recovery; one high-accuracy reading uses a 15-second timeout. Stale readings/searches cannot replace a later selection.

Reported accuracy is displayed. Accuracy above 50 metres or approximate permission produces a visible adjustment warning. A low reported error is not proof of an exact entrance; the user must check/adjust and explicitly confirm. Manual tap/drag-style adjustment clears old GPS accuracy metadata rather than claiming the new point was measured. No background permission/stream or automatic private GPS reverse-geocoding is implemented. See the [geolocator documentation](https://pub.dev/packages/geolocator).

Search only public streets, buildings and landmarks. The private draft address is never prefilled into the public search box. Private units/house details belong in the address preview, not Nominatim. City/state are publicly visible and must not include private unit details.

## Location privacy and snapshots

- Listing `coordinates` remain the private exact point. `locationDetails` stores the private address, optional address lines/city/state/postcode/source/accuracy. `publicGeoPoint` is derived server-side using 0.01-degree cell centres: `floor(coordinate / 0.01) * 0.01 + 0.005`. No random offsets. Longitude-cell widths vary with latitude; approximately a kilometre is a privacy approximation, not a distance guarantee.
- Safe public listing serialization is the default, including discovery/recommendations/wishlist/comparison and incidental model responses. Owner-only listing mutations/mine and authorized administrative listings explicitly restore private fields.
- Public profiles, push messages and blockchain inputs do not gain private pins. HTTP diagnostics omit query strings (which can contain GPS/search positions); unexpected-error logs retain error name/status/code rather than raw documents/request bodies.
- New booking `pickupLocationSnapshot`, `serviceLocation` and `deliveryLocation` are immutable snapshots created with the booking. Editing a listing/address later does not move that booking. Destination content participates in idempotency fingerprints; merely changing JSON field order does not change the request identity.
- `GET /api/v1/bookings/:id/locations` requires authentication and participant/admin access. Unrelated accounts receive 404.
- Owners see their own pickup/owner venue; renters see their own submitted service/delivery destination. Counterpart details unlock only for `approved`, `active`, `completed`, `disputed`. `pending`, `rejected`, `expired`, `cancelled` do not unlock them. Admins retain moderation access.
- Existing booking responses apply the same filtering, including legacy `serviceVenue` strings. Unknown legacy venue ownership is treated conservatively instead of exposing an unclassified private venue.
- Historical bookings are not silently populated from today's listing/address, since that could fabricate/move their agreed location. A legacy missing snapshot shows unavailable; no exact position is invented.

## Nearby search and optional backfill

Existing listing discovery and recommendation endpoints accept `latitude`, `longitude`, `radiusKm` **together**. Valid radii are 5, 10, 25, 50 km. Express uses MongoDB spherical `$geoWithin / $centerSphere` on `publicGeoPoint` and a `2dsphere` index. Category/price/availability filters and existing sorts remain; filtering happens before pagination/counting. Distances are not exposed as exact.

Records without usable persisted public points are excluded from nearby results. Text/town browsing remains available using public city/state. Legacy records lacking structured locality may display only their stored state or “Area available after confirmation”; private raw street text is not used as a public search oracle.

The backfill derives public points only from valid existing coordinates. It is bounded (default 500, maximum 5,000), idempotent and dry-run by default. It logs aggregate counts only and uses a compare-and-set guard against concurrent location edits. No external geocoding or invented coordinates. **It was tested only against disposable MongoDB; it has not been run on your live database.**

```powershell
cd C:\Users\weith\FYP\services\api
# Inspect aggregate counts first; no writes:
npm.cmd run backfill:public-locations -- --limit=500
# Only after reviewing that dry run and choosing to update your database:
npm.cmd run backfill:public-locations -- --apply --limit=500
```

Repeat the bounded apply deliberately for larger datasets. Rows with no valid private coordinates cannot be backfilled. The index is declared in the model; deployments with auto-indexing disabled must create the `publicGeoPoint` 2dsphere index through their normal deployment procedure. See [MongoDB geospatial query guidance](https://www.mongodb.com/docs/manual/reference/operator/query/geowithin/).

## Android push: setup and activation

15 October update: the supplied Android configuration and matching Admin service account have now been configured locally. The private Admin file was moved to ignored server `.data/firebase/service-account.json`; Admin authentication and launcher public-client flags passed verification. See [catalogue/delivery/push handoff](CATALOGUE_DELIVERY_AND_PUSH_RESULT.md) for restart instructions, tests and remaining real-device delivery checks. The setup instructions below remain applicable to other machines; local credentials are not committed.

[Firebase's current pricing page](https://firebase.google.com/pricing) lists Cloud Messaging (FCM) as no-cost and Spark as requiring no payment method. This is separate from Cloud Storage billing. RentHub can retain `STORAGE_MODE=supabase` and use Firebase only for Android messaging; there is no requirement to create a Firebase Storage bucket or enable paid Cloud Functions for this implementation.

1. Create or reuse a Firebase project on Spark. Register an **Android app** with exact package name `com.weith.renthub`.
2. Download its `google-services.json` and place it at `apps/renthub_flutter/android/app/google-services.json`. The file is ignored by Git. Do not put the Admin SDK service-account file here.
3. In Firebase project settings → Service accounts, obtain the Admin SDK service-account JSON for the same project. Store it outside tracked code, for example `services/api/.data/firebase/service-account.json`. Keep it private; do not paste it into chat, Dart defines or Git.
4. Update only the server settings in `services/api/.env`:

   ```dotenv
   FCM_MODE=firebase
   FIREBASE_PROJECT_ID=YOUR_ACTUAL_PROJECT_ID
   GOOGLE_APPLICATION_CREDENTIALS=C:/Users/weith/FYP/services/api/.data/firebase/service-account.json
   STORAGE_MODE=supabase
   ```

5. Stop the original launcher/API terminal with Ctrl+C and relaunch for your Android device:

   ```powershell
   cd C:\Users\weith\FYP\apps\renthub_flutter
   .\run-renthub.ps1 -Device YOUR_ANDROID_DEVICE_ID
   ```

6. Sign in and enable push under Profile → Settings. Grant the Android notification permission. If denied, enable RentHub notifications in Android Settings and explicitly save RentHub settings again.
7. Check the registered device under the existing Security page. With a second test account, trigger a message or booking update. Verify foreground in-app feedback, background notification, and notification-tap navigation separately. Do not use private identity documents as test notification content.

The launcher extracts **public client** API key, app ID, sender ID and project ID from the Android JSON and supplies the existing `FIREBASE_*` Dart defines. Server credentials never enter the Flutter build. Alternatively, supply `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID` and `FIREBASE_PROJECT_ID` in the server env for launcher extraction; they must describe the same project. Native Firebase initializes explicitly from `FirebaseOptions`; this change does not add the Google Services Gradle plugin.

Keep `FCM_MODE=disabled` until both client configuration and server credentials are ready. Windows, Chrome and Edge launcher targets keep Firebase client push disabled. Windows continues to use existing in-app updates; Web push service-worker/VAPID setup and iOS/APNs provisioning are not delivered by this Android-focused task.

`GET /api/v1/messages/push/status` is authenticated and reports configured/disabled provider state, **not successful delivery**. Device registration also does not prove delivery. Existing Firebase Admin delivery records and real-device testing are needed to verify credentials, network and notification permissions. Foreground messages use the existing in-app feedback; Android background notification messages use the `renthub_updates` channel. Delivery may be affected by device settings, Google Play services and force-stop behavior. See [FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) and [message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

The RentHub API must still run and be reachable to generate booking/message notifications and accept device registration. FCM does not host Express, MongoDB, AI or blockchain. No hosting changes were made.

## Verification

- API: **98/98 focused regressions passed** across precise locations, map adapter, maps/listing/push, listings, booking/rental, users, recommendations, discovery/admin, communication and payments, using isolated MongoDB. The full API suite also passed: **253 passed, 3 opt-in integration tests skipped, 0 failed**. Covers coordinate/structured validation, new versus legacy records, online venue exceptions, public feed/wishlist/comparison privacy, participant/status access, immutable snapshots, destination idempotency, address ownership/stable IDs, spherical filtering/counts/pagination, failed sources and bounded dry-run/idempotent backfill.
- Flutter: **83 focused tests passed**, with one pre-existing intentional skip. Includes each live workflow, GPS denial/permanent denial/off services/coarse accuracy/timeout, manual adjustment/stale responses, cancellation/draft retention, saved-address retry/leading zeros, nearby radius, pricing/listing/booking/account contracts and existing push behavior. Picker/layout regressions cover 360/390/1024 pixels at 1.3 text scaling; listing regressions cover those sizes and administration checks cover 1024/1440.
- Live Dart code and changed location/input tests pass focused analysis. Full-project analysis still fails only on two existing undefined Auth0 test parameters in `test/auth0_persistence_test.dart:41` (`latestLinkProvider`) and `:43` (`mobileLinkPollInterval`). No Auth0 changes.
- Launcher helper tests pass. API health now advertises `precise-locations-v1` so the launcher does not silently reuse an older location contract.
- Web JavaScript and Android debug APK builds pass. Existing socket_io_common Wasm/Cupertino font and Firebase/shared-preferences Kotlin warnings remain; the geolocator Android compiler also reports a deprecation note.
- Automated UI tests use a fake map canvas/GPS gateway. They are not claims of live tiles, hardware GPS accuracy, granted permissions or delivered notifications. No live database or external account setup was changed.

## Remaining checks

- [x] Configure the local Android Firebase client and server credentials; Admin authentication verified. Device permission/token/delivery checks remain below.
- [ ] Set a real OpenStreetMap application contact and verify search/tile access on the connected Android device.
- [ ] Verify physical/service listings, saved-address add/edit, service venue modes, owner delivery and Explore centre/radius on the connected Android device.
- [ ] Test GPS “while using app” and approximate permission, deny/deny permanently, disabled GPS and poor reception; check accuracy warning and manual entrance adjustment.
- [ ] Check a pending booking using both test accounts: counterpart exact points must be absent; approve and confirm both accounts can view the frozen agreed destinations.
- [ ] Edit the original listing/address and reload the existing booking: the snapshot must not move.
- [ ] Review the optional backfill dry run if older pinned listings are missing from nearby results. Do not use it to generate pins for unpinned records.
- [ ] Verify notification permission, background delivery and tap routing on the real device with test accounts.
- [ ] Fix the two pre-existing Auth0 test contract errors separately before claiming a clean full-project analyzer/test run.

Suggested complete commit message (includes the preserved maps/push groundwork):

```text
feat: add precise private locations and nearby search across RentHub

- reuse searchable OSM picker for listings, addresses, venues and delivery
- add opt-in Android GPS with accuracy warnings and timeout recovery
- require confirmed physical pins while preserving legacy unchanged records
- expose approximate public listing areas and protect private coordinates
- freeze participant-scoped booking locations and include destinations in idempotency
- preserve address IDs, structured details and leading-zero postcodes
- filter discovery and recommendations with indexed spherical public-area queries
- add bounded dry-run public-point backfill and launcher contract checks
- preserve Android FCM setup, registration recovery and notification channel
- test location privacy, snapshots, form recovery and nearby behavior
- document backfill, precision limitations and real-device checks
```
