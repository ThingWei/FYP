# RentHub

RentHub is a multi-category rental marketplace monorepo. The Flutter client is the only public client; it calls the Node API, which coordinates MongoDB, Supabase Storage, the AI service, optional Firebase push delivery, and the local Ganache blockchain.

## Projects

- `apps/renthub_flutter` - Flutter mobile/web application using Provider MVC
- `services/api` - Express/Mongoose MVC API and Socket.io gateway
- `services/ai` - FastAPI model-adapter service
- `blockchain` - Solidity rental agreement and Hardhat tests
- `packages/api_contracts` - OpenAPI contract and shared socket event names

## Quick start

1. Copy each `.env.example` to `.env`.
2. Run `docker compose up -d mongodb ganache ai api` for the complete backend.
3. In `services/api`, run `npm install`, `npm run seed`, then `npm run dev`.
4. In `services/ai`, create a virtual environment, run `pip install -r requirements.txt`, then `uvicorn app.main:app --reload --port 8001`.
5. In `apps/renthub_flutter`, run `flutter pub get` and `flutter run`.

The Flutter application defaults to the live Express/MongoDB repositories. Mock
mode is available only when explicitly launched with `--dart-define=USE_MOCKS=true`
for isolated UI previews and tests. See `docs/architecture.md` for boundaries and
extension points.

### Combined Windows launcher

After MongoDB is running and the API `.env` is configured, the Flutter launcher
starts the local Ganache blockchain, FastAPI AI service, Express API, and Flutter
application together. Ganache is started when `BLOCKCHAIN_MODE=ganache`:

```powershell
cd apps\renthub_flutter
.\run-renthub.ps1
```

The AI service uses `services\ai\.venv\Scripts\python.exe`; activating the
virtual environment manually is not required. Use `-Device chrome`, `-Admin`,
`-CheckOnly`, `-SkipAi`, or `-SkipBlockchain` when needed. Services already
running on their configured ports are reused and left running. Processes created
by the launcher are stopped when Flutter exits. Local blockchain state persists
under `blockchain\.data\ganache`. Launcher logs are stored in each service's
`.data\logs` directory.

When `AUTH_MODE=auth0` or `AUTH_MODE=hybrid`, the launcher also reads the Auth0 domain, audience,
client ID, callback, and database connection from `services\api\.env` and adds
the Flutter Dart defines automatically. Configure `AUTH0_WINDOWS_CLIENT_ID` for
the Native application and `AUTH0_WEB_CLIENT_ID` for the Web SPA. The standard
Windows command remains `.\run-renthub.ps1`; use `-Device chrome` for the Web
client and add `-Admin` for the administrator portal.

Use `AUTH_MODE=hybrid` when the normal email/password forms should use RentHub's
local MongoDB sessions while the separate **Continue with Auth0** action uses
Auth0 Universal Login. `AUTH_MODE=local` disables the Auth0 action, while
`AUTH_MODE=auth0` is retained for deployments that accept only Auth0 tokens.

### Local account sessions

For MongoDB-backed renter, Owner, and administrator accounts, use signed local
JWT sessions instead of development identity headers:

```dotenv
AUTH_MODE=local
LOCAL_JWT_SECRET=replace-with-a-random-secret-of-at-least-32-characters
LOCAL_ACCESS_TOKEN_MINUTES=15
LOCAL_REFRESH_TOKEN_DAYS=30
```

Generate a secret locally with
`node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` and
store it only in the ignored `services/api/.env`. The Flutter client stores the
access and rotating refresh tokens in platform secure storage, restores the
session after restart, and refreshes short-lived access tokens automatically.
Logout, password reset, self-deactivation, suspension, and banning revoke the
affected MongoDB session records. `AUTH_MODE=mock` is retained only for API
tests and explicit UI prototype runs.

### Password-reset email

Local MongoDB accounts can use Nodemailer with Gmail SMTP to deliver single-use
six-digit reset codes. Enable Google two-step verification, create an App
Password for RentHub, and add these values to `services\api\.env`:

```dotenv
EMAIL_MODE=smtp
EMAIL_FROM=RentHub <your.personal@gmail.com>
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your.personal@gmail.com
SMTP_PASSWORD=your-16-character-google-app-password
PASSWORD_RESET_SECRET=replace-with-a-random-secret-of-at-least-32-characters
PASSWORD_RESET_TTL_MINUTES=10
PASSWORD_RESET_COOLDOWN_SECONDS=60
PASSWORD_RESET_MAX_ATTEMPTS=5
```

Use the Google App Password without spaces, never the normal Gmail password.
The SMTP password and reset secret must not be committed. Restart the API after
changing `.env`. `EMAIL_MODE=resend` remains supported for a verified Resend
sender, while Auth0 accounts continue to use Auth0's hosted reset email.

### Supabase file storage

RentHub stores uploaded listing images and protected evidence in a private
Supabase Storage bucket while MongoDB retains the file metadata and ownership
records. Create a private `renthub-files` bucket, then configure only the API:

```dotenv
STORAGE_MODE=supabase
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SECRET_KEY=your-server-secret-key
SUPABASE_STORAGE_BUCKET=renthub-files
MAX_UPLOAD_BYTES=10485760
```

Never put `SUPABASE_SECRET_KEY` in Flutter or commit it. The mobile/web client
continues to upload and download through authenticated RentHub API routes. Run
`npm.cmd run preflight -- --write-probe` to verify bucket lookup, upload, and
cleanup. Firebase remains optional for `FCM_MODE=firebase`; it is no longer
required for file storage.

### OpenStreetMap location provider

Google Maps is not used. The API location boundary targets OpenStreetMap
Nominatim and enforces the public service's one-request-per-second minimum:

```dotenv
MAPS_MODE=openstreetmap
OPENSTREETMAP_NOMINATIM_URL=https://nominatim.openstreetmap.org
OPENSTREETMAP_USER_AGENT=RentHub/1.0 (contact: your-email@example.com)
OPENSTREETMAP_MIN_INTERVAL_MS=1000
```

The current Flutter screens collect text locations and do not render an
interactive map. Any future map screen must use OpenStreetMap tiles, show
`© OpenStreetMap contributors`, and avoid background tile downloads.

## Run with the MongoDB backend

Start MongoDB and the API first:

```powershell
docker compose up -d mongodb
cd services/api
Copy-Item .env.example .env
npm.cmd run seed
npm.cmd run dev
```

Run the renter and owner application on the CORS-enabled port:

```powershell
cd apps/renthub_flutter
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SOCKET_URL=http://localhost:3000
```

Run the separate administrator portal:

```powershell
cd apps/renthub_flutter
flutter run -d chrome --web-port 3001 -t lib/main_admin.dart --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SOCKET_URL=http://localhost:3000
```

For the earlier Auth0/Firebase implementation history and Windows callback configuration, see [Backend Phase 12](docs/BACKEND_PHASE_12_RESULT.md).

For the earlier Atlas/Auth0/Firebase preflight and restart-safe production E2E drill, see [Backend Phase 13](docs/BACKEND_PHASE_13_RUNBOOK.md); substitute the current Supabase settings when following its storage steps.

The seeded local accounts use the password `RentHub123!` (rerun the seed
command after pulling authentication changes):

- `renter@renthub.my`
- `owner@renthub.my`
- `aina@renthub.my`
- `demo@renthub.my` for role switching
- `admin@renthub.my` in the administrator portal

Live mode persists users, listings, bookings, rentals, payments, messages, notifications, reviews, disputes, damage-waiver claims, loyalty accounts, reward ledgers, referrals, configurable loyalty rules, AI evidence, local contract references, and administrator audit entries in MongoDB. Payment-provider transfers and dispute allocations remain simulated. Ganache transactions are local prototype records only and never represent real currency.

Ordinary accounts always have both Renter and Owner capabilities; the selected role is only the current interface. Administrators remain separate and admin/public mixed claims are rejected. Before deploying this invariant for existing data, run `npm.cmd run migrate:marketplace-roles` in `services/api` for a dry run, back up MongoDB, then use `npm.cmd run migrate:marketplace-roles -- --apply` after reviewing all manual-security-review counts.

The recommendation endpoint works without a trained artifact by naming its content/rating fallback. Pricing, YOLO item classification, and EfficientNet risk scoring report themselves unavailable until their training scripts produce evaluated artifacts. See `services/ai/README.md` and `blockchain/README.md`.

