# RentHub Backend Phase 2 Result

Date: 14 September 2026

## Outcome

RentHub now has strict Listing and Availability modules backed by MongoDB. The API preserves the Flutter prototype's stable `l-*` identifiers and distinguishes physical-item rentals from service bookings at the schema, validation and service layers.

The Flutter application remains mock-first by default. Its existing live listing repository is compatible with the new API when `USE_MOCKS=false`; migration of the primary renter and Owner feature screens from shared mock state is intentionally deferred to the next integration phase.

## Implemented

- Strict listing schema with stable public identifiers
- Six protected marketplace categories matching Flutter
- Physical-item and service-specific validation
- Owner identity, ownership and active-account checks
- Draft creation, submission, moderation, editing and soft deactivation
- Public discovery that exposes active listings only
- Search, category, type, location, price, verification and date filters
- Separate availability records with:
  - unavailable date ranges
  - service weekly hours
  - minimum booking notice
  - booking buffer time
  - overlap and invalid-range prevention
- Administrator approval and rejection transitions
- Privacy-safe API serialization without MongoDB `_id` leakage
- Complete 13-listing catalog seed aligned with the Flutter UI
- Flutter parsing of stable `publicId` values
- Live repository create defaults for the legacy lightweight listing form

## Listing endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/v1/listings` | Search and filter active listings |
| `GET` | `/api/v1/listings/:id` | Read an active listing |
| `GET` | `/api/v1/listings/owner/mine` | Read the authenticated Owner's listings |
| `POST` | `/api/v1/listings` | Create a validated draft |
| `PATCH` | `/api/v1/listings/:id` | Edit an owned listing |
| `DELETE` | `/api/v1/listings/:id` | Soft-deactivate an owned listing |
| `POST` | `/api/v1/listings/:id/submit` | Submit a draft for review |
| `PATCH` | `/api/v1/listings/:id/moderation` | Approve or reject as administrator |
| `GET` | `/api/v1/listings/:id/availability` | Read active-listing availability |
| `PUT` | `/api/v1/listings/:id/availability` | Replace owned-listing availability |

Supported discovery query parameters are `page`, `limit`, `search`, `category`, `type`, `location`, `verified`, `minPrice`, `maxPrice`, `availableFrom` and `availableTo`.

## Listing rules

- Physical items require condition and at least one fulfilment method.
- Physical items are priced per day and may contain a security deposit and damage-waiver option.
- Services require a package name and duration.
- Services do not store physical condition, deposit, waiver or collection controls.
- New listings always begin as drafts.
- Owners cannot edit a listing while it is under review.
- Editing an active or rejected listing moves it back to draft.
- Only pending-review listings can be approved or rejected.
- Rejection requires a reason.
- Owners cannot edit another Owner's listing.

## Running with the Flutter repository toggle

After starting MongoDB, seeding the API and running the Express service, Flutter's live listing repository can be enabled with:

```powershell
flutter run -d chrome --web-port 8080 `
  --dart-define=USE_MOCKS=false `
  --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

The lightweight `ListingController` uses the live repository in this mode. The polished renter and Owner feature screens still use their shared prototype state until the next integration phase, preventing a partially migrated UI from breaking existing flows.

## Validation

- `npm test`: all 18 API tests passed.
- API tests cover role authorization, ownership, physical/service rules, lifecycle transitions, discovery filters, availability conflicts and seed idempotency.
- The seed test verifies five core users, all 13 listings and the approved camera pricing/deposit values.
- `dart analyze`: no issues found.
- `flutter test`: all 44 tests passed.
- `flutter build web`: completed successfully.
- npm dependency audit: zero vulnerabilities.

## Next phase

Implement strict Booking and Rental lifecycle modules. Then introduce a feature-level Flutter data source that can switch the primary renter and Owner flows between mock and live repositories without changing their UI components.
