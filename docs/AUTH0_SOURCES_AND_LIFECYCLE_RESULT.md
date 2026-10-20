# Auth0 checks, rental-price sources and lifecycle review

Verified on 20 October 2026. Covers the user's requested tasks 1, 2 and 3.

## 1. Flutter/Auth0 checks — fixed

The native gateway constructor already accepted `latestLinkProvider` and
`mobileLinkPollInterval`. The web/stub constructors did not, so whole-project
analysis reported undefined named arguments in the persistence tests.

Both constructors now accept the same optional hooks. They are intentionally
unused on web/unsupported platforms. No OAuth parameters, refresh-token handling,
SDK login/logout behaviour, Auth0 tenant settings or local authentication changed.

- Full `flutter analyze`: **No issues found**.
- Native Auth0 persistence suite: **16 passed**, including Android PKCE, state
  rejection, warm/cold callback recovery, cancellation, refresh and logout.
- Full Flutter suite: **407 passed, 3 existing skips**.
- Ordinary Flutter Web build and Android debug APK build: **passed**.
- Existing Socket.IO Wasm dry-run incompatibility and Kotlin-plugin migration
  warnings remain; neither caused these builds to fail. No Wasm build is claimed.

## 2. Price-source adapters — implemented where verifiable, blockers retained

No live source was enabled, no quote was imported into MongoDB and no model was
retrained. HTTP probes were bounded, public and read-only; no browser automation,
private booking API, credentials, checkout interaction or access bypass was used.

| Source | Code/result | Current limitation |
| --- | --- | --- |
| iRent | Implemented product-page tier parser and bounded product discovery. Live probe: **6 accepted duration-band observations, 2 products, 7 pages**, zero DB writes. | One-time maintainer access/reuse review and explicit source enablement still required. |
| 12RENT | Implemented labelled daily-lease/minimum-period parser; fixture tests pass. | Live robots response is HTTP 200 with unrendered `<cfinclude>` markup, not a usable policy. Collection fails closed with `ACCESS_RESTRICTED`; it was not enabled. |
| RentSmart | Investigated old configured routes and the current electronics route linked by its own navigation. Direct responses contain no product prices; adapter remains unavailable. | Search-index excerpts show prices but do not establish current directly retrievable offers. A usable public catalogue/feed and access/reuse review are needed. No fabricated adapter success. |

### iRent semantics

The public [A35 product page](https://irent.my/product/samsung-galaxy-a35-5g-rental/)
publishes explicit duration tiers, unlike the catalogue's headline minimum.
The parser reads only the product's own summary, smartphone category metadata
and `irent-discount-table-wrapper`, not related items or executable scripts.

- One-day tier remains a one-day price.
- A 2–7-day daily rate becomes a quote for the two-day minimum with the original
  2–7-day applicability retained. It is not advertised as a one-day offer.
- The same applies to 8–30 days.
- `31+ Days (Yearly)` is excluded rather than guessing what that commitment means.
- Deposit, collection/delivery charges and source stock-substitution terms are
  disclosed. Neither the brand nor rental prices are hardcoded in parser rules.
- Overlapping duration ranges, malformed rates, other product categories and
  headline-only markup fail closed. Duplicate/conflicting observations use the
  existing shared safeguards.

The six live quotes were for two Samsung models and three explicit bands each.
They are asking-price observations, not achieved rentals, availability guarantees
or independently verified market averages.

### 12RENT semantics and blocker

The inspected [drill product page](https://toolrent.instantestore.com/pd-rental-bosch-gsr-120-li-cordless-drill-driver-professional-12v.cfm)
has explicit status, brand, model, type, daily lease term/rate and minimum period.
The parser ignores catalogue numbers and checkout/deposit totals. For its example
daily rate of RM5.99 and seven-day minimum, the fixture produces RM41.93 for seven
days, not the RM289.62 checkout figure. Only that minimum-period offer is accepted;
longer-period checkout semantics remain unverified and are not extrapolated.

Unsupported tool types, sales, missing/contradictory fields and ambiguous periods
are excluded. Parser completion does **not** override the malformed access policy.
`robotsAllows` now rejects unrendered markup as well as HTML challenge pages.
Do not edit the collector to bypass this. Publisher clarification/a usable policy
or an explicitly permitted alternative feed is needed before onboarding.

### RentSmart result

The directly retrieved [configured electronics page](https://rentsmartasia.com/product-category/rent-equipment/electronics/)
and [current electronics route](https://rentsmartasia.com/product-category/equipment/electronics/)
returned a catalogue shell without quotes. Other configured scooter/sports pages
were also empty when inspected through the public page reader. No unreviewed
JavaScript/private API was used to bypass that limitation. The source's admin
explanation now identifies the empty-catalogue problem.

The read-only diagnostic now reports unsupported sources explicitly instead of
printing nothing for `rentsmart`:

```powershell
cd C:\Users\weith\FYP\services\api
npm.cmd run inspect:price-sources -- irent
npm.cmd run inspect:price-sources -- 12rent
npm.cmd run inspect:price-sources -- rentsmart
```

After a maintainer reviews iRent's access/reuse conditions, add `irent` to the
existing `PRICE_SYNC_APPROVED_SOURCES` list without removing its other reviewed
entries. Restart the actual API, refresh admin source status and explicitly
enable iRent. No `.env` value or publisher permission was changed/claimed here.
RentSmart remains pending; 12RENT still cannot pass its current access probe.

Sources retain the existing 20-page, 500-observation, 2-MB-page, 15-second-request
and five-minute-job bounds. iRent/12RENT only discover allowlisted product paths
from category pages, not recursively through related products. Provenance,
deactivation, approval checks and category/type/duration matching remain in place.
The existing 22-category taxonomy and manual pricing fallback are unchanged.

## 3. Booking lifecycle — checked and confirmed bugs fixed

Three failing regressions were reproduced before fixes:

1. Concurrent Owner decisions approved **both** overlapping requests from different
   renters. Now only one approval/rental succeeds; the other pending physical
   request expires and its demo authorization is released.
2. Two concurrent RM400 refunds both succeeded against a RM570 capture. Refund
   operations now serialize by captured-payment resource and recompute the balance
   in integer cents before writing. The second excessive request is rejected.
3. Reusing a refund key with a changed amount returned the previous refund rather
   than rejecting the changed command. New refund records retain the requested
   amount mode; changed amount/reason/parent/type conflicts now return 409.

The existing MongoDB lease mechanism is reused with separate resource namespaces;
there is no new collection, dependency or migration. Request-creation locks remain
renter-scoped and pending dates remain **soft holds**. This does not turn pending
requests into availability reservations.

Owner decisions, cancellation and rental transitions share a short listing-scoped
operation lease. State and ownership are reread after waiting, preventing stale
double handovers/returns or cancellation racing approval from overwriting each
other. Relevant long operations recheck lease ownership before persistence.
Lease cleanup cannot delete a successor's lease.

Extension checks now reuse the confirmed-availability criteria, including unresolved
physical disputes. An extension cannot be approved after the item has entered the
return workflow. A recorded refund can reconcile an interrupted booking-status
update on retry without creating another refund or duplicate notification.

### Verified workflow coverage

| Workflow | Verified behaviour |
| --- | --- |
| Agreement/request | Authenticated renter, saved terms/charges and participant ownership; self-booking rejected. |
| Demo checkout | Card/FPX/Wallet flows, decline, retry, expiry, server-controlled total and one successful authorization; payment alone does not confirm dates. |
| Owner decision | Unpaid approval blocked; actual Owner only; concurrent approvals cannot confirm overlapping bookings. |
| Cancellation/rejection | Existing eligibility rules retained; authorization voided; scheduled rental cancellation remains consistent. |
| Physical handover | Owner-only transition and single capture, including double taps. |
| Extension | Active/overdue physical rentals only, Owner decision, vehicle eligibility, confirmed/manual/disputed availability checks. |
| Return | Renter evidence, Owner inspection, deposit bounds, one release/deduction/settlement, no duplicate completion side effects. |
| Services | Start/capture, Owner delivery, renter completion and settlement; physical-return/claim rules not applied. |
| Refunds | Admin-only, partial/full amount bounds, cent precision, identical retries, conflicting-key rejection and interrupted-status recovery. |
| Disputes/claims | Participant access, duplicate dispute checks, evidence/responses, physical-only damage-waiver claims, administrator decisions, dismissal/resolution history. |
| Availability/history | Malaysia date handling, pending soft holds, approved/active/disputed blocking, expired/rejected/cancelled/completed release, location privacy and saved agreement history retained. |

### Remaining policy/financial gaps — not silently invented

- **Extension billing:** approval currently changes end dates without an additional
  checkout or extra rental payment. This pre-existing behaviour is unchanged; a
  charging/acceptance policy and extension-payment workflow need a separate decision.
- **Dispute payouts/claims:** allocations and approved claim amounts are recorded
  as simulated decisions, not automatically applied as refund/Owner-payment ledger
  transfers. Real settlement is not implemented by this review.
- **Post-settlement reconciliation:** existing refund caps concern successful
  refunds against the capture. They do not implement recoupment of prior Owner
  settlements or netting of released deposits. Do not treat this demo ledger as a
  production financial reconciliation system.
- These leases prevent the tested concurrent operations; they do not make every
  multi-document save/external blockchain effect crash-atomic. Process crashes or
  partial writes outside the tested refund recovery still require status inspection.
- Dispute creation/resolution does not yet share every rental-operation lease.
  A comprehensive adversarial concurrency audit of all moderator/lifecycle writes
  remains future work; no universal concurrency/production-readiness claim is made.
- Payments remain simulated, and blockchain was disabled in isolated API tests.
  No real financial credentials were collected. Real-device/actual Ganache UAT is
  still required before the lecturer demonstration.

## Verification and handoff

- Full API suite: **389 passed, 3 optional skips**.
- Focused lifecycle/source checks: **127 passed** before the final harmless
  principal-recheck/diagnostic changes; final full suite includes those changes.
- Full AI suite: **482 passed**, two existing dependency deprecation warnings.
- Full Flutter suite: **407 passed, 3 skipped**; Auth0 persistence: **16 passed**.
- Analysis: **no issues**. Web and Android debug builds passed. `git diff --check`
  passed; existing CRLF conversion notices are not whitespace failures.
- API tests used temporary MongoDB instances and mock auth/local storage with FCM,
  email and blockchain disabled. No live booking, payment, identity or price-source
  records were modified. No secrets, model artifacts or training data changed.
- No UI redesign occurred. Existing responsive checkout/agreement/location widget
  tests ran, but no new manual visual/device session is claimed.

Restart the API from its original launcher/terminal to load these changes; do not
start another process on occupied port 3000. Rebuild/restart Flutter normally.
Use fresh test bookings for demonstration, verify unpaid/declined requests cannot
be approved, and check one physical rental plus one service all the way to completion.

## Commit message

```text
fix(renthub): align Auth0 gateways and harden sources and booking lifecycle

- align web and stub Auth0 constructor hooks without changing login behaviour
- parse iRent product duration tiers with bounded category-only discovery
- add strict 12RENT lease-field parsing while blocking malformed access policy
- report RentSmart empty-catalogue and pending-adapter diagnostics explicitly
- serialize competing approvals, cancellation and rental state transitions
- prevent concurrent over-refunds and reject changed refund idempotency requests
- reconcile durable refund retries and deduplicate refund notifications
- enforce disputed availability and active-state guards for extensions
- add lifecycle/source regressions and document unresolved financial policies
```
