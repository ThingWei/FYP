# Similar-item pricing selection and clarity

Later duration-policy correction: see [rental-length pricing results](PRICING_RENTAL_DURATION_RESULT.md).
Explicit daily rates can now support qualified longer-rental baselines; the
strict-period statements below remain applicable to fixed packages and realised
rental averages. The R50 class-comparison defect documented below remains open.

28 October 2026, Malaysia time.

RentHub selects a bounded set of comparable rental-price observations before
building the existing XGBoost features. Exact products remain preferred. Similar
items support a labelled rough estimate; catalogue recognition and name similarity
do not establish an exact market value.

## Selection rules

The shared `selectComparableTier` helper serves live inference, exports and the
forward-time evaluation worker. Existing category/subcategory, product-type,
edition, capacity, package and clean-provenance restrictions remain.

| Priority | Evidence | Minimum before using this tier |
|---|---|---:|
| 1 | Exact canonical product, then exact brand/model text | 1 |
| 2 | Same brand/model name, package/version details unconfirmed | 1; always broad and qualified |
| 3 | Same brand and model-name family | 2 |
| 4 | Same brand/type, condition and state | 2 |
| 5 | Same brand/type Malaysia-wide | 2 |
| 6 | Compatible product type locally, then Malaysia-wide | 3 |

An insufficient last tier remains below its minimum and does not gain an exact
label. Books keep title/author/edition/ISBN restrictions; family matching is
disabled for books. Mice, keyboards, monitors, laptops, consoles and controllers
remain separate product types.

Rank by model-family hints, known closer condition, age, rental length, area and
recency. Family keys normalise generation numbers while retaining Pro/Ultra/Lite
suffixes. Numeric proximity within a family is a bounded retrieval hint. These
heuristics do not assert equal specifications or value. Stable identifiers break
ties; reference prices do not determine similarity ranking.

Use at most **12 observations per asking-price/completed-rental group**, rather
than every match. This engineering bound is not an empirically optimised setting.
Inference counts and medians describe selected observations. Source deduplication
remains in place. Fixed-duration completed averages must match the requested
length; external duration bands remain usable only within their advertised band.
Platform daily asking prices do not acquire an invented fixed duration. Unknown
age/condition stay unknown. Offline recency uses each prediction's time cutoff.

## Price presentation

Endpoints and fitted feature order are unchanged. Additive `comparison_summary`
metadata retains selection version, basis, candidate/selected counts, minimum
status, missing details, observed bounds and original model bounds.

- Exact evidence retains the existing same-product explanation.
- Matching name/incomplete details: “Based on a matching model’s advertised price.
  Some version or package details are missing, so this is a rough guide.”
- Supported similar comparisons: “Based on comparable rental prices. Exact-model
  prices are limited. You choose the final price.”
- Sparse or absent/older metadata retains the conservative insufficient-model
  evidence message. Unavailable estimates retain manual pricing and retry.

Broader estimates retain **Rough daily estimate** and the visible synthetic-heavy
training warning. Expanded details show missing age/condition/package information,
source counts and asking-price limitations. **Use this price** remains explicit.

Broader displayed bounds enclose both original model bounds and selected observed
prices. The predicted amount is unchanged by this display step. This envelope is
not a newly calibrated prediction interval; diagnostics retain the original bounds.
Prices may fall outside the displayed range. Exact-estimate bounds stay unchanged.

## Read-only database and frozen-model check

A bounded native read inspected the twelve demo identities. 335 stored references
met the initial active/date/status query; source/type/period/package eligibility
and deduplication were applied separately. This is not a claim of 335 independently
verified transactions.

| Outcome for the 12 identities | Count |
|---|---:|
| Exact named product references | 4 |
| Matching model, unconfirmed package/version details | 6 |
| Broader same-brand/type comparisons | 2 |
| No selected reference | 0 |

Samsung S23/S24 preferentially select their respective RM190/RM230 source quotes,
rather than sharing a brand-wide median because package details are absent.
Camry selects its RM500 one-day quote with an unconfirmed-details label, rather
than averaging other Toyota models. These are reference inputs, not predictions.

The existing artifact returned **12/12 available suggestions** offline. Inputs
used each demo's explicitly fictional condition/age, one rental day and neutral
Owner features. This was a functional smoke test, not held-out accuracy evaluation.
Example model outputs: S23 RM136.53, S24 RM154.76 and Camry RM389.87. Express also
applies the broader-range envelope; raw FastAPI bounds in the smoke report precede
that presentation step. Outputs are not expected achieved transaction values.

Canon 5D/5D Mark III still lack exact selected observations and both produced
RM151.73. Brand/type comparisons cannot establish their distinct market values.
Many references lack specifications, product segment, condition and age. Family
heuristics do not replace these data. No measured accuracy improvement is claimed.

Private reports:

- `services/api/.data/evidence/similar-pricing-2026-10-28/audit-v2.json`
- `services/ai/.data/evaluation/similar-pricing-2026-10-28.json`

Artifact SHA-256 remains
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
No retraining/deployment, source activation, imports or listing/booking/payment/
account/reference writes were performed. Demo, AI-derived, unknown-origin and
simulated-payment evidence remain excluded by existing provenance gates.

## Verification and use

Regressions cover bounded ranking, exact/unconfirmed-name precedence,
price-independent selection, families/suffixes, peripheral/package/period
exclusions, missing data, temporal cutoffs, inference counts and range disclosure.
Flutter checks cover 360/390/1024 pixels with 1.4 text scaling, malformed/legacy
metadata, applying a price and existing draft/empty-price/stale-response/upload
retry behaviour. No real-device UAT or independent real-price accuracy evaluation
was performed.

| Check | Result |
|---|---|
| Full API suite | 511 passed, 3 existing skips, 0 failed |
| Focused API pricing/inference/export checks | 89 passed; final selector/range checks 18 passed |
| Full Flutter suite | 486 passed, 3 existing skips |
| Relevant AI pricing/disclosure/frozen-evaluation tests | 29 passed |
| Flutter analysis | No issues found |
| Web build | Passed |
| Android debug APK build | Passed |
| Read-only functional check | 12/12 available; 4 exact, 6 unconfirmed matching models, 2 broad |
| Deployed model hash / whitespace check | Unchanged / passed |

Existing nonblocking Wasm/Socket.IO, optional Cupertino font and Kotlin migration
warnings remain. No new Auth0/analyzer errors occurred. Full suites passed before
the final additive preservation of original range diagnostics; the final selector/
range unit checks also passed afterward.

Restart Express if not running in watch mode, then hot-restart/rebuild Flutter.
Request a fresh estimate after checking the package and rental length. An already
displayed estimate does not refresh automatically. Retraining is unnecessary for
this change.

## Follow-up diagnostic: EOS R50, 28 October (resolved by the next follow-up)

The user reported a main suggestion above RM300. A read-only reproduction found
no exact R50 reference in the selected evidence. The model-name family heuristic
groups `EOS R50` with seven stored Canon EOS R3/R5/R6/R7 body-only observations,
whose median is RM400. Excellent condition, age 1, one day and neutral Owner
features produced RM357.45; age 3 produced RM316.67. These are diagnostic model
outputs, not validated R50 prices. No fixed R50 price rule was found.

This exposes a remaining semantic-selection defect: sharing an EOS R name stem
does not establish comparable capabilities or market segment. The current generic
camera type is also too coarse for adapters, action cameras and camcorders seen
in the with-lens fallback diagnostic. Passing regression tests and the twelve-item
smoke check did not establish those comparisons as sound. No production fix,
fixed-price cap, source write or model retraining was performed in this diagnostic.
Strong specification/type validation and conservative handling when those data
are unavailable are still needed before claiming reliable R50 comparisons.

Private reproductions: `services/api/.data/evidence/r50-price-check-2026-10-28.json`
and `services/ai/.data/evaluation/r50-price-check-2026-10-28.json`.

The subsequent [pricing suitability and frozen evaluation result](AI_PRICING_QUALITY_AND_EVALUATION_RESULT.md)
supersedes the unresolved defect above. Name stems no longer establish camera
comparability: matching reviewed specifications are required for cross-model
camera references, and known classes reject unknown/conflicting classes. Stored
R50 evidence now abstains instead of borrowing R3/R5/R6/R7 prices. The parser
also recovers identifiable body/lens kits with distinct quotation identities;
these were previewed privately rather than imported. Full verification and
remaining evidence limitations are recorded in that result.

## Commit message

```text
feat(pricing): rank similar rental references and clarify estimates

- prefer exact and qualified matching-model price observations
- add bounded same-family retrieval and rank known comparable attributes
- preserve type, package, duration and clean-evidence restrictions
- share selection with exports and forward-time feature preparation
- explain similar estimates while retaining missing-data/training disclosures
- preserve predictions and widen broad displayed ranges to observed references
- test inference, sparse evidence, mobile layouts and legacy responses
```
