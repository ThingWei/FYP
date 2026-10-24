# Rental-price evidence gaps and collection priorities

Later 24 October follow-up: [Goritta parser preparation](GORITTA_PRICE_SOURCE_ONBOARDING_RESULT.md)
adds a registered Sports candidate, still blocked pending written reuse permission.
The snapshot below remains unchanged; registration does not create observations.

24 October 2026, 13:33 MYT. Read-only MongoDB snapshot; no source enablement,
imports, bookings, retraining, migrations or environment changes. Existing
uncommitted work is preserved. This is an audit and collection handoff, **not
completion of real-world price coverage**.

## Measured coverage

334 stored observations passed current reference eligibility across **16/22**
physical subcategories. There are 253 named-product observations and 81
specification-only observations. **None records item age or condition.** These
are advertised asking prices, not achieved rental prices. Source approvals below
refer to configuration only; no independent reuse-rights review was inferred.

| Category | Specific category | Eligible observations | Distinct source-product offers | Immediate gap |
| --- | --- | ---: | ---: | --- |
| Devices | Smartphones | 2 | 2 | Few models; one website; iRent review still pending |
| Devices | Cameras | 181 | 181 | 138 lenses versus 43 cameras; one website |
| Devices | Computers | 3 | 3 | Laptops only; no desktops |
| Devices | Audio | 8 | 8 | Specification-only microphones; no speakers/headphones/mixers |
| Devices | Gaming | 6 | 2 | Two consoles across duration bands; no controllers/VR |
| Devices | Other devices | 6 | 6 | Walkie-talkies/capture devices; no tablets/watches/printers |
| Vehicles | Cars | 73 | 13 | Duration bands are not 73 independent products; one website |
| Vehicles | Motorcycles | 15 | 15 | One website; missing condition/age |
| Vehicles | Bicycles | 10 | 10 | One website; named/specification identity mix |
| Vehicles | Other vehicles | 0 | 0 | No eligible scooter/unicycle observations |
| Equipment | Event equipment | 16 | 16 | All specification-only; no mixer/tripod/tent/table/chair evidence |
| Equipment | Tools | 1 | 1 | One specification-only drill; other tool types missing |
| Equipment | Sports equipment | 0 | 0 | No eligible sports/camping observations |
| Equipment | Other equipment | 5 | 5 | Cleaners/washers/vacuums; one website |
| Books | Textbooks | 0 | 0 | No verified current per-title/edition observation |
| Books | Reference books | 0 | 0 | No verified current per-title/edition observation |
| Books | Fiction | 0 | 0 | Book-rental candidate below needs product/access validation |
| Books | Other books | 0 | 0 | A children's title needs contextual classification, not automatic genre guessing |
| Clothing | Formal wear | 1 | 1 | One specification-only jacket; no suits/formal dresses |
| Clothing | Costumes | 3 | 3 | Specification-only; one website |
| Clothing | Traditional wear | 3 | 3 | Kurta/traditional costumes; no hanfu or Malay garments |
| Clothing | Other clothing | 1 | 1 | Specification-only winter package; no rainwear |

Offers normalize URL/product identity; they are not independently confirmed
businesses, physical items or successful rentals. Website counts do not prove
independence. A configured product type with a nonzero count still has no
statistical sufficiency guarantee. Observation timestamps remain 22 October;
this audit did not refresh them or falsely describe them as collected today.

## Implemented improvements

From `services/api`:

```powershell
npm.cmd run audit:price-coverage
# Optional NEW aggregate report; an existing file is never overwritten:
npm.cmd run audit:price-coverage -- --output .data/evidence/price-coverage-new.json
# Lower the native read bound if needed; exceeding it refuses a partial report:
npm.cmd run audit:price-coverage -- --limit 1000
```

The new CLI reuses the same coverage builder as the admin source screen. Native
MongoDB reads have field projections, a 10-second query timeout and a maximum of
10,000 observations. It does not initialize Mongoose schemas, collections or
indexes, contact providers, run jobs or perform database writes. It emits safe
aggregate counts, configured source gates, missing semantic types and next
collection actions—not private account/document/location data or raw price rows.
Optional JSON output reuses exclusive creation to preserve previous reports.

The offline pricing export had omitted ISBN, edition, variant and package fields
from its native query projections. These now survive export for both listings
and external references. A regression checks that another book edition does not
silently become compatible price evidence after export. No model features,
ranking weights, runtime pricing priority or fitted artifacts were changed.

## Research leads: not enabled or ingested

Public pages were reviewed on 24 October. A research lead is not source approval,
an implemented parser or a database observation. Search snippets and cached
pages cannot validate live per-product availability or collection permission.

### Sports equipment: Goritta

[Goritta's camping rental page](https://goritta.com/pages/camp-like-a-pro-goritta-camping-equipment-rental)
shows named tents with a four-day rental period. Examples include the Mobi Garden
QR tent and DoD One Pole tent; unavailable/maintenance entries must be excluded.
Camping furniture, cooking gear and power stations must not be relabelled into
unrelated supported product types just to populate the Sports category.

[Its terms](https://goritta.com/policies/terms-of-service) require express written
permission for reproduction/exploitation of the service. No permission was
declared or requested on the user's behalf. **Collection remains blocked pending
review/permission.** A future permitted adapter must retain the four-day package,
original amount, pickup terms and excluded charges—not invent a one-day offer.

### Fiction / other books: The Joy of Books

The operator's [about/how-it-works page](https://thejoyofbooks.com/about/)
describes a separately charged book rental period of 60 days and refundable
per-book deposits. Its [Fiction catalogue](https://thejoyofbooks.com/product-category/rentals/fiction/)
lists *The Lord of the Rings*, but the displayed catalogue amount alone must not
be interpreted as the rental fee. Deposit, shipping and rental charges need
explicit separation on a directly accessible product page.

The web tool supplied cached pages; direct product/terms retrieval did not
complete, including a bounded probe using existing access-policy checks. No
access restrictions were bypassed. Product metadata, current availability,
author/edition/ISBN, deposit separation and reuse conditions remain unverified.
**No per-title observation or adapter was added.** The source cannot be stretched
to claim Textbooks or Reference books coverage without corresponding titles.

### Other vehicles: mobility-scooter candidate

[Fresco's electric-scooter rental page](https://electricwheelchair.com.my/electric-scooter-rental/)
publishes explicit one-/two-week packages excluding delivery/deposit. However,
its FAQ says the final quote varies by model. Do not attach the page-level price
to the displayed X5 as exact-model evidence without clarification. A potential
specification-only mobility-scooter observation is not an e-kick-scooter price;
month lengths also must not be guessed. Access/reuse and model association need
review before any adapter or ingestion.

[Dr Scooter's rental page](https://www.drscooter.my/rental) uses minimum “from”
rates. It is unsuitable for the current strict quote contract unless the provider
supplies explicit product/period quotes. It was not enabled or imported.

### Existing onboarding gates

The live configuration has eleven approved/enabled existing sources. iRent and
12RENT have parsers but lack configured approval; earlier 12RENT policy-validation
restrictions are not cleared by this audit. RentSmart and optional AVM have no
usable registered adapter. No existing source was deleted or replaced. The four
book subcategories still have no registered external price source.

## Recommended order and gates

1. Resolve access/reuse and product semantics for Sports and Other vehicles;
   validate fixtures and bounded access diagnostics before a separate enablement.
2. Verify a current book product and its rental/deposit/period separation. Seek
   permissioned per-title observations for unsupported book domains rather than
   using retail prices, subscriptions or blanket per-category prices.
3. Review iRent permission to diversify sparse smartphone evidence. Broaden
   laptop/audio/gaming/clothing **product types**, not repeated camera-lens quotes.
4. Preserve unknown condition/age. Obtain permissioned measured values; release
   year, stock labels and random synthetic values are not physical item age.
5. Export a new reviewed dataset and run the existing forward-time evaluation
   against the category-median baseline. Keep asking prices, accepted bookings,
   completed rentals and staged activity separate. Existing dedicated-demo
   activity does not become real achieved-rental evidence.

No automated retraining, mass demo booking or seeded “real-world” rental history
was performed. Model accuracy and all-category real price coverage remain open.

## Verification

Focused audit/export/domain tests: 44 passed. Full API: **456 passed, three optional
skips** (459 total), with isolated mock auth, temporary MongoDB and disabled external
services/jobs. Tests cover all-22 reporting, read-only native access, no index or
collection creation, bounds, private-field exclusion, source gates, age/condition
gaps, low book equivalents and preserved comparison metadata.

No Flutter or AI inference source changed in this follow-up; their tests/builds
are not claimed as rerun. The current deployed pricing artifact remains intact.

Commit message:

```text
feat(pricing): audit category evidence gaps and preserve export identity details

- add bounded read-only all-category coverage audit and collection priorities
- separate source configuration, product-type gaps and unknown age/condition
- retain ISBN, edition, variant and package metadata in native pricing exports
- document measured coverage and permission-gated source research leads
- preserve live data, source settings, fitted models and transaction provenance
```
