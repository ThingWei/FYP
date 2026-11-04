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
selects a free port from `3002` to `3020`. It passes the selected port to the new
API, Flutter HTTP and Socket.io URLs, and Android forwarding. Existing processes
keep running. Ports `3001`, `8080`, `8001` and `8545` are reserved for the web,
AI and blockchain services.

To prefer a particular API port for this session:

```powershell
.\run-renthub.ps1 -ApiPort 3002
```

The launcher prints the selected port. If you supply custom `API_BASE_URL` or
`SOCKET_URL` Dart defines for LAN access, use that same port in both URLs.

## Automatic MongoDB Atlas network access

For an Atlas `mongodb+srv://...mongodb.net` connection, the launcher uses MongoDB
Atlas CLI to allow the laptop's current public IPv4 address before starting any
backend services. Install Atlas CLI on each laptop, restart the terminal, and run:

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
