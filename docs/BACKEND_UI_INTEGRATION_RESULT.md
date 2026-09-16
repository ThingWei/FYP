# Backend to Final UI Integration Result

## Result

The final Flutter interfaces can now run in either local mock mode or live MongoDB-backed mode. Mock mode remains the default for offline demonstrations. Set `USE_MOCKS=false` to use the Express API and MongoDB.

## Live renter flow

- Creates or loads the MongoDB user profile at login.
- Loads the active listing catalogue from the API.
- Creates a booking before authorizing its server-calculated total.
- Displays live pending and historical bookings.
- Supports cancellation, physical return evidence, rental extensions, and service completion.
- Shows published listing reviews and supports completed-order review submission and editing.
- Loads MongoDB conversation threads, messages, and notifications.
- Sends messages over REST and receives new messages through Socket.IO.

## Live owner flow

- Loads owned listings, requests, rentals, conversations, and profile data.
- Creates physical-item or service drafts and submits them for moderation.
- Approves or rejects authorized booking requests.
- Handles physical handover, extension decisions, return confirmation, service start, and service delivery.
- Uses the same persistent messaging and notification records as the renter.
- Shows received reviews and supports suspicious-review flags.

## Live administrator flow

- Loads users, all listing states, bookings, rentals, payments, and message reports.
- Suspends accounts with a required reason.
- Approves or rejects submitted listings.
- Reviews booking and transaction records and issues simulated refunds.
- Resolves reported messages.
- Moderates persistent reviews and shows the flagged-review queue count.
- Clearly labels modules that do not yet have a backend phase instead of showing dummy records as live data.

## Safety and consistency decisions

- The client never submits a payment amount. The API calculates the authoritative booking total.
- A booking is created before payment authorization, and an idempotency key protects retries.
- Physical rentals and service bookings send different fields and expose different lifecycle actions.
- Failed login requests clear the temporary local API identity.
- Service bookings include an explicit appointment time and venue.
- Administrator queue endpoints require the administrator role.

## Validation

- `npm.cmd test`: 31 of 31 API tests passed.
- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub`: 52 of 52 Flutter tests passed.
- Live renter/owner web build: passed with `USE_MOCKS=false`.
- Live administrator web build: passed with `USE_MOCKS=false`.

The web compiler reports an upstream Socket.IO WebAssembly dry-run warning. Standard JavaScript web builds complete successfully.

## Start commands

See the repository `README.md` for the MongoDB, API, renter/owner, administrator, and seeded-account commands.
