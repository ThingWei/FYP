# RentHub Backend Phase 4 Result

Date: 14 September 2026

## Outcome

RentHub now has a strict, MongoDB-backed simulated payment and transaction module. The backend owns every amount: a renter authorizes the total stored on a pending booking, the payment is captured only when the physical handover or service starts, and completion produces the appropriate deposit and Owner-settlement records.

No real funds are moved. Every transaction is explicitly marked as simulated so the feature remains suitable for the FYP demonstration.

## Implemented

### Payment authorization and capture

- Renter-only authorization for the renter's own pending booking
- Server-authoritative booking amount; arbitrary client amounts are ignored
- Card, FPX and wallet mock payment methods
- Required idempotency keys with conflict detection
- Owner approval blocked until an active authorization exists
- Authorization voided when a pending or approved booking is cancelled
- Capture at physical-item handover or service start
- Stable public transaction identifiers and gateway-reference placeholders

### Deposit and Owner settlement

- Full deposit-release transaction when an item is returned without a deduction
- Deposit-release and deposit-deduction records when a valid deduction applies
- Owner-settlement transaction after physical return confirmation
- Owner-settlement transaction after renter service-completion confirmation
- Booking payment states synchronized through `unpaid`, `authorized`, `captured`, `settled`, `partially_refunded`, `refunded` and `voided`

### Refunds and monitoring

- Administrator-only refunds against successful capture transactions
- Partial and full refunds
- Enforcement of the remaining refundable balance
- Idempotent retry support even after the transaction has been fully refunded
- Renter transaction history
- Booking-level history visible only to a participant or administrator
- Paginated administrator monitoring with booking, type and status filters

## Payment endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/payments/authorizations` | Authorize the stored total for a pending booking |
| `GET` | `/api/v1/payments/mine` | List the renter's transaction history |
| `GET` | `/api/v1/payments/booking/:bookingId` | List participant/admin booking transactions |
| `GET` | `/api/v1/payments` | Administrator transaction monitoring |
| `POST` | `/api/v1/payments/:id/refunds` | Administrator partial or full refund |

Authorization request example:

```json
{
  "bookingId": "RH-BKG-2026-09142",
  "method": "card",
  "idempotencyKey": "checkout:RH-BKG-2026-09142"
}
```

There is intentionally no `amount` field in the accepted contract. The API reads `booking.pricing.total` from MongoDB.

## Seed alignment

- `RH-BKG-2026-09142` is seeded as captured at RM570 with linked authorization and capture transactions.
- `RH-SVC-2026-03218` is seeded as authorized at RM472.50 with its linked authorization transaction.
- The seed remains idempotent and now verifies five users, 13 listings, two bookings, one rental and three payment records.

## Flutter integration contract

- `Booking.fromJson` and `Transaction.fromJson` parse stable backend public IDs.
- `LiveBookingRepository` creates physical or service booking payloads based on the stored listing type.
- `LiveBookingPaymentRepository` authorizes a booking without sending a client-controlled amount and reads its transaction history.
- The existing prototype remains mock-first by default. Setting `USE_MOCKS=false` activates live listing and booking repositories; the visual checkout still uses its mock payment controller until the booking-first UI sequence is migrated.

## Validation

- `npm test`: all 27 API tests passed.
- Booking/rental/payment integration tests: all 9 passed.
- `flutter analyze`: no issues found.
- `flutter test`: all 46 tests passed.
- `flutter build web`: succeeded, including the WebAssembly dry run.
- `git diff --check`: no whitespace errors.

Tests cover server-owned totals, authorization permissions, approval gating, capture, cancellation voiding, deposit release, Owner settlement, administrator monitoring, partial/full refunds, exhausted-balance retry behavior and idempotent seeding.

## Current limitations

- The gateway adapter is simulated and must not be represented as a real payment processor.
- Refund actions are administrator API operations; the administrator Flutter screen is not yet connected to this live endpoint.
- Multi-document lifecycle changes are not wrapped in MongoDB transactions because the current local setup uses standalone MongoDB. Configure a replica set before production use.

## Recommended next phase

Implement communication and notification APIs next. Bookings, rentals and payments now provide the stable identifiers and lifecycle events needed to create conversation threads and targeted notifications without inventing duplicate records in each screen.
