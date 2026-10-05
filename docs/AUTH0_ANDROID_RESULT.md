# RentHub Android Auth0 result

Date: 5 October 2026

## Implemented architecture

Android now uses the same RentHub authentication architecture as Windows and
Web:

```text
RentHub Android
  -> Auth0 Universal Login in the system browser
  -> com.weith.renthub://login-callback
  -> OAuth state validation
  -> authorization-code + PKCE S256 exchange
  -> access token in memory + refresh token in secure storage
  -> POST /api/v1/users/session
  -> MongoDB RentHub profile, normalized roles, and activeRole
```

The Android browser and callback transport use `url_launcher` and `app_links`.
Android does not start a localhost callback server and does not use the Windows
`rundll32` browser launcher. Windows keeps its loopback callback and Web keeps
the Auth0 SPA SDK.

The callback is configurable with `AUTH0_ANDROID_CALLBACK_URL`; its default is
`com.weith.renthub://login-callback`. The launcher passes the URI scheme and
host to Android manifest placeholders, so the Dart callback and Android intent
filter stay aligned.

## PKCE and callback validation

Every login generates a cryptographically random OAuth `state` and PKCE
`code_verifier`. The authorization request sends an S256 `code_challenge` and
requests `openid profile email offline_access`. RentHub ignores unrelated deep
links and accepts only the configured scheme, host, port, and path. It validates
the returned state, Auth0 error, and authorization code before `/oauth/token` is
called.

The login screen exposes **Cancel Auth0 Login** while the browser flow is
pending. Cancellation closes the pending callback operation and re-enables the
login actions. Closing a browser without returning a callback cannot be
detected reliably by a custom URI flow; the user can cancel in RentHub, and the
gateway also has a three-minute timeout.

## Secure session restoration

`flutter_secure_storage` persists only:

```text
renthub_auth0_session_provider
renthub_auth0_session_refresh_token
```

Access tokens remain in memory. On restart, RentHub exchanges the saved refresh
token, persists a rotated replacement when supplied, and calls
`/api/v1/users/session`. An `invalid_grant`, 401, or 403 clears persisted Auth0
credentials. Temporary Auth0/network failures retain the refresh token for a
later retry. Logout clears both in-memory and persisted Auth0 credentials plus
the RentHub session, preventing restoration after restart.

This is independent of Firebase and works with `FIREBASE_ENABLED=false`.

## Required API `.env` values

Configure `services/api/.env` without committing real credentials:

```dotenv
AUTH_MODE=hybrid
AUTH0_ISSUER_BASE_URL=https://YOUR_TENANT.auth0.com/
AUTH0_AUDIENCE=https://api.renthub.local
AUTH0_ANDROID_CLIENT_ID=YOUR_ANDROID_NATIVE_APPLICATION_CLIENT_ID
AUTH0_ANDROID_CALLBACK_URL=com.weith.renthub://login-callback
```

`AUTH_MODE=auth0` is also supported. `hybrid` keeps local MongoDB/JWT login and
shows **Continue with Auth0** as a separate choice.

## Auth0 Dashboard setup

Create or use an Auth0 application of type **Native** for Android. Then:

1. Put its client ID in `AUTH0_ANDROID_CLIENT_ID`.
2. Add exactly `com.weith.renthub://login-callback` to **Allowed Callback URLs**.
3. Enable the **Authorization Code** and **Refresh Token** grant types.
4. For the RentHub API with identifier `https://api.renthub.local`, enable
   **Allow Offline Access**.
5. Keep Refresh Token Rotation enabled, or deliberately configure reusable
   refresh tokens; RentHub supports both rotated and unrotated responses.
6. Keep the Android application ID as `com.weith.renthub`.

No Android logout URL is required by this implementation because RentHub logout
clears local credentials and does not open Auth0 hosted logout. The browser may
therefore retain Auth0 SSO and offer the same account on the next explicit
**Continue with Auth0** action; this does not silently restore a logged-out
RentHub session.

## Running on Android

From `apps/renthub_flutter`:

```powershell
.\run-renthub.ps1 -Device <ANDROID_DEVICE_ID>
```

The launcher retains `adb reverse tcp:3000 tcp:3000`, so a USB-debugging device
can use `http://localhost:3000`. Auth0 internet traffic does not use ADB. If ADB
reverse is unavailable, pass reachable LAN endpoints after allowing the API
through the host firewall:

```powershell
.\run-renthub.ps1 -Device <ANDROID_DEVICE_ID> `
  --dart-define=API_BASE_URL=http://<PC-LAN-IP>:3000/api/v1 `
  --dart-define=SOCKET_URL=http://<PC-LAN-IP>:3000
```

## Automated verification

`test/auth0_persistence_test.dart` covers the Android custom callback, ignored
unrelated links, PKCE authorization parameters, exact redirect URI, OAuth state
rejection, authorization-code exchange, secure refresh-token persistence, token
restoration/rotation, invalid-grant cleanup, temporary failure retention,
logout, Windows loopback login, and hybrid restoration priority.

Final automated results:

- focused Auth0 persistence/deep-link tests: 10 passed;
- Flutter analyzer: no issues;
- complete Flutter suite: 113 passed, 2 intentionally skipped;
- Android debug APK: built successfully at
  `apps/renthub_flutter/build/app/outputs/flutter-apk/app-debug.apk`;
- complete Express suite in isolated test configuration
  (`AUTH_MODE=mock`, local storage, blockchain disabled): 125 passed,
  3 optional live E2E tests skipped;
- complete FastAPI suite: 31 passed with 2 third-party deprecation warnings;
- Dart format check, PowerShell parser check, and `git diff --check`: passed.

The developer `.env` uses live Auth0/Supabase/Ganache settings, so the Express
suite was deliberately run with process-local test overrides. No `.env` value
was modified.

## Physical-device E2E status and procedure

A real Auth0 tenant login cannot be claimed from automated tests. `adb` was not
installed on the validation machine, so no physical-device flow was run.
Perform this tenant/device check after entering the Dashboard values above:

1. Connect a USB-debugging Android device and confirm it with `adb devices`.
2. Start RentHub with the launcher and tap **Continue with Auth0**.
3. Sign in in Universal Login and confirm the deep link returns to RentHub.
4. Confirm `/users/session` loads the same MongoDB user and active renter/owner
   role.
5. Fully close and reopen the app; it should restore without another browser
   login.
6. Log out, fully close and reopen; it must remain logged out.
7. Repeat once by cancelling the browser flow and using **Cancel Auth0 Login**
   to confirm the UI becomes usable again.

Known limitation: a custom URI scheme can be claimed by another installed app.
OAuth state and PKCE prevent that app from completing or exchanging this
client's login, but an HTTPS Android App Link with a verified domain would offer
stronger callback ownership for a production deployment.
