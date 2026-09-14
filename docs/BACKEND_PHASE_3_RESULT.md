# RentHub Backend Phase 3 Result

Date: 14 September 2026

## Outcome

RentHub now has strict Booking and Rental lifecycle modules backed by MongoDB. Booking prices are calculated from the stored listing snapshot, approved bookings lock availability, and physical-item rentals remain separate from service-order completion flows.

The Flutter prototype remains mock-first while these API contracts are stabilized. The next integration phase can replace the mock booking repository without changing the visual flow.

## Implemented

### Booking requests

- Renter-only booking creation for active listings
- Prevention of booking an owned or blocked-Owner listing
- Server-calculated Malaysian Ringgit totals
- Inclusive daily pricing for physical-item rentals
- Security-deposit and optional damage-waiver pricing
- Five-percent service platform fee
- Service end-time calculation from package duration
- Renter booking history and Owner incoming-request views
- Participant-only booking details
- Owner approval or reason-required rejection
- Renter cancellation before the rental becomes active
- Revalidation of listing status and availability during approval
- Approved/active booking conflict protection
- Owner-configured blackout enforcement

### Physical rentals

- Scheduled rental creation after booking approval
- Owner handover confirmation with condition evidence
- Activation of the linked booking and rental
- Renter extension request
- Owner extension approval or reason-required rejection
- Extension conflict revalidation
- Renter return evidence submission
- Owner return confirmation and deposit-deduction validation
- Synchronized booking/rental completion

### Services

- Scheduled service-order creation after approval
- Owner service-start action
- Owner delivery-complete action
- Renter service-completion confirmation
- No physical handover, return or condition evidence on services

## Booking endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/bookings` | Create a pending request |
| `GET` | `/api/v1/bookings/mine` | Renter booking history |
| `GET` | `/api/v1/bookings/owner` | Owner booking requests/orders |
| `GET` | `/api/v1/bookings/:id` | Participant/admin booking details |
| `PATCH` | `/api/v1/bookings/:id/decision` | Owner approval or rejection |
| `POST` | `/api/v1/bookings/:id/cancel` | Renter cancellation |

## Rental endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/v1/rentals/mine` | Renter rentals/service orders |
| `GET` | `/api/v1/rentals/owner` | Owner rentals/service orders |
| `GET` | `/api/v1/rentals/:id` | Participant/admin lifecycle details |
| `POST` | `/api/v1/rentals/:id/handover` | Confirm physical-item handover |
| `POST` | `/api/v1/rentals/:id/extensions` | Request a physical rental extension |
| `PATCH` | `/api/v1/rentals/:id/extensions/decision` | Decide an extension |
| `POST` | `/api/v1/rentals/:id/return` | Submit renter return evidence |
| `POST` | `/api/v1/rentals/:id/return/confirm` | Confirm return and deposit outcome |
| `POST` | `/api/v1/rentals/:id/start-service` | Start an approved service |
| `POST` | `/api/v1/rentals/:id/service-delivered` | Mark service delivery complete |
| `POST` | `/api/v1/rentals/:id/service-completion` | Renter completion confirmation |

## Authoritative seed records

- `RH-BKG-2026-09142`: Sony Alpha a7S III, 20–22 September 2026, RM255 rental, RM300 deposit, RM15 waiver, RM570 total
- `RH-SVC-2026-03218`: Essential Event Coverage, 3 October 2026 at 2:00 PM Malaysia time, three hours, RM450 service plus RM22.50 fee, RM472.50 total
- `RH-RNT-2026-09142`: active physical rental linked to the camera booking
- Aina Rahman is seeded as the verified Owner of the photography service

The seed remains idempotent and can be rerun without duplicating users, listings, bookings or rentals.

## Validation

- `npm test`: all 24 API tests passed.
- End-to-end tests cover physical and service pricing, participant views, approval, date locks, cancellation, handover, extension, return, deposit validation and service completion.
- MongoDB blackout ranges and accepted bookings are both checked for conflicts.
- Seed tests verify five core users, 13 listings, two authoritative bookings and one active rental.
- JavaScript syntax checks and Git whitespace checks passed.

## Current limitation

Lifecycle changes update linked booking and rental documents in the same service operation, but multi-document MongoDB transactions are not enabled because the current local Docker configuration uses a standalone MongoDB node. A replica set should be configured before production deployment if fully atomic multi-document transitions are required.

## Next phase

Implement Payment and Transaction APIs, including simulated authorization, successful/pending/refunded transactions, deposit handling, refund authorization and administrator monitoring. Then connect the live Flutter booking and payment repositories behind the existing mock toggle.
