# Backend Phase 6 Result: Review Management

## Implemented

Review Management is now a dedicated Express and MongoDB module instead of a generic CRUD placeholder.

### Participant review lifecycle

- Only a renter or Owner who participated in a completed rental or service order can submit a review.
- Each participant can submit at most one review for the same rental.
- The reviewed user, listing, booking, rental, author role, and subject role are derived by the server.
- Overall and communication ratings are required.
- Physical-item renter reviews may include condition and value ratings.
- Service reviews do not store a physical-item condition rating.
- Owner reviews of renters do not store item-condition or value ratings.
- Review text is validated and stored in MongoDB.
- The reviewed participant receives a notification.

### Editing and reputation

- Authors may edit their own review for 24 hours after submission.
- The API returns `canEdit` and `editableUntil` metadata for authored reviews.
- Published reviews can be read by listing before booking.
- Public subject summaries return the average rating and review count.
- Hidden reviews are excluded from public listing and reputation results.

### Owner and administrator controls

- The reviewed participant can flag a suspicious review with a reason.
- Administrators can list all reviews or filter by published, hidden, or flagged state.
- Hiding a review requires a reason.
- Administrators can restore a hidden review.
- Moderation updates notify the review author and remain visible in request audit logs.

## Final UI integration

- Renter and Owner completed-order cards expose review submission.
- Reviews remain editable from the completed-order card while the server-provided 24-hour window is open.
- Listing booking pages load and show published reviews before checkout.
- Owner Dashboard shows received reviews and supports suspicious-review flags.
- Admin Reviews is now a live MongoDB-backed destination with hide and restore actions.
- Admin Dashboard shows the flagged-review count.

## Seed data

The idempotent seed now contains a completed historical physical rental and a linked published review, so live listing, renter, Owner, and administrator review screens have consistent initial data.

## Main endpoints

- `POST /api/v1/reviews`
- `PATCH /api/v1/reviews/:id`
- `GET /api/v1/reviews/mine`
- `GET /api/v1/reviews/received`
- `GET /api/v1/reviews/listing/:listingId`
- `GET /api/v1/reviews/subjects/:subjectId/summary`
- `POST /api/v1/reviews/:id/flag`
- `GET /api/v1/reviews/admin`
- `PATCH /api/v1/reviews/:id/moderation`

## Important constraints

- Reviews cannot be created before the rental or service order is completed.
- Review targets are server-derived and cannot be selected by the client.
- Duplicate reviews return `REVIEW_ALREADY_EXISTS`.
- Late edits return `EDIT_WINDOW_ENDED`.
- Reviews remain part of the simulated FYP environment and contain no real personal data.
