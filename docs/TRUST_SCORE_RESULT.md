# Working RentHub trust scores

Implemented 28 October 2026. Existing uncommitted administrator work is preserved.

## What users can do

- Open **Trust** on Profile, the **Trust score** tile on the Owner Home screen, or **Owner trust** on a listing.
- Owners can open **Renter trust history** on incoming requests. Administrators can open **View trust history** from a user record.
- Read the score, completion/partner/review counts, recorded timeliness and confirmed issues. Scores are separate for the renter and Owner roles; one account can have different role histories.
- New or unsupported histories show **Not enough rental history**, rather than an invented high score. Refresh and retry retain previously loaded information. Logout/account changes hide the previous account's information.

This is a transparent reputation policy, not an AI authenticity prediction. Use it alongside verification and reviews. It does not automatically authorize, approve, reject or restrict a booking. MyKad and driving-licence requirements are unchanged.

## Calculation: renthub-trust-v1

The observation window is 365 days. Each role/cohort needs **three qualifying completed rentals and two distinct counterparties** before publishing a numerical score. The combined profile also has its own maturity check.

Only participant-consistent booking/rental pairs with a recorded completion, successful MYR capture evidence covering the booked rental base amount, and usable provenance contribute. A completion later placed under dispute retains its completion history while the report is unproven. Cancelled, pending, rejected, unpaid, unknown-payment and future-dated records do not contribute.

The score combines:

| Component | Weight | Policy |
| --- | ---: | --- |
| Completed rental responsibility | 55% | Completed rentals minus explicitly confirmed responsibility; both participants share half a fault each |
| Published reviews received | 25% | Only the actual counterparty's published review of that completed rental; hidden, unrelated and forged reviews are excluded |
| Recorded timeliness | 20% when measurable | Physical Owner handover, physical renter return, or Owner service delivery |

Missing timeliness is omitted and applicable weights are normalized. Missing reviews retain a neutral prior, so adding a positive first review cannot reduce reputation. The policy starts each component with four neutral observations to avoid a first successful rental appearing perfect.

For reproducibility, with `n` qualified completions, fractional responsibility `f`, `r` received ratings whose sum is `s`, and `t` on-time observations out of `m` measured:

```text
completion component = 100 × (n − f + 2) / (n + 4)
review component     = (20 × s + 200) / (r + 4)
timeliness component = 100 × (t + 2) / (m + 4), only if m > 0
score                = rounded weighted mean, bounded to 0–100
```

Example: three good completions across two counterparties, three five-star reviews and three on-time observations produce **71 / 100**, not 100. More consistent history gradually strengthens the result. These weights are product rules, not empirically calibrated probabilities or a demonstrated fraud-detection accuracy.

Physical dates remain calendar dates: the deadline is the end of the selected final day in Malaysia. Approved extensions use the current rental end date. Missing timing is not guessed. Service renter confirmation delay is not treated as lateness. Handover timeliness is measured by the start day's end, not a promised appointment time the system does not store.

## Disputes and provenance

Administrators now have an optional **Responsibility finding** in the existing dispute resolution form: Not determined, Neither participant, Renter, Owner or Both participants. It is saved with the resolution. Old decisions default to not determined; dismissed disputes cannot produce a responsibility penalty. Refund amounts, deposit deductions, open complaints and flagged reviews do not establish fault.

**Marketplace** and **Demo activity** are calculated and displayed separately. Simulated payments or labelled demonstration bookings/listings/snapshots go into the demo cohort. Genuine reputation requires explicit marketplace provenance and successful non-simulated captures. Unknown legacy evidence is not silently upgraded. Because the current checkout is simulated, completing its flow grows the demo history, not genuine paid-marketplace reputation.

Demo scores never enter genuine trust sorting or the pricing model's Owner-trust feature. Old numeric seed values are no longer presented or sorted as earned reputation. Existing numeric API fields remain compatible using neutral 50 when genuine history is insufficient; ordinary user screens show the actual status instead. Administrator CSV exports leave unestablished earned reputation blank.

No historical booking, payment, source marker, identity approval or financial amount was changed. No production database seed or migration was run.

## Integration and maintenance

- Authenticated `GET /api/v1/users/me/trust` and `GET /api/v1/users/:id/trust` return safe aggregates, with overall/Owner/renter and marketplace/demo summaries. The latter supports encoded Auth0 account identifiers. Blocked/inactive targets are hidden from unrelated ordinary users; administrators and the account itself retain access.
- Optional derived caches live in `User.trustProfile` and `Listing.ownerTrustProfile`. Profile reads refresh after 60 seconds; completion, published-review creation/edit/moderation and resolved-dispute completion refresh affected accounts. Listing snapshots refresh with the account, on listing creation and on pricing requests. A listing snapshot may lag until that refresh; open the trust page for the current calculation.
- Durable lifecycle follow-ups run after successful financial/state commits. Trust failures cannot instruct a user to repeat a payment; invalidated caches fall back to neutral/unavailable. The dedicated history page offers retry. A failed reputation lookup does not block profile loading, listing creation or manual pricing.
- Recalculation is idempotent and protected by the existing account-scoped operation lock. No incremental score counters, new dependencies or automatic role changes were introduced. Derived cache writes do not reorder records by changing business timestamps.
- Queries are bounded to 1,000 recent completions and 20,000 associated payment rows. Exceeding the bounds returns unavailable rather than a misleading partial score. Large histories need a future aggregation strategy.
- Aggregate responses contain no emails, booking/payment identifiers, private coordinates, identity documents or fingerprints. Full factual records keep their existing authorization.
- `trust-profile-v1` is required by launcher readiness, preventing reuse of an older API lacking the new routes.
- Pricing feature order, deployed artifacts and recommendation weights remain unchanged. Pricing uses the calculated genuine Owner role score or neutral 50.

## Verification

Verified with isolated test databases and generated test facts; no real activity was fabricated.

| Check | Result |
| --- | --- |
| Full Express API suite | 610 passed, 3 skipped |
| Full Flutter suite | 539 passed, 3 skipped |
| Full AI suite | 606 passed; existing dependency deprecation warnings |
| Flutter analysis | No issues |
| Launcher regression | Passed, including trust capability mismatch |
| Trust page layouts | 360 / 390 / 1024 logical pixels, 1.4 text scale; no widget layout exceptions |
| Administrator web build | Passed |
| Main application web build | Passed |
| Android debug APK | Passed |

Existing Socket.IO WebAssembly dry-run, missing Cupertino-font and plugin Kotlin migration warnings remain; JavaScript web builds and the debug APK succeed. No Auth0 analyzer failure was observed.

The existing opt-in skips cover two live MongoDB Flutter phases and UI capture, plus three live external catalogue/API checks. The default suites do not perform those live writes or provider calls.

Coverage includes maturity, distinct counterparties, provenance separation, review edits/moderation, Malaysia date boundaries and extensions, open versus resolved responsibility, duplicate records, role separation, cache persistence/idempotency, failed-cache fallback, blocked-account access, private serialization, forged profile writes, trust sorting before pagination, lifecycle completion refresh, stale responses, malformed responses and explicit retry. Booking-screen tests now scroll the outer page rather than a text field when reaching below-the-fold agreement controls.

Pricing artifact SHA-256 remains `2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

## Demonstration steps and limits

1. Restart through `run-renthub.ps1` and hot-restart the app to load the new capability and UI.
2. Open Profile → Trust. A new account should have counts and no earned numerical score.
3. Use dedicated tester accounts to finish three demo rentals involving two different counterparties. Submit eligible reviews. Open Trust again: demo counts/score update separately; genuine reputation stays unestablished.
4. On a genuine incoming request, open Renter trust history. Switch back to renter and verify its separate role history.
5. As administrator, resolve a test dispute with an explicit finding. Only a responsible participant's applicable cohort changes; an open/dismissed report or refund alone does not lower reputation.

Real-device interaction and keyboard/assistive-technology verification remain manual handoff checks. Genuine paid-transaction reputation cannot be demonstrated honestly by relabelling the simulated checkout. The policy cannot establish authenticity, rightful ownership, absence of collusion or future reliability. No past sample scores are treated as independently validated reputation.

## Commit message

```text
feat(trust): calculate role-based reputation from recorded rental activity

- separate genuine marketplace reputation from simulated demo history
- require sufficient completions and distinct counterparties before scoring
- use published reviews, recorded timeliness and explicit dispute findings
- refresh derived account and listing summaries after eligible activity
- add safe trust-summary endpoints and readable renter/Owner/admin access
- exclude legacy seeded and demo scores from earned trust sorting and pricing
- preserve financial outcomes when reputation refresh fails
- test policy, API access, lifecycle updates, retry and responsive layouts
```
