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

