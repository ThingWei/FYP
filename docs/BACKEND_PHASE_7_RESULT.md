# Backend Phase 7 Result: Disputes and Claims

## Result

Dispute Management is now a dedicated Express and MongoDB domain connected to the final renter, Owner, and administrator interfaces. It replaces the previous generic CRUD placeholder.

## Participant dispute lifecycle

- Only the renter or Owner linked to a rental/order can open or view its dispute.
- A rental/order can have only one dispute.
- Opening a dispute updates both the booking and rental/order to `disputed`.
- Both participants can add responses and evidence while the case is open.
- The other participant receives persistent notifications when a case is opened or updated.
- Closed cases reject further participant responses.

Physical-item categories cover damage, return condition, missing items, deposit deductions, and late returns. Service categories cover service quality, non-delivery, scope mismatch, and cancellation. The API rejects physical-item dispute categories and insurance claims for services.

## Damage-waiver claims

- Only the linked Owner can submit a claim.
- Claims require a physical-item booking with damage-waiver cover.
- Evidence is required and claim amounts are validated against the booking value.
- Administrators can approve or reject a pending claim with a required reason.
- Approved claim amounts cannot exceed the requested amount.
- Both linked participants can view the claim status; only the Owner receives the submission action.

## Administrator workflow

- The live Disputes & Claims destination loads both MongoDB queues.
- The case file shows the booking agreement, physical inspection/handover records where applicable, evidence counts, booking conversation history, and participant responses.
- Administrators can request more evidence, escalate, dismiss, release to the renter, split, or release to the Owner.
- A decision note is required.
- Physical-item decisions receive an explicitly fake `MOCK-CHAIN-...` reference.
- Allocation amounts are stored as simulated settlement instructions only; the phase does not claim to transfer real money.
- Final decisions update the linked booking and rental/order state and notify both participants.

## Audit safety

- Dispute status changes, final decisions, and claim decisions create append-only `AdminAudit` entries.
- The generic mutable audit CRUD route was replaced by an administrator-only, read-only endpoint.
- The live Audit Logs destination shows these records and their decision metadata.

## Main endpoints

- `POST /api/v1/disputes`
- `GET /api/v1/disputes/mine`
- `GET /api/v1/disputes/:id`
- `POST /api/v1/disputes/:id/responses`
- `POST /api/v1/disputes/:id/claims`
- `GET /api/v1/disputes/claims/mine`
- `GET /api/v1/disputes/admin`
- `GET /api/v1/disputes/claims/admin`
- `PATCH /api/v1/disputes/:id/review-status`
- `PATCH /api/v1/disputes/:id/resolve`
- `PATCH /api/v1/disputes/claims/:claimId/decision`
- `GET /api/v1/admin`

## Seed data

The idempotent seed includes a disputed physical-item rental, inspection evidence, a participant response, and a pending damage-waiver claim. This gives the renter, Owner, administrator dispute queue, claim queue, and case-file viewer consistent initial data.

## Validation

- `npm.cmd test`: 34 of 34 API tests passed.
- `flutter analyze`: no issues found.
- `flutter test`: 56 of 56 Flutter tests passed.
- Live renter/Owner JavaScript web build: passed with `USE_MOCKS=false`.
- Live administrator JavaScript web build: passed with `USE_MOCKS=false`.
- `git diff --check`: passed; only repository line-ending notices were reported.

Flutter reports the existing upstream Socket.IO WebAssembly dry-run warning and a Cupertino icon font notice. Standard JavaScript web builds complete successfully.
