# RentHub Backend Phase 5 Result

Date: 14 September 2026

## Outcome

RentHub now has strict MongoDB-backed conversations, messages, message reports and notifications. Conversations are linked to real bookings, only their renter and Owner can access them, and messages are created through validated REST actions before the server emits real-time Socket.IO events.

Booking, payment and rental lifecycle operations now generate targeted in-app notifications for the affected participant.

## Implemented

### Conversations and messages

- One conversation per booking, created automatically with the booking request
- Renter/Owner participant-only thread and message access
- Conversation list with safe participant profile data, latest-message preview and unread count
- Paginated chronological message history
- Server-derived sender and recipient identities
- Required non-empty messages with a 2,000-character limit
- Explicit thread read receipts
- Closed-thread enforcement
- Two-way blocking enforcement before message creation
- No direct client-to-client message rebroadcasting

### Message safety and administration

- Renter or Owner reporting of a received message
- Harassment, scam, spam, inappropriate and other report reasons
- Required details for the `other` reason
- Idempotent repeat reporting by the same participant
- Administrator-only report queue
- Administrator resolution or dismissal with a required explanation
- Prevention of self-reporting and outsider access

### Notifications

- Paginated notification centre with category and read-state filters
- Global unread count in response metadata
- Individual mark-as-read
- Mark-all-as-read
- Individual removal
- Clear-all
- Real-time `notification:new` emission to the target user's socket room

Lifecycle notifications are generated for:

- New booking requests
- Payment authorization
- Booking approval or rejection
- Booking cancellation
- Physical handover
- Service start
- Extension request and decision
- Return submission and confirmation
- Service delivery and renter completion
- Partial and full refunds

### Socket.IO security

- The server is the only source of `message:new`, `message:read` and `notification:new` broadcasts.
- User-specific rooms are established from mock identity during local development.
- Production socket connections verify the configured JWT issuer and audience.
- Thread-room joins check MongoDB participation before granting access.

## Communication endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/v1/messages/threads` | List participant conversations |
| `POST` | `/api/v1/messages/threads/from-booking/:bookingId` | Get or create the booking conversation |
| `GET` | `/api/v1/messages/threads/:threadId/messages` | Read message history |
| `POST` | `/api/v1/messages/threads/:threadId/messages` | Send a validated message |
| `POST` | `/api/v1/messages/threads/:threadId/read` | Mark received thread messages read |
| `POST` | `/api/v1/messages/:messageId/report` | Report a received message |
| `GET` | `/api/v1/messages/reports` | Administrator report queue |
| `PATCH` | `/api/v1/messages/reports/:reportId` | Resolve or dismiss a report |
| `GET` | `/api/v1/messages/notifications` | List the current user's notifications |
| `POST` | `/api/v1/messages/notifications/read-all` | Mark every notification read |
| `POST` | `/api/v1/messages/notifications/:notificationId/read` | Mark one notification read |
| `DELETE` | `/api/v1/messages/notifications/:notificationId` | Remove one notification |
| `DELETE` | `/api/v1/messages/notifications` | Clear all notifications |

## Seed alignment

The idempotent seed now includes:

- Two booking-linked conversation threads
- Four renter/Owner messages across physical and service bookings
- Four read/unread lifecycle notifications
- One open message report for the administrator moderation queue

All records use the same booking, listing, user, payment and rental identifiers introduced in earlier phases.

## Flutter integration contract

- `Message`, `Conversation` and `RentHubNotification` parse backend public IDs and state.
- `LiveMessageRepository` supports thread lists, history, validated sending, read receipts, reporting and optional Socket.IO updates.
- `LiveNotificationRepository` supports filtering, read operations, individual removal and clear-all.
- `SocketService` supplies mock user identity or a production token during the Socket.IO handshake.
- Existing renter and Owner screens remain mock-first until the final integration phase, preserving offline prototype behavior.

## Validation

- `npm test`: all 30 API tests passed.
- New communication integration tests: all three passed.
- `flutter analyze`: no issues found.
- `flutter test`: all 48 tests passed.
- `flutter build web`: succeeded, including the WebAssembly dry run.
- JavaScript syntax and Git whitespace checks passed.

Coverage includes participant isolation, unread counts, read receipts, reporting, administrator resolution, blocking, notification filtering/removal, lifecycle event generation and idempotent seed execution.

## Current limitations

- Socket events are in-app real-time events; external push services and email delivery are not connected.
- Mock socket authentication accepts a development user ID. It must never be enabled in production.
- The visual message and notification pages still use local prototype state by default.
- Cross-document writes are not transactional until MongoDB is configured as a replica set.

## Recommended next phase

Implement Reviews and Ratings. Completed booking and rental records can now enforce one review per participant, verified-booking labels, aggregate listing/Owner ratings and administrator review moderation.
