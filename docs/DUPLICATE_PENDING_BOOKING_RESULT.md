# Duplicate pending physical-rental requests

Implemented 15 October 2026, preserving the uncommitted role-isolation work.

## Behaviour

- A renter cannot submit another pending request for the same physical item with
  any overlapping rental dates, even with a fresh submission key or different
  fulfilment options. Physical rental end dates remain inclusive.
- Both unpaid and payment-authorized pending requests are covered. Following the
  paid-deadline correction below, authorized requests remain pending until an Owner
  decision/cancellation or a competing approved booking resolves them.
- A duplicate returns HTTP 409, code `DUPLICATE_PENDING_BOOKING`, with only
  `details.bookingId` pointing to that renter's existing request. It creates no
  booking, payment, conversation or extra booking-created notification.
- Flutter offers **Keep editing** or **View existing request**. Keeping the draft
  retains its inputs and resets the submit button. Viewing retrieves the current
  participant-authorized booking and opens its focused renter detail page behind
  the existing authenticated route guard. It never automatically starts payment.
- Current unpaid requests retain **Continue payment**. Authorized pending requests
  say **Awaiting Owner approval** and do not offer another payment.
- To change dates or fulfilment, cancel the existing request before replacing it.
  Different items and non-overlapping date ranges remain bookable.
- Cancelled, rejected, expired and completed requests do not block a new attempt.
  An unpaid pending record whose expiry has elapsed also does not prevent replacement;
  normal lifecycle processing remains responsible for its expiry/payment cleanup.
  Legacy pending records without an expiry still count as pending until resolved.

Paid pending requests are not excluded just because an old `expiresAt` value has
elapsed. New successful payments clear that payment deadline. See
[Paid pending requests and listing photos](PAID_PENDING_AND_LISTING_PHOTOS_RESULT.md)
for the correction, legacy recovery and current verification results.

## Soft holds and authorization

Other renters may still request the same item and dates while requests are pending.
Pending requests do not become confirmed availability blocks. Approval, active rental,
unresolved physical dispute and Owner blackout rules remain authoritative. Approving
one physical request retains the existing competing-pending expiry/authorization
release workflow. Service booking semantics are unchanged.

Existing same-key replay still returns the saved booking without extra side effects;
changed input under the same key still returns `IDEMPOTENCY_CONFLICT`. A fresh key
cannot bypass the same-renter pending-overlap check.

## Concurrent creation

A private MongoDB-backed mutex serializes creation by renter/listing pair across API
processes, without requiring MongoDB transactions or a process-local-only lock.
Different renters have independent locks; this is not an item/date reservation.

The private `bookingrequestlocks` collection uses MongoDB's built-in unique `_id`,
with a hashed pair identifier, random ownership token and 60-second lease. Ordinary
concurrent submissions wait briefly (up to 80 bounded 25ms waits plus database time),
then recheck idempotency and pending overlaps. Ownership is checked/renewed immediately
before insertion. Cleanup is token-specific and has TTL expiry for abandoned locks.
No new production dependency, credentials or manual migration is required.

A busy/lost lock returns HTTP 409 `BOOKING_REQUEST_IN_PROGRESS` with safe guidance
to check Bookings. The app does not blindly repeat a booking/payment write.
Database or lock failures do not bypass the guard.

Existing duplicate bookings are not automatically cancelled or deleted. They remain
visible so the renter can review/cancel unwanted requests through normal controls.

## Verification

- Booking/API suite: **31 passed**, including 11 added regressions for this fix.
- Full API suite: **361 passed, 3 skipped** against ephemeral MongoDB, not live data.
- New Flutter tests: **5 passed**, including actual listing submission recovery for
  unpaid/paid requests and draft-preserving dialogs at 360/390 pixels with 1.5x text.
- Full non-live Flutter suite: **377 passed, 3 skipped**.
- Flutter source and new-test analysis: **no issues**.
- Web build: **passed**, with existing socket_io_common WebAssembly dry-run and
  Cupertino-font warnings. No Android hardware test is claimed.
- Full analysis still reports the two existing undefined Auth0 test arguments
  `latestLinkProvider` / `mobileLinkPollInterval` at
  `test/auth0_persistence_test.dart:41/43`; Auth0 code was not changed.

API cases cover exact/partial/contained overlap, shared end/start days, fresh keys,
parallel fresh-key requests, replay compatibility, paid/unpaid state preservation,
other renters/items/dates, terminal/elapsed/legacy expiry, lock failure/recovery and
lost ownership. Existing soft-hold and Owner-approval tests remain passing.

Delivery-fee fixtures now cancel pickup before requesting delivery. Payment-collision
fixtures use separate dates, and competing-renter fixtures use different accounts.

Tests use process-local `NODE_ENV=test`, `AUTH_MODE=mock`, `STORAGE_MODE=local`,
`FCM_MODE=disabled`, `BLOCKCHAIN_MODE=disabled`, `EMAIL_MODE=disabled` with
mongodb-memory-server. Live configuration and records were not changed.

## Device check

Restart the API and hot-restart Flutter. Submit a physical rental request, then try
the same/partly overlapping dates again. Open the existing request; unpaid should
offer Continue payment and authorized should await Owner approval. Cancel it and
confirm a fresh request is permitted. Use another renter to confirm pending dates
remain requestable until an Owner approves one.

## Commit message

```text
fix(bookings): prevent duplicate overlapping pending rental requests

- reject same-renter physical-item overlaps across fresh submission keys
- serialize concurrent creation with a private MongoDB-backed request mutex
- preserve idempotent replay and pending soft holds for other renters
- offer existing-request recovery without creating another payment
- retain drafts and reset loading controls after duplicate failures
- clarify paid pending requests as awaiting Owner approval
- cover concurrency, expiry, terminal states and mobile recovery in tests
- update compatible delivery/payment fixtures and document verification
```
