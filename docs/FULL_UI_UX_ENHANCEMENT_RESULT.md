# RentHub UI/UX enhancement and integration result

Implementation date: 20 November 2026. Verification is in progress; results below will be completed after execution.

## Requirement checklist

- [x] Deduplicate equivalent saved places at serialization, selection and future-write boundaries; preserve distinct units and stored history.
- [x] Keep one saved-place selector and remove the separate area-selection system introduced above delivery guidance.
- [x] Disable past same-day appointment choices and validate Malaysian appointment instants on the server.
- [x] Remove Minimum Notice and Buffer from the Owner interface; retain existing configured values for compatible clients.
- [x] Remove duplicated booking appointments and payment/date summaries; retain appointments at checkout and in agreements.
- [x] Link booking titles to existing listing details, with safe recovery for unavailable records.
- [x] Improve transaction timestamps, type/amount/status grouping and newest-first payment history.
- [x] Group agreement participants, arrangement and locations with responsive spacing.
- [x] Simplify receipt confirmation; provide busy feedback and duplicate-action guards for approval, handover, receipt and return.
- [x] Gate dispute reasons by actual rental stage and overdue deadline, including direct API submissions.
- [x] Move case conversations into Messages; retain case-management actions in case screens.
- [x] Add admin access to case messaging, notification indicators and authorized notification destinations.
- [x] Add server-filtered Owner listing search/category/status controls, reset and accurate pagination.
- [ ] Complete automated regression, build and responsive-layout verification.

## Architecture and data handling

The existing Flutter Material theme, Inter font and shared components remain the visual foundation. The `ui-ux-pro-max` skill guided loading feedback, touch targets, form labels, virtualized messages and responsive information groups. Its local UX and Flutter queries were checked against the existing stack; no new design-system package was introduced.

### Saved places and scheduling

Recent locations previously used formatted address labels in their identity, while the client merged them by exact coordinates alone. Equivalent addresses now use normalized structured address fields plus rounded confirmed pins. Different unit/address fields remain separate. Existing duplicates are projected once in responses and selectors; original database records are retained. Future equivalent recent-place writes use a stable identity and an atomic duplicate guard. Explicit duplicate address submissions receive a friendly validation error.

The booking screen uses the original delivery/saved-place/map controls. Delivery advice derives from that existing selection or discovery area. The extra independent selector has been removed.

Appointment validation interprets dates and times in Asia/Kuala_Lumpur, with fresh checks before creating a booking and authorizing a new payment. Successful retries recover existing results rather than invalidating a previously recorded payment. The UI disables elapsed hour/minute/period combinations and validates again at submission. Service times use the same selection controls and an explicit Malaysian UTC conversion.

Minimum Notice and Buffer are hidden from Owner availability editing. Omitted fields retain saved values; older API clients can still send validated optional settings. No historical availability is reset.

### Messaging and administration

The existing Messages inbox now includes case conversations. `LiveChatPage` supports booking and case modes with a shared bubble frame. Case messages use a virtualized list, the existing authenticated socket connection and protected upload service. Case pages provide a conversation link instead of another embedded message composer.

Messaging routes adapt the existing case-message store and historical responses; messages are not copied into a second collection. Ordinary two-person booking threads retain their current contract and permissions. The legacy dispute-message routes remain compatible.

Added interfaces:

- `GET /api/v1/messages/cases?page=1&limit=20`: authorized case inbox, stable ordering, unread counts and filtered database totals.
- `GET/POST /api/v1/messages/cases/:id/messages`: existing case history and idempotent sends through Messaging.
- `POST /api/v1/messages/cases/:id/read`: viewer-scoped read receipts bounded by the server-provided read cutoff.
- Additive notification destination kinds `case_chat` and `admin_case`.
- Optional `search` and `category` on the existing Owner listings endpoint, combined with existing status/page/limit parameters.

Active authorized admins can participate in disputes and linked damage-waiver case discussions. This does not grant access to unrelated private booking chats or introduce unrestricted administrator direct messaging. Admin messaging and notification actions are in the portal header; the ten sidebar destinations remain intact.

New cases, case updates and case messages notify the appropriate admin team through the installed notification service. Unique event/recipient keys avoid duplicate deliveries. Opening Messages updates only the viewer's message notifications up to the read cutoff, leaving later arrivals unread. Viewing messages performs no case decision or financial operation.

Admin socket connections are owned by the administrator shell and released on disposal; dashboard data reads do not create background socket connections.

### Dispute eligibility and UI feedback

Before renter receipt, an Owner can report communication/other issues, while a renter can report problems with the submitted handover. Owner damage/missing-item reasons require a started rental. Late return requires the existing actual return deadline and grace policy; a displayed overdue status alone is insufficient. Return-condition/deposit-review reasons require a submitted return record. Existing completion restrictions and case history remain intact.

Mutating buttons show progress, prevent duplicate taps and retain existing confirmations/recovery paths. Spinners pause behind confirmation dialogs because waiting for a decision is not a network operation. Payment notification links open the relevant transaction within expanded payment details rather than repeating it above the section.

## Migrations and preserved data

No bulk migration, shared-record cleanup, environment change, credential change, production dependency or payment relabelling was performed. The existing case-message store from the preceding change is reused. Original saved-place history and existing messages/attachments remain stored. Pricing, recommendation and image-model artifacts are not retrained or replaced.

## Verification results

Pending final execution summary.

## Manual walkthrough

1. Open a booking with saved/recent locations. Confirm one option per equivalent address, clear/reselect it, and check that different units remain separate. Confirm there is no extra selector above delivery guidance.
2. Book today and try an elapsed pickup or service time. Select a later time, then test a future-date booking. Leave a screen open until a selected time elapses and retry.
3. Open booking details and payment details: appointments should appear once; the listing title should open its current details. Check a payment notification and the displayed transaction/date/order.
4. Open an agreement at mobile and desktop widths. Check participant names, arrangement, locations, appointments and charges.
5. Approve a booking, send handover, confirm receipt and confirm return. Observe progress, try repeated taps and cancel a confirmation. Confirm success is reconciled with server status.
6. Before renter acknowledgement, try Owner damage/non-return dispute reasons; they should be unavailable. Check that the renter can report handover issues and that an actual overdue rental offers late return.
7. Open the case conversation through Messages as renter, Owner and admin. Send text/evidence, load older messages, reconnect, inspect unread counts and navigate back to case management. Resolve through the existing admin controls; closed history should remain readable.
8. In the admin portal, receive a new-case/message notification, open it, and verify the correct case/conversation. Confirm another participant cannot access a foreign case.
9. Search/filter My Listings, visit later pages, reset filters and open an existing management action. Check empty matches and refresh errors.

Physical-device notification, real network reconnection and keyboard/screen-reader walkthroughs must be recorded separately from automated checks.
