# RentHub Flutter application

The renter and Owner interfaces are mobile-first. The Windows runner is useful
for local development only; Firebase Cloud Messaging is intentionally disabled
on Windows.

## Android and iOS Firebase setup

The repository currently contains Web and Windows runners. Generate the missing
mobile runners before configuring Firebase:

```powershell
flutter create --platforms=android .
```

Generate/configure iOS on macOS, then use the FlutterFire CLI from this folder:

```powershell
flutterfire configure --platforms=android,ios
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

For iOS, also enable Push Notifications and Background Modes → Remote
notifications in Xcode and upload the APNs key in Firebase Console.
