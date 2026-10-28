# Pricing evidence follow-up: sources, transactions and evaluation

Superseded source state: [five disabled sources are now removed](PRICING_SOURCE_CLEANUP_AND_READINESS_RESULT.md).
The diagnostic counts below describe the earlier research pass, not active registrations.

27 October 2026. This follows the existing source review and implements the
requested transaction-collection preparation and frozen-model evaluation steps.
It does not claim that genuine transactions or publisher approvals occurred.

## Source onboarding outcomes

Bounded diagnostics used the existing allowlisted transports/parsers. They did
not connect to MongoDB, import quotes or enable sources. Access, parser results
and reuse clearance were recorded separately for all 16 registered sources in
the private `source-review-outcomes.json`. Most entries explicitly retain their
prior audit state; they were not all re-probed in this follow-up.

| Source | Actual follow-up | Remaining issue |
|---|---|---|
| iRent | Transport/parser probe: 6 accepted duration-band observations over 7 pages; 5 skipped unsupported layouts/quotes | Reuse review unresolved; no automatic enablement |
| ITPA | Transport/parser probe: 3 accepted quotes from 1 page; no skips | Rental-price reuse scope unresolved; keep on-site and separate delivery/setup terms |
| 12RENT | Collector returned `ACCESS_RESTRICTED`; parser did not run | Need a permitted feed or publisher clarification; no bypass |
| RentSmart | Direct electronics page has no usable product quotes; linked terms PDF returned 404 | No adapter or reuse clearance established |
| The Rental Guy camping | Public page remains readable; research parser remains unregistered | Reuse review unresolved; tax, handling days and bundles remain separate |
| RENTISM, Cilt, DRIVOR, Alquiler, Ecocana, Goritta, PC Rent, JomRentPro, Partymix, Futago, AVM | Prior audited state retained; not newly probed here | No new clearance or enablement |

The [iRent customer terms](https://irent.my/customer-terms-and-conditions/)
describe vendor-supplied listings and customer rental procedures; they do not
establish a reuse grant for this dataset. The general terms endpoint timed out
through the research tool. Do not substitute another similarly named company's
terms for iRent.my.

The [ITPA price page](https://itpa.my/pc-rental.php) publishes daily on-site
computer offers and separates delivery/setup charges. Its own linked
[terms page](https://itpa.my/terms-conditions.php) addresses chess programmes and
teaching materials; no rental-price reuse conclusion was established from it.
An unrelated similarly named organisation's terms were excluded from review.

The [RentSmart electronics page](https://rentsmartasia.com/product-category/rent-equipment/electronics/)
still exposes no catalogue prices. Its [terms landing page](https://rentsmartasia.com/terms-of-service)
links a PDF that failed retrieval; search excerpts were not imported as quotes.
The [Rental Guy camping page](https://therentalguy.com.my/camping-equipment-2/)
distinguishes individual one-day references from bundles and date-specific totals.
This establishes quote semantics, not independent reuse clearance.

No reviewed source was marked approved by this work. A working parser or
reachable page is not substituted for the unresolved review. No messages were
sent to publishers. A maintainer can request clarification using this unsent text:

> I am building RentHub for my university FYP. May I store a limited set of your
> publicly advertised rental amounts, rental periods and product specifications,
> with source links and dates, for price-comparison research and evaluation? I
> would keep asking prices separate from completed transactions and would not
> copy customer information or product photographs. Please let me know any
> access, attribution, refresh or redistribution conditions, or a permitted feed.

Written permission is required where applicable source conditions require it;
this report does not give a blanket legal conclusion about public price facts.

## Step 3: genuine transaction evidence

Fresh native read-only inspection still found 14 physical listings, all missing
price-origin metadata; 25 bookings, including 2 completed; and 25 payment records,
all simulated. One completed booking has simulated payment records and the other
has no payment evidence. No independently verified achieved-rental cohort exists.

The current payment adapter explicitly returns `sim_` references and simulated
results. Completing more demonstration bookings therefore cannot satisfy the
clean completed-rental policy. No payment records, provenance markers or booking
statuses were changed to manufacture this evidence. Real payment integration is
outside this task; current simulation remains intact.

Prepared `transaction-collection-template.json` contains **zero records and zero
recruited participants**. It extends the existing consent/test-session kit with
separate natural/staged activity, asking/achieved amount basis, price independence,
known-at time, duration, condition/age and private evidence references. It is a
planning file, not a training export or approved ingestion route.

For actual collection:

1. Obtain appropriate participant agreement and use participant codes. People
   perform their own actions; do not create clicks/bookings on their behalf.
2. Keep existing dedicated demo accounts and their scripted sessions staged.
   Usability feedback is useful but is not a genuine commercial transaction.
3. Record independently agreed rental amounts and explicit periods separately
   from deposits, delivery, waivers and fees. Preserve unknown age/condition.
4. Retain consent and supporting evidence privately. Do not put identity
   documents, credentials, account identifiers or precise coordinates in the kit.
5. Review actual transaction/payment evidence and item-price provenance before
   any clean classification. A separately documented external transaction would
   need its own approved review/ingestion workflow; none was enabled here.
6. Preserve a later chronological holdout before candidate fitting. A number of
   rows or completion of a scripted scenario is not an accuracy threshold.

Step 3 is **prepared, with evidence collection still outstanding**. It cannot be
reported as collected genuine history while only demo transactions exist.

## Product-audit consistency fix

The older `auditPricingEvidence.js` command still reconstructed completed rentals
from mutable current listings and payment-status labels. It now reuses the clean
native export, immutable snapshots and payment/provenance policy. All reads are
bounded, no collections/indexes are created, and imports do not execute the CLI.

The command preserves its four arguments. It reports platform asking prices,
external asking references and completed-rental evidence separately. Domain/type,
duration and time restrictions are applied; unknown age/condition are not assigned
defaults. Demo configuration cannot reintroduce contaminated records.

Actual Toyota/Camry check: zero clean platform asks, zero clean completed rentals,
and one exact compatible one-day external asking reference selected. This is an
asking-price comparison, not a Toyota achieved-rental accuracy result. Only
`find` and `getMore` database commands were observed.

## Step 4: frozen-artifact evaluation executed

Fresh private export: **334 external asking-price observations**. Platform rows
excluded by the shared policy: 6 simulated-payment booking observations, 1 booking
without an immutable historical snapshot, and 3 active prices of unknown origin.
These booking exclusions include approved/active records, not only completed ones.

The existing global chronological cutoff produced 310 earlier history rows and
24 later asking targets. Comparable features used only earlier eligible history,
excluding the target's own offer/product group and incompatible types/packages.
All 24 targets lacked compatible prior evidence: prediction coverage **0/24**,
abstentions **24/24**. MAE, RMSE, R-squared and baseline errors remain null, with
explicit insufficient-data states. No completed-rental holdout exists.

The deployed bundle was loaded in `--mode deployed`. No fit or deployment ran.
Its missing row-level training manifest still prevents proving training/holdout
independence, so even future numerical results on this artifact remain diagnostic
until that limitation can be resolved. Retraining is not justified by this run.

Deployed SHA-256 remains
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

## Private deliverables and commands

New files, all excluded from Git:

- `services/api/.data/evidence/pricing-transaction-followup-v2/summary.json`
- Adjacent `observations.json`, `preview.json`, `source-review-outcomes.json`
  and `transaction-collection-template.json`.
- `services/ai/.data/evaluation/pricing-transaction-followup-v2.json`.

The review preview remains empty pending clearance; the observations file is
explicitly stored-data diagnostics, not newly cleared market data.

From `services/api`:

```powershell
node src/scripts/auditPricingEvidence.js Vehicles Cars Toyota Camry
# Fresh audit: choose a NEW directory; existing outputs cannot be overwritten.
npm.cmd run audit:pricing-real-world -- --output .data/evidence/NEW-DIRECTORY
```

From `services/ai`, using the actually saved follow-up export:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/evidence/pricing-transaction-followup-v2/observations.json `
  --mode deployed --report .data/evaluation/NEW-REPORT.json
```

## Verification

Regression checks cover contaminated legacy labels, simulated payments, stale and
late-known observations, unknown acquisition time, incompatible peripheral types,
duration bands, asking/achieved separation, invalid CLI arguments and unchanged
input payloads. Live records, source settings and deployed models remain unchanged.
No Flutter code changed during this follow-up, so presentation rebuilds were not
repeated. Suite results are recorded after the final run below.

| Verification | Result |
|---|---|
| Full API suite | 499 passed, 3 existing skips, 0 failed (502 total) |
| Focused frozen/pricing/evidence AI suites | 34 passed; 2 existing controlled-fixture imputation warnings |
| New product-audit regression suite | 3 passed, including unknown external acquisition time |
| Native product-audit check | Toyota/Camry aggregates returned; only `find` and `getMore` |
| Fresh aggregate/source-state comparison with earlier audit | Unchanged |
| Deployed pricing-model SHA-256 | Unchanged |
| `git diff --check` | Passed |

API tests used process-local mock authentication, disabled jobs/push/email/
blockchain, local storage and an unreachable AI URL; each database test used its
isolated temporary MongoDB. The complete suite needs `CATALOG_MODE=domain` for
its stubbed provider tests and the existing namespaced Auth0 name/email claims.
Initial invocations with missing claim settings or a disabled catalogue mode
failed those configuration-dependent tests. The final invocation used the
documented settings and passed; no Auth0 or catalogue application code was changed.

Completion status: source diagnostics **executed**; no new reuse approvals;
transaction collection **prepared, actual genuine records outstanding**; frozen
evaluation **executed, insufficient evidence for numerical accuracy**; retraining
and deployment **not performed**. Older audit outputs remain intact.

## Commit message

```text
fix(pricing): align product audits with clean transaction evidence

- reuse bounded native exports instead of mutable listing and payment-status joins
- separate asking references from verified achieved-rental evidence
- constrain diagnostic counts by type, duration and evidence availability
- prepare private source-review outcomes and an empty transaction collection kit
- run frozen evaluation without fitting or replacing the deployed model
- document unresolved reuse, genuine-history and temporal holdout gaps
```
