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
2. Run `docker compose up -d mongodb ganache`.
3. In `services/api`, run `npm install`, `npm run seed`, then `npm run dev`.
4. In `services/ai`, create a virtual environment, run `pip install -r requirements.txt`, then `uvicorn app.main:app --reload --port 8001`.
5. In `apps/renthub_flutter`, run `flutter pub get` and `flutter run --dart-define=USE_MOCKS=true`.

Mock mode is the Flutter default, so the UI can run without the other services. See `docs/architecture.md` for boundaries and extension points.

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
flutter run -d chrome --web-port 8080 --dart-define=USE_MOCKS=false --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SOCKET_URL=http://localhost:3000
```

Run the separate administrator portal:

```powershell
cd apps/renthub_flutter
flutter run -d chrome --web-port 3001 -t lib/main_admin.dart --dart-define=USE_MOCKS=false --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SOCKET_URL=http://localhost:3000
```

The seeded prototype accounts accept any password of at least six characters:

- `renter@renthub.my`
- `owner@renthub.my`
- `aina@renthub.my`
- `demo@renthub.my` for role switching
- `admin@renthub.my` in the administrator portal

Live mode persists users, listings, bookings, rentals, payments, messages, notifications, reviews, disputes, damage-waiver claims, loyalty accounts, reward ledgers, referrals, configurable loyalty rules, and administrator audit entries in MongoDB. Payments, booking-discount rewards, and dispute allocations remain simulated and use server-calculated or administrator-recorded amounts; no real financial or blockchain transfer is claimed.

