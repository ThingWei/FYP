# RentHub

RentHub is a Malaysian rental marketplace for physical items and services. Renters can find and book a listing, Owners can manage listings and requests, and administrators can review accounts, listings and disputes.

**This README is the operating guide for students and supervisors.** Start with the daily startup instructions if this laptop has already been configured. First-time setup and developer references are further down.

## Quick links

- [Start RentHub](#1-start-renthub-on-a-configured-laptop)
- [Open the administrator portal](#2-open-the-administrator-portal)
- [Supervisor walkthrough](#3-demonstrate-the-main-features)
- [Full-platform test plan and execution sheets](docs/testing/README.md)
- [Stop RentHub safely](#4-finish-the-session)
- [Use another laptop](#5-use-renthub-on-another-laptop)
- [First-time setup](#6-first-time-setup)
- [Common problems](#7-common-problems)
- [Further documentation](#8-further-documentation)

## Before you start

For checking all modules in priority order, use the [testing guide](docs/testing/README.md).
It includes the full manual cases, blank private result sheets and an isolated
regression command. Automated passes and the real-device walkthrough are recorded
separately.

Have these ready:

- The configured project folder on the laptop.
- An internet connection. Sign-in, shared records, stored photos and map searches use online services.
- Your own RentHub sign-in. For a booking demonstration, use two separate prepared accounts: one Renter and the listing's actual Owner. An administrator account is needed for the admin portal.
- For Android: a data-capable USB cable, USB debugging enabled, and the phone unlocked to approve the debugging prompt.

Use identity-verified accounts for the booking walkthrough. Vehicle rental tests may also require an approved driving licence for that vehicle.

The laptop runs the application server, AI checks and demonstration blockchain. **Keep it awake and keep the launcher terminal open while testing.** Installing the APK on a phone does not keep these laptop services running by itself.

## 1. Start RentHub on a configured laptop

Open PowerShell in the project root, the folder containing this README. In VS Code, open the project and choose **Terminal > New Terminal**.

Go to the app folder:

```powershell
cd .\apps\renthub_flutter
```

Choose **one** startup option below. These commands use presentation mode, which avoids restarting newly launched services whenever source code changes.

### Windows application

```powershell
.\run-renthub.ps1 -Presentation
```

This opens the Renter/Owner application. Use the account's role switch to move between those two interfaces.

### Android application

Connect the phone and find its device ID:

```powershell
adb devices -l
```

The phone must show `device`, rather than `offline` or `unauthorized`. Replace `YOUR_DEVICE_ID` below with the value shown in the first column:

```powershell
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation
```

This starts the required services, builds/opens RentHub on the phone, and connects the phone to the laptop's server.

If the current app version is already installed, you can start just the services and open RentHub on the phone yourself:

```powershell
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation -ServicesOnly
```

Use the build/open command after pulling app changes. **Services-only mode does not update the installed app.** It keeps checking the phone connection and attempts to restore forwarding after reconnection.

An already paired and connected wireless ADB device can also be selected by its device ID. The launcher does not pair a phone or automatically reconnect an expired wireless endpoint.

### What successful startup looks like

The terminal checks database access, starts or reuses the local blockchain, starts or reuses AI assistance, and checks that the application server is ready. It then opens the selected app, or stays running in services-only mode.

The first startup on a new laptop may take longer because dependencies or the contract compiler are not cached. Later AI startup can also take time while models load. Wait for the readiness messages; an earlier `Application startup complete` message alone does not mean every required check has passed.

If startup fails, follow the specific error and the [common problems](#7-common-problems) below. Do not start extra copies of every service to try to fix it.

### Do I need `atlas auth login` every morning?

**No, after the one-time Atlas setup below.** Each laptop uses its own saved automation account instead of a personal browser session. Run your normal launcher command; no extra daily sign-in command is needed.

The launcher checks the database first. If this network needs access, it registers only the current public IP for 24 hours. The message **Atlas access registered for this public IP (expires in 24 hours)** is still expected: the network entry is temporary, while the automation credential lasts up to 365 days.

### One-time Atlas setup on each laptop

Pull/copy the updated launcher, `setup-renthub-atlas.ps1` and its `scripts` folder. Keep the existing private `services/api/.env` pointing to the shared RentHub database. Run these commands from `apps/renthub_flutter`:

```powershell
# One-time administrator sign-in; complete it yourself in the browser
atlas auth login --profile default

# Check the intended project without changing anything
.\setup-renthub-atlas.ps1

# Configure this laptop's separate automation account
.\setup-renthub-atlas.ps1 -Apply

# Everyday startup remains unchanged
.\run-renthub.ps1 -Presentation
```

Setup checks that the organization contains only RentHub's matched project. It permits its administration API to be used from changing networks, creates a laptop-specific **Project Network Access Manager** account and stores the credential in **Windows Credential Manager**. Database access remains restricted to individual IPs. The other laptop must run setup separately; do not copy CLI credential files or reuse another laptop's automation secret.

Setup selects `ATLAS_PROFILE=renthub-launcher` and the verified project ID in the private API `.env`; it does not change the database URI or other application secrets. An explicit `-AtlasProfile NAME` overrides this setting. Without either setting, older setups retain `default` and may still need personal login renewal.

This laptop's new secret expires **6 November 2027**. Other laptops show their own renewal date when configured. Before expiry, sign into the administrator profile once and run `.\setup-renthub-atlas.ps1 -Apply -RenewSecret`. Test normal startup, then retire the previous secret for that laptop in Atlas. Never paste secrets into chat or terminal commands. Do not disable the laptop service account while it is still in use.

After switching Wi-Fi during a running session, rerun the launcher. Internet access, Atlas availability and a valid saved credential are still required. See the [Atlas automation guide](docs/ATLAS_AUTOMATION_SETUP_RESULT.md) for recovery and verification limits.

## 2. Open the administrator portal

For a demonstration with a phone and administrator browser at the same time:

1. Keep the phone's main launcher terminal running.
2. Open a **second** PowerShell terminal in the project root.
3. Run:

```powershell
cd .\apps\renthub_flutter
.\run-renthub.ps1 -Device chrome -Admin -Presentation
```

For Microsoft Edge, replace `chrome` with `edge`.

The administrator portal opens at `http://localhost:3001`. Sign in with a prepared administrator account. This second launcher reuses compatible services already running; the first terminal remains responsible for keeping its services alive.

To use the Renter/Owner interface in a browser instead, run:

```powershell
.\run-renthub.ps1 -Device chrome -Presentation
```

That browser interface uses `http://localhost:8080`. Android remains the appropriate device for demonstrating camera scanning, current GPS location and phone push notifications. Windows does not offer Android GPS or phone push delivery.

## 3. Demonstrate the main features

Use the normal application screens. These steps create or update demonstration records, so choose prepared demo accounts and listings.

### Renter and Owner booking walkthrough

1. **Renter:** search for a listing owned by the other account. Check its photos, price, approximate area and reviews.
2. Choose dates and pickup/delivery, or the appropriate service arrangements. Review the agreement and charges.
3. Start checkout and complete **Demo Card**, **Demo FPX** or **Demo Wallet** payment within **10 minutes**. No real banking details are required. An unpaid checkout shows **Awaiting payment**, with no rental progress steps; reopening it does not restart the timer.
4. The request remains **awaiting Owner approval**. A successful demo payment does not confirm the booking.
5. **Actual Owner:** sign into the account that owns the listing, open Requests, review it and approve or reject it.
6. For a future physical rental, wait until the booked day. The Owner uses **Record handover** to review the actual condition and photos, the Renter uses **Submit Return**, and the Owner uses **Confirm Return** after inspecting the item. For a service, follow its service-completion actions instead.
7. Open the booking's agreement to show the accepted terms and supporting record/status updates.

Report any issue **before confirming final return or service completion**. After completion, neither participant can open a new dispute. Existing cases and reviews remain accessible. The booked end date alone does not close the dispute window: an overdue rental or a return still awaiting inspection may still need review. See the [dispute cutoff guide](docs/DISPUTE_COMPLETION_CUTOFF_RESULT.md).

Bookings and Owner Requests have compact cards: open **View details** for status, agreement and actions. They also have search, filter and sorting icons. Press Search/Enter after typing; use X to clear it. Filter by status, item/service, category, payment and rental dates. The filter dialog controls bookings per page. After payment, a horizontal icon strip shows rental progress in details; swipe sideways on the phone to see all steps. Log Out asks for confirmation. See the [booking interface guide](docs/BOOKING_INTERFACE_AND_CONFIRMATIONS_RESULT.md) and [payment countdown and details guide](docs/PAYMENT_WINDOW_AND_BOOKING_DETAILS_RESULT.md).

Switching a Renter account into Owner mode does not make that account the Owner of someone else's listing. Complete handover/return actions only at the appropriate stage. Existing expiry, identity and payment rules still apply.

Pending requests do not reserve physical-item dates. Different renters may request the same dates; approval resolves competing requests. The application prevents the same renter from unnecessarily submitting a duplicate request.

### Owner listing and AI assistance

1. Open **My Listings**, then **New Listing**. Choose a physical item or service.
2. For a physical item, choose the category, brand and model, or enter an unlisted product manually.
3. Add several clear photos and confirm the location. New physical locations need a map pin.
4. Choose **Suggest a daily price**. The explanation says whether the result is a rough guide. **Use this price** fills the field and closes the suggestion; you can still edit it.
5. Save an incomplete listing as a draft, or complete the required fields and submit it for review.
6. Tap a physical listing to browse its photo carousel and photo-check notes. Availability controls appear once the listing is approved and active.

### Administrator review

Open the relevant sidebar section to review verification submissions, listings, users, bookings, transactions, disputes, reports or reviews. Use **View details** to inspect a record. Read-only viewing does not approve or change it; moderation actions have their own confirmations.

Rental-price references show advertised prices from approved sources. They are separate from completed RentHub rentals. Use the existing update controls or the optional file-import section when appropriate; daily operation does not require importing a CSV.

### Explain the demonstration honestly

| Feature | What to explain to the supervisor |
| --- | --- |
| Payments | Test payment outcomes are simulated. No real money is collected. |
| Rental records | The blockchain runs locally on a demonstration network. It records supported physical-rental events; it does not certify an entire agreement or prove a user's identity. |
| Price suggestions | Estimates depend on available rental comparisons and the trained model. Some products have limited independent price evidence. Owners choose the final price. |
| Photo/KYC checks | Automated checks assist administrator review. Passing a photo check does not prove authenticity or rightful ownership. |
| Recommendations | Results use available browsing, saving and booking activity. Sparse history limits personalisation. |
| Demo listings | Listings marked as demonstrations are examples. They must not be presented as genuine completed-marketplace evidence. |

Do not submit someone else's identity document for a walkthrough. Use only documents and photos you are authorised to use.

## 4. Finish the session

1. Finish the action currently in progress; avoid closing the server during payment or approval.
2. Close secondary browser/client sessions first.
3. In each launcher terminal, use **Ctrl+C** and let cleanup finish. A Flutter debug terminal may first return control to the launcher's continuing service session; use Ctrl+C there to end it.
4. The launcher stops service processes it started. Services reused from another terminal are still controlled by that original terminal.

Closing the Android app or ending its Flutter debugging session can leave the launcher's services running. Keep that terminal open if you still need the installed app. Do not delete `.data` folders to shut down or reset the application; they contain local chain state, logs and other working files.

## 5. Use RentHub on another laptop

The two laptops can share account, listing and booking records through the **same MongoDB Atlas database**, and photos through the **same Supabase bucket**.

| Part | Where it lives | What the other laptop needs |
| --- | --- | --- |
| Accounts, listings, bookings and messages | MongoDB Atlas | The same configured database connection and compatible application secrets |
| Photos and protected documents | Supabase Storage | The same API-side storage settings and access |
| Trained AI files and OCR resources | Laptop | Copy the required runtime files to the same relative paths |
| Python environment and installed dependencies | Each laptop | Install locally; do not copy another laptop's `.venv` or `node_modules` |
| Demonstration blockchain | Local host | Use one active API/blockchain host for the complete multi-device walkthrough |

Copying source code alone does not copy model weights, private settings or a local blockchain. Atlas does not synchronise independent blockchain instances or live chat connections across two application servers.

For a consistent presentation, run the server/AI/blockchain on **one selected laptop** and connect the demonstration clients to that host. Use the other laptop as an alternative host after completing its setup, rather than approving the same workflow independently on two local chains.

Transfer private settings securely. Keep the existing identity/session secrets consistent where required; do not generate replacement identity-binding secrets simply because you changed laptops. See the [shared-database guide](docs/SHARED_DATABASE_ATLAS_SETUP.md) for the detailed checklist.

## 6. First-time setup

Skip this section for a laptop that already launches successfully. These steps are for the project maintainer; a supervisor using a prepared laptop can go directly to startup.

### Install/check the required tools

| Tool | Purpose |
| --- | --- |
| Flutter and its Dart SDK | Build and run the application |
| Node.js 22 or newer | Run the application server and local blockchain; the launcher checks this version |
| Python 3.11 | Create the AI environment used with this project's pinned requirements |
| Android SDK/ADB | Build and connect the Android app |
| Windows development tools reported by `flutter doctor` | Needed when building the Windows desktop app |
| Atlas CLI | Automatic Atlas network registration when the database is not already reachable |

Check the tools in a new PowerShell terminal:

```powershell
flutter doctor -v
node --version
py -3.11 --version
```

If Python says no suitable runtime is found, install Python 3.11 and reopen the terminal. Another Python version being installed does not make `py -3.11` available.

### Install project dependencies

Run these commands from the **project root**. Each `Push-Location` enters a folder and `Pop-Location` returns to the root.

```powershell
Push-Location .\services\api
npm.cmd ci
Pop-Location

Push-Location .\blockchain
npm.cmd ci
Pop-Location

Push-Location .\services\ai
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Pop-Location

Push-Location .\apps\renthub_flutter
flutter pub get
Pop-Location
```

Creating the environment and installing dependencies are separate steps. The launcher expects the Python executable at `services\ai\.venv\Scripts\python.exe`; manually activating it every day is unnecessary.

Optional YOLO-World support has additional setup described in the [AI guide](services/ai/README.md). The launcher does not download missing weights. Install/build output should be checked before proceeding when a command fails.

### Restore the private configuration

For an existing RentHub setup, obtain the working private configuration from the project maintainer. On a completely new setup, `services/api/.env.example` is a template for creating `services/api/.env`. **Do not overwrite an existing `.env` with the template.**

The important groups of settings are:

| Settings | What they control |
| --- | --- |
| `MONGODB_URI` | The Atlas database used for shared records |
| `ATLAS_PROFILE` / `ATLAS_PROJECT_ID` | The local Atlas automation profile and verified project; no credential values |
| Auth0 client settings and local-session settings | Sign-in for Windows, Android and browser clients |
| `KYC_IDENTITY_MATCH_SECRET` | Stable private identity matching across accounts |
| Supabase settings | Uploaded photos and protected documents |
| AI settings and local model paths | Pricing, recommendations and image checks |
| `BLOCKCHAIN_MODE` / `GANACHE_RPC_URL` | The configured local rental-record network |
| Firebase server credentials and Android configuration | Optional Android push notifications |
| Email delivery settings | Password-reset email |

After changing configuration, close the original launcher normally and restart it. A service reused from an older session keeps its previous settings until that service is restarted.

The launcher reads the API configuration and supplies the client startup values. You do not need to type the long Auth0/API `--dart-define` command manually. Normal sign-in and **Continue with Auth0** retain their configured behaviour.

For Android push, the client uses `apps/renthub_flutter/android/app/google-services.json`. The application server separately needs Firebase Admin credentials. These are different files; keep private server keys out of Git and Flutter's public configuration.

For document uploads, the API's verification-photo limit is 20 MiB by default. The Supabase bucket must allow at least that size. Ordinary uploads retain the 10 MiB default. Changing the limit does not bypass readability or identity checks.

### Restore AI runtime files

Copy the trained runtime files and the EasyOCR resources from the working laptop to the same relative locations. The usual model directory is `services/ai/models`, including its `easyocr` folder; custom paths must match the original runtime configuration.

Training datasets are **not required for ordinary demonstrations**. Trained model files and OCR resources are required for their corresponding AI features. Git does not include the generated weights or the Python environment. You do not need to retrain simply to start on another laptop.

AI configuration examples are in `services/ai/.env.example`. The current launcher starts Uvicorn using its inherited environment and model-path defaults; it does not automatically load that AI example file as runtime configuration. Preserve any custom AI environment settings used on the working laptop. See the [AI guide](services/ai/README.md) before changing model paths or retraining.

### Check the setup

From the project root:

```powershell
.\apps\renthub_flutter\run-renthub.ps1 -Presentation -CheckOnly
```

This performs startup/readiness checks and then stops services created for the check. It does not open the app or keep a new demonstration server running. After a successful check, choose the normal Windows, Android or administrator startup command above.

Missing optional-model warnings still need review before promising that feature in the presentation. A running server does not mean every AI artifact is installed or independently validated.

**Do not run database seed/import commands as a routine startup step.** They change data and are not a fix for an empty or incorrectly configured database. Ask the maintainer before replacing records or importing demonstrations.

## 7. Common problems

| What you see | What to do |
| --- | --- |
| RentHub cannot connect | Check that the main launcher is still running and reports its server ready. On Android, check the selected device ID and debugging connection. An installed app alone cannot start the laptop's server. |
| Atlas asks for login | Complete the one-time automation setup on this laptop. A personal `default` profile can expire; a configured automation profile needs its own credential renewal, not daily browser login. Follow the specific permission/network guidance. |
| Accounts or listings are missing on the other laptop | Check that its API uses the same Atlas connection **and database name**. Restart after configuration changes. Do not seed new data to mask a wrong connection. |
| Photos are missing | Check the API's Supabase configuration and internet connection. Shared database rows alone do not provide access to a different storage bucket. |
| Android shows `unauthorized` or `offline` | Unlock the phone, approve debugging, and reconnect the data cable. Check `adb devices -l` again. Use the currently connected ID; a wireless ID may change. |
| The phone disconnects | Keep the services terminal open. Reconnect/authorise the same device. Services-only mode checks reconnection; a different device ID requires restarting with that ID. |
| Python environment is missing | Create `.venv` inside `services/ai` with Python 3.11 and install `requirements.txt` there. Reopen the terminal after installing Python. |
| AI startup is slow | Wait for readiness. For a slower laptop, use `-AiStartupTimeoutSeconds 300 -ApiStartupTimeoutSeconds 120`. If a process exits, check its log rather than repeatedly extending the deadline. |
| A model or OCR check is unavailable | Check the runtime files and paths. Do not start training or enable automatic downloads just to suppress a warning. |
| Price suggestion is unavailable | Enter a price manually. Some products lack suitable rental comparisons. Adding demo listings does not establish real rental-price accuracy. |
| A pending listing cannot manage availability | Availability opens after the listing is approved and active. Pending listings are still under review. |
| A verification photo is rejected | Check the specific rescan message. Clear details, correct sides and matching numbers are required. Verification photos up to 20 MiB are supported with the matching bucket limit. Do not send an unmasked identity photo in a bug report. |
| No current-location button on Windows | The GPS shortcut is for Android. On Windows, search the map and select a pin. |
| No phone push notification | Use Android, enable notifications in the app/phone, and check Firebase configuration. Windows retains in-app notifications rather than Android push delivery. |
| Wrong blockchain chain ID | RentHub expects local chain ID 1337. Check which program owns the configured network and close that program normally if appropriate, then rerun the launcher. Do not delete chain data or kill an unidentified process. |
| A port is already in use | Read the launcher's message. It can choose an alternative API port while keeping Android's app-facing port stable. For incompatible AI/blockchain listeners, close the identified original service before retrying. |
| Windows build fails | Run `flutter doctor -v` and resolve its Windows toolchain findings. Refer to the first meaningful compiler error, rather than only the final "build failed" line. |

The usual private logs are:

- API: `services/api/.data/logs/launcher-api-error.log` (or `launcher-api-PORT-error.log`).
- AI: `services/ai/.data/logs/launcher-ai-error.log`.
- Blockchain: `blockchain/.data/logs/launcher-ganache-error.log`.

For help, provide the first relevant error and whether you used Windows, Android or the admin browser. Remove passwords, connection strings, tokens, identity data and other private details before sharing logs.

## 8. Further documentation

| Guide | Use it for |
| --- | --- |
| [Launcher reliability](docs/LAUNCHER_RELIABILITY_RESULT.md) | Startup checks, presentation mode, reconnection and process ownership |
| [Shared database setup](docs/SHARED_DATABASE_ATLAS_SETUP.md) | Atlas, another laptop, compatible private settings and storage |
| [Flutter application](apps/renthub_flutter/README.md) | App commands and client-specific configuration |
| [Android Auth0](docs/AUTH0_ANDROID_RESULT.md) | Native sign-in callbacks and Android setup |
| [Maps and notifications](docs/MAPS_AND_PUSH_NOTIFICATIONS_RESULT.md) | Map/push integration and its limits |
| [Checkout and agreements](docs/SIMULATED_CHECKOUT_AND_AGREEMENT_RESULT.md) | Payment simulation, approval and supporting rental records |
| [AI service](services/ai/README.md) | Model files, evaluation, training and missing-model behaviour |
| [AI readiness](docs/AI_VALIDATION_AND_DEMO_READINESS_RESULT.md) | Measured results and remaining real-data gaps |
| [Blockchain](blockchain/README.md) | Local contract setup and technical demonstration limits |
| [Latest UI improvements](docs/FRIENDLY_COPY_AND_LISTING_PHOTO_REVIEW_RESULT.md) | Pricing copy, photo carousel and availability controls |

### For developers

The main folders are:

```text
apps/renthub_flutter/   Renter, Owner and administrator interfaces
services/api/          Application rules, shared data access and live messaging
services/ai/           Pricing, recommendation and image-check assistance
blockchain/            Local physical-rental record contract
packages/api_contracts/ API and event contracts
```

The live Flutter app calls RentHub's Express API. The API handles database, storage, AI and blockchain access. Keep server credentials out of the Flutter app.

For isolated UI preview, the explicit `--dart-define=USE_MOCKS=true` option uses the mock application. Those screens do not demonstrate live persistence, AI, phone push or blockchain integration. Use the normal launcher flow for the supervisor's integrated-system walkthrough.

After code changes, use the relevant Flutter/API/AI/blockchain tests. Do not run production-data scripts or real account actions as a substitute for isolated regression tests.
