# Paid extensions, settlements, refunds and recovery

Implemented 20 October 2026. This supersedes the four financial/lifecycle gaps in
`AUTH0_SOURCES_AND_LIFECYCLE_RESULT.md`. Payments remain simulations, not a real
escrow, payment gateway, insurer or protection fund.

## 1. Paid extra rental days

- New physical bookings snapshot their effective booked daily rate and original
  day count, including any promotion actually applied at booking time.
- Requesting extra days saves a server-priced quote with its own ID, old/new end
  dates, extra days, daily rate and total. No deposit, delivery or damage-waiver
  fee is charged a second time. At most 365 extra days can be requested at once.
- The renter reviews a dedicated demo checkout and explicitly chooses Demo Card,
  FPX or Wallet. Opening/cancelling checkout makes no transaction. A decline saves
  a failed attempt; a known decline can be retried with a new key.
- Unpaid quotes expire after 60 minutes. Successful authorization clears that
  payment deadline while Owner approval is awaited. A pending extension is not a
  date reservation. Current availability and vehicle eligibility are rechecked
  before payment and approval.
- Only Owner approval captures the extra payment and changes both rental and
  booking dates. The current quote ID is required for a new quote's decision,
  preventing an old screen from approving a replacement request.
- Rejecting an extension, submitting a return or opening a dispute releases its
  outstanding demo hold. Expired quotes are closed by the existing lifecycle job.
- Previous extension decisions are retained. Approved extra charges are appended
  to the booking and shown separately in the agreement/charge breakdown; the
  original saved pricing and accepted agreement version/hash are not rewritten.
- Checkout checks ownership/session, resets failed controls and offers a read-only
  status check after uncertain responses. It never blindly repeats a write.
- Old rentals without a trustworthy original-rate snapshot remain readable but
  cannot receive a guessed paid-extension quote. Contact support; a changed end
  date is not reliable evidence of the original daily rate. No migration or
  retroactive extra charge is performed.

Additive route: `POST /api/v1/rentals/:id/extensions/payment` with `extensionId`,
`method`, `simulationOutcome` and `idempotencyKey`. Existing request/decision paths
remain. Current clients include `extensionId` in Owner decisions.

## 2. Dispute and claim decisions

The administrator allocates only the balance still held, not the original gross
booking total. Prior refunds, deposit releases and Owner payments remain intact.
Default release-to-renter/Owner allocates the whole remaining balance. A split
must contain positive amounts for both participants and allocate the remaining
balance exactly. No clawback, penalty or invented recoupment is applied.

Non-dismissed resolutions create simulated renter-release and Owner-settlement
ledger entries and complete both linked records. A zero remaining balance can
record a zero allocation without issuing another payout. Dismissal restores the
actual saved pre-dispute statuses and makes no distribution. Settlement retries
return the recorded matching decision; conflicting decisions remain rejected.

Resolution audit entries are included in the durable plan. Completion
notifications and idempotent loyalty work have a retryable follow-up outbox.
Claims use an atomic pending-state decision guard. Approved claim decisions say
`payoutStatus = pending_funding`, and both participant/admin screens explain that
**no payout has occurred**. No pool, insurer, automatic funding or claim-payment
endpoint is invented. Existing waiver-fee allocation is preserved; it is **not**
represented as funding a protection pool.

## 3. Held-balance reconciliation

`GET /api/v1/payments/booking/:bookingId/balance` is authenticated and restricted
to participants/administrators. It returns aggregate captured, distributed and
held MYR amounts plus a reconciliation-required flag; no location or identity
information is included.

The calculation uses integer cents:

```text
held = successful initial + extension captures
       - successful refunds
       - renter/deposit/dispute releases
       - Owner settlements
       - recorded platform retention
```

Deposit deductions are allocation memos: their money is already included in the
Owner payout, so they are not counted a second time. Service platform fees are
recorded as platform retention. No new fee rate is introduced.

Refunds are limited by both the selected capture's unrefunded amount and the
whole booking's remaining held balance. Refunds and settlements share the same
listing-operation lease. New refunds save a write-ahead plan before ledger/state
updates; matching retries reconcile without another payout or notification.
Flutter retains an uncertain administrator refund's attempt key for an explicit
retry, and shows the held balance before the refund/allocation dialog. Money
history now includes transactions where the account is payer **or** recipient.

If an earlier refund/legacy payout makes the ordinary full return/service
settlement unaffordable, it stops with `SETTLEMENT_REVIEW_REQUIRED` before new
distribution (and before the return's supporting blockchain operation). An admin
must review the remaining funds rather than silently reducing someone's
entitlement. Missing captured ledger records or an overdistributed ledger also
require review. Legacy transactions are neither deleted nor relabelled.

## 4. Recovery and concurrency

`LifecycleOperation` is a private, non-expiring MongoDB write-ahead collection.
Only whitelisted, server-built creates and final set/unset updates enter a plan.
It is not exposed as an API accepting arbitrary database updates. New payment
effects have immutable IDs/idempotency keys, and existing record updates have
revision fences. Interrupted plans are replayed, not repriced against their own
partially consumed balances.

Covered plans include initial approval/rental creation, rejection/cancellation
hold release, handover/service start state updates, extension payment/approval,
normal physical/service settlement, dispute opening/resolution and new refunds.
Approved-request follow-up also recovers competing pending-request expiry.

Recovery runs before mutations on that listing, during participant-specific
booking/rental and balance reads, and before the existing lifecycle job. A job
pass selects at most 100 queued entries (50 by default); a listing pass handles
at most 100 state plans and 100 follow-ups. State plans take priority over failed
notifications; remaining state plans block new mutations until recovered.
Existing admin lifecycle-job controls can run it without another
terminal process. Job status includes recovered listings, expired extensions and
released orphan terminal holds. This is recovery of **recorded intents**, not a
bulk migration or an attempt to infer missing historical decisions.

Dispute creation, responses, review/resolution, rental mutations, refunds and
overdue status changes share the listing-decision lease. Overdue marking rereads
and conditionally updates still-active rentals, preventing an old fetched row
from overwriting a return/dispute/extension. Final booking creation checks
confirmed availability inside the short lease too; pending requests themselves
still do not block each other. Initial checkout retains its existing payment
lease/CAS behavior, so cancellation can still win while a gateway attempt is
pending. A bounded cleanup releases orphan initial holds for expired/rejected/
cancelled requests, without touching captured money.

Restart the existing API/launcher and rebuild Flutter to load the changes. Keep
`LIFECYCLE_JOBS_ENABLED=true` for unattended recovery and quote/hold cleanup while
the API runs. Do not launch a second API on port 3000. No new credentials,
production dependency, Auth0 change or live database operation was needed.

## Verification

- Full API suite: **411 passed, 3 optional skips** (414 total). Final focused
  financial/dispute/refund rerun: **33 passed**, including the separate dispute
  refund ledger label.
- Full Flutter suite: **416 passed, 3 existing skips**. Application analysis:
  **no issues**. Web and Android debug APK builds passed.
- Existing non-blocking build warnings remain: Socket.IO's Wasm dry run,
  optional Cupertino icon-font discovery, and Firebase/preferences plugins'
  Kotlin Gradle migration notice. No unrelated analyzer failures remain.
- `git diff --check` passed. AI code/models/contracts were not changed; AI
  training and the Python suite were not rerun for this financial/UI task.
- New focused widget coverage includes 360/390/1024-pixel widths at 1.5x text,
  explicit success/decline/cancel, lost-response read recovery, logout while the
  confirmation is open, retryable loading failure and separate extension charges.
- New isolated MongoDB/API regressions cover original-rate pricing, all demo
  methods, authorization/foreign access, changed quotes, conflicting dates,
  extension history, return/dispute hold release, expired quotes, balance privacy,
  refund/settlement limits, already-paid disputes and unfunded claim approval.
- Injected failures cover extension authorization, extra-day capture/date writes,
  initial rental creation/booking approval, refund/state reconciliation, settlement
  ledger/state writes, dispute closure and completion notification recovery.
  Revision-fence replay and concurrent decisions/dispute-return transitions are
  tested. Mock authentication/local storage are used only inside tests; FCM,
  email and blockchain are disabled there. No live records/secrets were changed.

### Limits and device handoff

- These are simulated financial records. Real payment-provider idempotency,
  webhook reconciliation, regulated safeguarding and funded claim payouts are not
  implemented or claimed.
- Saved financial/state plans recover across standalone MongoDB partial writes;
  this is not a multi-document transaction. Reads outside the focused recovery
  routes can briefly see partial state until recovery. Missing/deleted plan
  targets stop safely for operator review; never manually delete a pending plan.
- External blockchain calls precede the saved state plan. A crash at that boundary
  can leave an orphan/supporting transaction; exactly-once blockchain effects are
  not promised. Contracts are unchanged and do not record full agreement text or
  paid-extension terms. An unavailable supporting record does not undo settlement.
- Completion outbox work is deduplicated/retried, but push delivery remains
  best-effort. Unrelated informational notifications are not a universal outbox.
- No physical Android/Ganache session was performed in this change. For UAT,
  create a fresh physical booking, authorize/approve/handover, request extra days,
  test decline/cancel/success, approve as Owner, and check dates/extra receipt.
  Return it and verify one release/payout. Separately test a partial refund plus
  dispute split and an approved claim labelled payout-pending. Repeat a service
  completion and log out during extension confirmation. Use test accounts/funds.

## Commit message

```text
feat(renthub): add paid extensions and recoverable simulated settlements

- snapshot booked rates and quote extra days without repeating one-off fees
- add guarded demo extension checkout, retries and Owner payment approval
- preserve extension history and show extra charges separately from original totals
- allocate dispute settlements from remaining held funds with durable audit records
- keep approved claims payout-pending until a funded demo protection pool exists
- reconcile refunds against releases, Owner payouts and retained platform fees
- persist replayable lifecycle/payment plans with revision fencing and follow-up work
- serialize dispute/rental transitions and guard overdue and pending-request races
- recover interrupted approvals, payments, refunds and terminal authorization holds
- add API crash/concurrency and responsive Flutter checkout regression coverage
- document simulation limits, legacy rate gaps and device verification steps
```
