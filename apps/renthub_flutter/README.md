# RentHub Flutter application

The renter and Owner interfaces are mobile-first. The Windows runner is useful
for local development only; Firebase Cloud Messaging is intentionally disabled
on Windows.

## Android and iOS Firebase setup

The Android runner uses application ID `com.weith.renthub`. Register that exact
identifier in Firebase, then run FlutterFire configuration from this folder:

```powershell
flutterfire configure --platforms=android
```

Generate and configure the iOS runner later on macOS after choosing its final
bundle ID:

```powershell
flutter create --platforms=ios .
flutterfire configure --platforms=ios
```

This creates the native `google-services.json` and
`GoogleService-Info.plist` integration. Do not commit private server service
account credentials. Start the mobile application with the live backend and
Firebase enabled:

```powershell
flutter run --dart-define=FIREBASE_ENABLED=true `
  --dart-define=API_BASE_URL=http://YOUR-LAN-IP:3000/api/v1 `
  --dart-define=SOCKET_URL=http://YOUR-LAN-IP:3000
```

For iOS, also enable Push Notifications and Background Modes -> Remote
notifications in Xcode and upload the APNs key in Firebase Console.

## Android Auth0 development

Android Auth0 uses the configurable custom callback
`com.weith.renthub://login-callback`. Configure the Android Native application
client and callback in `services/api/.env`, then use the same launcher as the
Windows build:

```powershell
.\run-renthub.ps1 -Device <ANDROID_DEVICE_ID>
```

The launcher supplies the Auth0 Dart defines and Android manifest placeholders
and forwards the selected API port with `adb reverse`. It finds ADB from `PATH`, the
Android SDK environment variables, or the standard per-user Android SDK
location. Firebase remains optional. See
`docs/AUTH0_ANDROID_RESULT.md` for Auth0 Dashboard and LAN fallback setup.

## API port conflicts

The launcher reads `PORT` from the shell environment or `services/api/.env`
(default `3000`). If that port hosts an outdated or unhealthy API, it automatically
selects a free port from `3002` to `3020`. Desktop/browser clients use the selected
port. Android clients keep `localhost:3000`; ADB forwards that device port to the
selected PC port, so an installed APK still works after a PC port conflict. Existing processes
keep running. Ports `3001`, `8080`, `8001` and `8545` are reserved for the web,
AI and blockchain services.

To prefer a particular API port for this session:

```powershell
.\run-renthub.ps1 -ApiPort 3002
```

The launcher prints the selected port. If you supply custom `API_BASE_URL` or
`SOCKET_URL` Dart defines for LAN access, use that same port in both URLs.

## Automatic MongoDB Atlas network access

For an Atlas `mongodb+srv://...mongodb.net` connection, the launcher first tries a
read-only database ping. A working connection needs no CLI login or access-list
update. If it fails, the launcher uses MongoDB Atlas CLI to allow the laptop's
current public IPv4 address before starting backend services. Install Atlas CLI
on each laptop, restart the terminal, and run when registration is needed:

```powershell
atlas auth login
.\run-renthub.ps1
```

Use an Atlas account with permission to manage this project's network access.
The same account can be used on both of your laptops. CLI login is separate from
the application's database credentials and RentHub sign-in. Reauthenticate with
`atlas auth login` if the CLI session expires.

The launcher matches the configured database hostname to an accessible Atlas
cluster, so it cannot silently update a different project. Optionally set
`ATLAS_PROJECT_ID` in `services/api/.env` or pass `-AtlasProjectId <project-id>`
to avoid searching projects. A named CLI profile can be selected using
`-AtlasProfile <profile-name>`.

Public IPv4 detection uses `https://checkip.amazonaws.com`, with
`https://api.ipify.org` as a fallback; no database URI or CLI credentials are sent
to either service. New entries allow only that individual IP and expire
after 24 hours. Existing access entries are preserved; the launcher never deletes
the other laptop's address or adds an allow-from-anywhere rule. Laptops sharing
one public IP reuse its entry. The launcher verifies the database connection with
read-only connect/ping attempts while access propagates. Connection failure stops
startup before AI or blockchain processes are launched.

Rerun the launcher after changing networks or after temporary access expires.
Both laptops need the updated launcher. Keep their configured Atlas database and
application identity/session secrets compatible as described in
`docs/SHARED_DATABASE_ATLAS_SETUP.md`.

For manually managed Atlas access, pass `-SkipAtlasAccess`. Local MongoDB and
non-Atlas connections do not use CLI registration.

## Reliable local presentation

Run from this directory with Node.js 22+ and your configured API `.env`:

```powershell
# Windows app, stable services without code reload
.\run-renthub.ps1 -Presentation

# Android: replace the example with the ID shown by adb devices
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation

# Already-installed Android app: keep backend services and reconnection checks running
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation -ServicesOnly
```

AI startup allows 180 seconds by default; API startup allows 90. For a slower
laptop, use `-AiStartupTimeoutSeconds 300` and/or `-ApiStartupTimeoutSeconds 120`.
Readiness checks verify service contracts, database connectivity and chain ID;
starting a process alone is not success. Missing trained models still produce
warnings. Existing compatible services are reused with their original reload
settings; close their original launcher first if you need all services stable.

Services-only mode and the retained session after Android debugging ends restore
ADB forwarding after reconnection and check service health periodically. They do
not restart services during a booking or payment. Flutter's interactive debug
session owns the terminal while `flutter run` is active; use `-ServicesOnly` with
an installed app for continuous launcher monitoring. No automatic ADB pairing is
performed; an already connected wireless ADB device can be selected by its ID.

Keep the PC awake, online and the terminal open. Local hosting still depends on
that PC; use one active backend/blockchain for the presentation. See
`docs/LAUNCHER_RELIABILITY_RESULT.md` for tests, log paths and recovery steps.
