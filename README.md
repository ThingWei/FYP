# RentHub

RentHub is a multi-category rental marketplace monorepo. The Flutter client is the only public client; it calls the Node API, which coordinates MongoDB, the AI service, Firebase adapters, and the local Ganache blockchain.

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

For Auth0 bearer authentication, Firebase Storage uploads, required Auth0 claims, and Windows callback configuration, see [Backend Phase 12](docs/BACKEND_PHASE_12_RESULT.md).

For the real Atlas/Auth0/Firebase preflight and restart-safe production E2E drill, see [Backend Phase 13](docs/BACKEND_PHASE_13_RUNBOOK.md).

The seeded local accounts use the password `RentHub123!` (rerun the seed
command after pulling authentication changes):

- `renter@renthub.my`
- `owner@renthub.my`
- `aina@renthub.my`
- `demo@renthub.my` for role switching
- `admin@renthub.my` in the administrator portal

Live mode persists users, listings, bookings, rentals, payments, messages, notifications, reviews, disputes, damage-waiver claims, loyalty accounts, reward ledgers, referrals, configurable loyalty rules, AI evidence, local contract references, and administrator audit entries in MongoDB. Payment-provider transfers and dispute allocations remain simulated. Ganache transactions are local prototype records only and never represent real currency.

The recommendation endpoint works without a trained artifact by naming its content/rating fallback. Pricing, YOLO item classification, and EfficientNet risk scoring report themselves unavailable until their training scripts produce evaluated artifacts. See `services/ai/README.md` and `blockchain/README.md`.

