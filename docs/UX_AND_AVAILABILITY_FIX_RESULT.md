# RentHub onboarding, discovery, and availability result

Last verified: 4 October 2026

## Outcome

The three reported issues are fixed across Flutter, Express, and MongoDB:

1. onboarding is shown only until it is completed or skipped once;
2. Home category filtering preserves personalized AI recommendation ranking while
   Explore and non-AI sorts retain normal marketplace discovery behaviour; and
3. Owner blackouts and accepted booking occupancy now use one availability view
   in discovery, booking UI, and authoritative booking conflict checks.

No mock listing or booking data was introduced by these changes.

## First-launch behaviour

Flutter stores only a non-sensitive Boolean named
`renthub_onboarding_completed` in `SharedPreferences`.

| Launch state | Destination |
| --- | --- |
| First launch | Splash, then onboarding |
| Onboarding completed or skipped, signed out | Login |
| Onboarding completed, restorable session | Renter/Owner application |
| Logout | Login, without replaying onboarding |
| Later application restart | Login or restored application, without onboarding |

Access and refresh credentials remain in the existing secure-session storage.
The onboarding preference does not contain credentials or profile information.

## Home recommendations and Explore discovery

Flutter now treats recommendation mode as a deliberate Home-only path:

```text
Home + Recommended + filters
  -> GET /api/v1/listings/recommended?<same filters>
  -> Express filters eligible live candidates
  -> FastAPI ranks only those candidates
  -> recommendation metadata and reason reach the listing cards

Explore, or Home + a non-AI sort
  -> GET /api/v1/listings?<filters and sort>
  -> neutral marketplace result heading
```

Supported recommendation filters are search, category, listing type, location,
verified Owner, promotion, price range, and an availability date range. Own
listings, blocked Owners, restricted accounts, and unavailable dates are removed
before candidates reach the recommendation service. This prevents a category
chip such as Devices or Vehicles from silently falling back to a generic
marketplace request.

`Listing` now retains `recommendationAdapter`, availability, final score,
content score, collaborative score, and the human-readable recommendation
reason. Recommendation reasons are displayed only when AI-ranked results are
actually being shown. Price, rating, and newest sorts do not carry an AI label.

## Unified availability

`GET /api/v1/listings/{listingId}/availability` returns the existing weekly
policy plus two range collections:

- `unavailableRanges`: the renter-facing union of Owner blackouts and booking
  occupancy;
- `manualUnavailableRanges`: only Owner-authored blackouts, for the Owner
  availability editor.

Each range has `start`, exclusive `end`, `source`, optional `reason`, and
`allDay`. The endpoint also returns `nextAvailableDate`. It never exposes the
other renter's identity or booking identifier.

### Status rules

| Booking status | Physical listing occupancy |
| --- | --- |
| `pending` | No hard block |
| `approved` | Blocks |
| `active` | Blocks |
| unresolved `disputed` | Blocks |
| `completed` | Released |
| `cancelled` | Released |
| `rejected` | Released |
| `expired` | Released |

Pending requests remain soft holds so multiple renters can request the same
dates. The Owner decision path performs the authoritative conflict check again;
therefore only the first compatible request can be approved.

### Date semantics

API availability ranges use an exclusive end. A physical rental from 20 to 22
September occupies the three calendar days and is exposed as:

```json
{
  "start": "2026-09-20T00:00:00.000Z",
  "end": "2026-09-23T00:00:00.000Z",
  "source": "booking",
  "allDay": true
}
```

Consequently, selecting 22 September overlaps and selecting 23 September as the
first rental day is allowed. The same booking-derived ranges are used by normal
Explore queries and personalized recommendation candidate filtering.

## Flutter booking experience

The booking screen now loads current server availability before enabling a
request. It provides distinct loading, error/retry, available, unavailable, and
next-available states. Occupied days are disabled in the date picker, an inline
message explains a conflicting selection, and availability is fetched again
immediately before the confirmation flow. The server remains authoritative if
availability changes between those two requests.

The Owner editor reads `manualUnavailableRanges`; it cannot accidentally save a
booking-derived range as an Owner blackout.

## API contract

`packages/api_contracts/openapi.yaml` now documents the recommendation filters
and the merged listing availability response, including exclusive-end semantics
and range source values.

## Validation

- Recommendation integration: Home category candidates are filtered before AI;
  truthful fallback metadata remains available.
- Availability integration: approved, active, and disputed physical bookings
  block dates; completed, cancelled, rejected, and expired bookings release
  dates; adjacent ranges are accepted.
- Two-renter race integration: two pending and authorized requests were created
  for the same dates; the first approval succeeded and the second returned
  `AVAILABILITY_CONFLICT`.
- Flutter startup tests cover first launch, completing onboarding, returning
  signed-out and authenticated launches, logout, and a simulated restart.
- Flutter listing tests cover Home Devices and Vehicles recommendation filters,
  Explore normal discovery, neutral non-AI sort labels, recommendation metadata,
  exclusive-end range calculations, and booking-screen conflict rendering.

Repository checks completed:

- `node --test --test-concurrency=1` with `AUTH_MODE=mock`,
  `STORAGE_MODE=local`, and `BLOCKCHAIN_MODE=disabled`: 112 passed, 0 failed,
  3 intentionally skipped.
- `flutter pub get`: completed successfully.
- `dart format --output=none --set-exit-if-changed lib test`: 144 files
  checked, 0 changed.
- `flutter analyze`: no issues found.
- `flutter test`: 103 passed, 0 failed, 2 pre-existing skips.
- `flutter build web`: succeeded. Its advisory WebAssembly dry run reports the
  existing `socket_io_common` JavaScript-interop limitation; the normal web
  build is valid.

## Known limitations

- Pending requests intentionally do not reserve inventory. Availability can
  change until Owner approval, which is why the server-side approval recheck is
  required.
- The booking screen fetches availability on entry and immediately before
  submission. It does not yet subscribe to a live availability Socket.IO event
  while the calendar is open.
- Physical rentals are calendar-day based. A service booking can retain precise
  time data in the API, while the current mobile date selector presents
  day-level availability.
- `SharedPreferences` is suitable for the non-sensitive onboarding-completed
  flag. Authentication credentials continue to require secure storage.
