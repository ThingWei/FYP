# Low-cost book prices and unfinished listing drafts

24 October 2026. These changes preserve existing uncommitted work. No database
migration, live import, source enablement, retraining or secret change is needed.

## Book prices

- Physical Books listings accept RM0.01–RM1,000,000 per day. Other physical
  categories and services retain their RM1 minimum. Entered prices still require
  finite values with at most two decimal places; zero, negatives, malformed text
  and scientific-notation strings are rejected.
- Flutter, Express, Mongoose, CSV validation, automatic quote normalization,
  measured coverage and offline export eligibility use the same category policy.
- An explicit RM5 / 14-day book observation retains both original values and the
  full-precision equivalent `5 / 14`. It is not an advertised one-day rate and
  cannot be reused as a one-day quote. Existing title/author/ISBN/edition and
  product-domain restrictions remain in force.
- FastAPI no longer raises a supported sub-RM1 book prediction to RM1. A raw
  book prediction below RM0.01 is unavailable, not silently raised. Statistical
  fallback supports book medians below RM1 and keeps its existing minimum count
  and dispersion requirements. Low-price uncertainty uses relative spread
  rather than hiding it behind an RM1 denominator.
- A promotion that rounds the effective price to zero is rejected; otherwise
  existing discounts and booking/payment rules remain unchanged.
- Controlled fixture predictions 0.01, 0.35, 0.99 and 1.00 remain those values for
  Books; a 0.004 fixture is unavailable. These are regression fixtures, not
  measurements of the deployed model's market accuracy. There is no fixed book
  price rule, retraining, invented observation or accuracy improvement claim.

## Draft versus submission

- Save Draft accepts missing title, price, location/pin, photos and relevant
  service details. The current category/type still identifies the form. Supplied
  values retain format, length, range, ownership and authorization checks. A
  one-character working title is allowed in a draft; review requires three.
- Draft prices remain missing/null, not zero in MongoDB. Flutter uses zero only
  as its existing non-null display-model sentinel, shows “Price not set”, and
  reopens the editable price as empty. Empty titles display “Untitled listing”.
- Save Draft does not invoke MyKad verification, item analysis or submission.
  Incomplete drafts are excluded from public feeds and cannot be booked.
- Submitting for review validates the title, price, location, condition and
  fulfilment or service package/duration before item analysis or a status change.
  Physical service/item locations still need pins; online services do not.
  Existing identity and three-photo checks remain. Optional descriptions,
  brand/model and comparison metadata do not become newly required fields.
- Draft location edits may be unfinished but invalidate old coordinates. Supplied
  pins must be valid and agree with structured details. Final submission checks
  the pin again. Public location privacy remains server-enforced.
- Failed saves retain the draft and photos. Reopening an incomplete draft keeps
  missing price/age/duration empty; editing uses the existing PATCH endpoint.
- The service venue selector is width-constrained to avoid overflow at 360/390px
  with increased text size. No new dependency, endpoint or Auth0 change.

## Verification

Final results: **453 API tests passed (3 optional skips), 446 Flutter tests passed
(3 existing skips), and 549 AI tests passed.** Flutter source analysis is clean;
web and Android debug builds succeeded. Existing nonfatal Socket.IO Wasm/font,
Firebase/preferences Kotlin migration and Python dependency/imputer warnings remain.
No unrelated Auth0 source errors were reported in this run. API testing uses
four test-file workers and a 60-second per-test limit; an earlier unbounded
parallel run stalled and was stopped, rather than reported as successful.

The deployed pricing artifact SHA-256 before/after is unchanged:
`2B9B23AC8069A3FEE776181131F65D1EBC82AA135A88CA918ABEDCAE5059A976`.

Tests cover
cent-price boundaries, explicit multi-day evidence reaching inference without
changing completed counts, category changes, invalid formats, ranges, CSV
preview without writes, book fallback, missing prices, incomplete physical and
service drafts, malformed supplied values, failed-save recovery and reopening.
Mobile widget checks use 360/390px and 1.4× text, with book pricing also at 1024px.

API tests use temporary MongoDB, mock identities and disabled external services,
not the live `.env`. AI fixture tests do not modify deployed artifacts. Physical
Android verification and real-market book evaluation remain separate handoff work.

Restart the API and AI service and relaunch Flutter with the normal launcher.
No live records need rewriting. Missing real book-price observations and the
synthetic-heavy fitted model remain accuracy limitations.

Commit message:

```text
fix(listings): allow unfinished drafts and low-cost book pricing

- separate draft persistence from mandatory review submission checks
- retain entered-value validation, pin privacy and identity/photo guards
- reopen missing prices cleanly and fix service venue selector overflow
- support physical book prices from RM0.01 across Flutter, API and AI
- preserve explicit multi-day quote amounts, periods and daily precision
- reject zero-rounded promotions and add draft/pricing regressions
```
