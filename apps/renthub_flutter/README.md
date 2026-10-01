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
flutter run --dart-define=USE_MOCKS=false `
  --dart-define=FIREBASE_ENABLED=true `
  --dart-define=API_BASE_URL=http://YOUR-LAN-IP:3000/api/v1 `
  --dart-define=SOCKET_URL=http://YOUR-LAN-IP:3000
```

For iOS, also enable Push Notifications and Background Modes -> Remote
notifications in Xcode and upload the APNs key in Firebase Console.
