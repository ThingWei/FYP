# RentHub application: quick operating guide

RentHub has a Renter/Owner app and a separate administrator portal. For the full setup checklist, supervisor walkthrough, shared-data explanation and troubleshooting, use the **[main operating guide](../../README.md)**.

These commands run from `apps/renthub_flutter`. The laptop must already have the project's private configuration, dependencies and AI runtime files.

For the complete priority-ordered platform test cases, manual execution sheets and
isolated automated checks, see the [testing guide](../../docs/testing/README.md).
Run its commands from the project root, not this application folder.

## Everyday commands

### Windows

```powershell
.\run-renthub.ps1 -Presentation
```

### Android: build/open the current app

Connect and unlock the phone, enable USB debugging, and approve the computer when asked.

```powershell
adb devices -l
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation
```

Replace `YOUR_DEVICE_ID` with the connected phone's ID. Its status must be `device`.

### Android: use the app already installed

```powershell
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation -ServicesOnly
```

Open RentHub on the phone yourself. This does not install app updates. Keep the terminal open; it monitors the connection and attempts to restore forwarding after reconnection.

### Administrator browser

```powershell
.\run-renthub.ps1 -Device chrome -Admin -Presentation
```

Use `edge` instead of `chrome` if preferred. The admin portal opens at `http://localhost:3001` and requires an administrator account. If the main phone launcher is already running, open this command in a second terminal and keep the main terminal open.

The Renter/Owner browser command is `.\run-renthub.ps1 -Device chrome -Presentation` and uses port 8080. Use Android for the camera scanner, current GPS location and phone push notification demonstration.

## What the launcher handles

- Checks the configured database and prepares temporary Atlas network access when needed.
- Starts or reuses the AI service, local blockchain and application server.
- Supplies the API and configured sign-in values, so the long manual Dart-define command is unnecessary.
- Connects Android's `localhost:3000` to the selected server port on the laptop.
- Keeps local blockchain data in `blockchain/.data/ganache`.

Presentation mode disables development reload for services this launcher starts. Compatible services started elsewhere retain their existing settings. Use one main backend host during a multi-device demonstration.

## Atlas: set up once per laptop

Normal startup does not need daily Atlas browser login after this setup. Keep the shared database connection in the private API `.env`. From this folder:

```powershell
# One-time administrator sign-in, completed in your browser
atlas auth login --profile default

# Read-only preview, then configure this laptop
.\setup-renthub-atlas.ps1
.\setup-renthub-atlas.ps1 -Apply

# Normal daily startup
.\run-renthub.ps1 -Presentation
```

Run setup separately on the other laptop after copying the updated scripts. Each laptop gets a separate, narrowly permitted automation account, stored in Windows Credential Manager. Do not copy credential files or put secrets in `.env`. Setup requires an administrator who can manage the existing RentHub project and its RentHub-only organization.

The launcher checks database connectivity first. If needed, it registers this network's individual IP for 24 hours using the saved automation account. **The 24-hour access message is normal and does not mean you must log in tomorrow.** Other laptops' entries remain untouched. Rerun the launcher after changing Wi-Fi.

Setup writes `ATLAS_PROFILE=renthub-launcher` and the verified `ATLAS_PROJECT_ID` in `services/api/.env`. Selection order is explicit `-AtlasProfile`, configured `ATLAS_PROFILE`, then `default`. Legacy personal profiles retain their usual login expiry; no browser login is opened automatically.

The original laptop's new secret expires **6 November 2027**. Each laptop displays its own date. To renew, sign into the administrator profile once and run:

```powershell
.\setup-renthub-atlas.ps1 -Apply -RenewSecret
```

After testing normal startup, retire the prior secret for this laptop in Atlas. An expired/revoked credential, missing permissions or unavailable Windows credential store still needs repair; the launcher explains which check failed. `-SkipAtlasAccess` is only for access managed separately and cannot fix an unreachable database.

See the [complete one-time setup and recovery guide](../../docs/ATLAS_AUTOMATION_SETUP_RESULT.md). Administration-API network access and database network access are separate: setup changes the former only after verifying the dedicated organization, and never opens database access to all IPs.

## Startup checks and slower laptops

```powershell
# Check service startup, then stop services created for this check
.\run-renthub.ps1 -Presentation -CheckOnly

# Allow more startup time on a slower laptop
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation -AiStartupTimeoutSeconds 300 -ApiStartupTimeoutSeconds 120
```

A readiness check verifies that required services respond; missing model warnings must still be reviewed. Check-only mode does not leave a new server running for the app.

If the default API port is occupied, the launcher may select an available fallback. Android still uses its stable app-facing port. You can prefer an API port with `-ApiPort 3002`.

Keep the laptop awake, online and the terminal open. An APK does not host the backend. An already connected wireless ADB device is supported, but pairing and reconnecting an expired wireless endpoint remain manual.

## Sign-in, photos and push configuration

The application's private server configuration is in `services/api/.env`. Keep the existing working settings when preparing another laptop; do not overwrite them with an example file.

- **Sign-in:** the launcher selects the configured Windows, Android or Web Auth0 client. Normal email/password and the separate Continue with Auth0 button follow the API's configured authentication mode.
- **Android callback:** the configured default is `com.weith.renthub://login-callback`. The exact application/callback setup is documented in the [Android Auth0 guide](../../docs/AUTH0_ANDROID_RESULT.md).
- **Photos:** listing images and protected documents use the configured API storage service. The current shared setup uses Supabase; database connectivity alone does not configure file access.
- **Push:** Android uses application ID `com.weith.renthub` and its own `android/app/google-services.json`. Firebase Admin credentials belong on the server. Do not confuse the client configuration with the private server key.
- **Windows:** in-app notifications are available; Android GPS and Firebase phone push are not enabled on Windows.

Do not put private server keys in Flutter code, screenshots or Git. iOS is not part of the current prepared Windows/Android demonstration workflow; generating a new iOS runner is not a normal startup step.

## Stop and recover

Use Ctrl+C in the launcher terminal and allow cleanup to finish. Ending Android debugging can leave the launcher in a continuing service session; keep it running if the installed app is still in use.

Close services that you recognise from their original terminal. The launcher does not terminate unrelated programs to free ports. Never delete local chain data or rerun database seeds as a routine recovery step.

See [common problems in the main guide](../../README.md#7-common-problems) and [launcher diagnostics](../../docs/LAUNCHER_RELIABILITY_RESULT.md) for the safe recovery steps and private log paths.
