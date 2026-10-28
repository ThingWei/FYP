# Evidence-led product selection

Implemented 28 October 2026. Product selection now starts with locally stored
evidence. A maintained global catalogue is optional. XGBoost pricing remains in
place; this change does not replace its calculation with a median, retrain a
model or claim improved price accuracy.

## Owner workflow

1. Choose a category and specific category, then open Brand (Author/publisher for Books).
2. Browse/search suggestions from eligible rental references, reviewed marketplace evidence, saved catalogue identities and the curated fallback, in that order.
3. Selecting a brand opens matching models/titles even when no catalogue brand ID exists.
4. **Find more products** explicitly checks existing external catalogue providers. Results merge with local choices. Search changes return to the local path; another online lookup requires an explicit action. **Load more** may continue an explicitly requested online lookup.
5. **Enter manually** remains available during loading, empty results and failures. Cancelling does not alter the form.

Identity rows explain their source without showing rental amounts, private
listing data, Owner identities or reviewer details. Evidence selections say
**Product selected** / **Found in rental references** (or reviewed marketplace
evidence). Actual catalogue matches retain catalogue wording. Neither proves
authenticity or a correct price. Selecting a suggestion never fills daily price,
condition or age. Explicitly known variant/edition/ISBN/package/lens details are
carried into existing comparison fields.

Manual text, existing saved selections, entered prices, images and drafts remain
intact after failures and mode changes. A changed identity invalidates prior
estimates/IDs and incompatible comparison details. Account and request guards
ignore late results; optional-provider failures preserve local results.

## API, identities and eligibility

Existing owner-authorized `/api/v1/catalog/brands`, `/models` and `/search`
accept optional `mode=evidence`. Omit it for existing provider-backed behaviour.
For example:

```text
GET /api/v1/catalog/models?category=Devices&subcategory=Computers&brand=Logitech&mode=evidence
```

In evidence mode, even `refresh=true` only rereads local eligibility. No provider
call, catalogue upsert, materialized suggestion cache or background refresh is
created. Each request rechecks source enablement, configured approval, reference
deactivation, dates and validation through the existing shared reference policy.
Existing source jobs/settings are unchanged.

Marketplace suggestions require active physical listings, active Owners, valid
prices and the existing independently reviewed price-provenance check. Demo,
unknown-origin, unreviewed and AI-derived listing prices are excluded. Named
reference products require valid domain/type information; specification-only,
unbranded and placeholder manufacturers do not become invented brand entries.
These exclusions affect identity suggestions, not the validity of a separately
eligible specification-only pricing comparison.

Queries preserve existing search-length, result-limit and authorization rules.
Each reference/listing/cache scan is bounded at 1,000 records plus a lookahead;
search and brand constraints are applied before that bound. Up to 120 results
are exposed through existing expanding windows. `scanLimited` identifies a
bounded scan; users can narrow a search. Database/provider failures never disable
manual product entry.

Unicode-safe case/spacing normalization retains letters and model numbers.
Recorded exact aliases may deduplicate through an existing valid catalogue ID;
unreviewed fuzzy similarities cannot. Variants, editions, ISBNs, packages and
included lenses remain distinct. Wikidata cache entries retain domain validation.

Additive item metadata:

- `selectionSource`: `rental_reference`, `marketplace_evidence` or `catalogue`.
- `displayKey`: stable display identity, never used as a canonical catalogue ID.
- Optional existing comparison fields: variant, edition, ISBN, package and lens.

Additive response metadata: `mode`, `evidenceSuggestions` and `scanLimited`.
Existing envelope/fields are retained. A canonical product/brand ID is returned
only when a matching, context-valid saved catalogue entry supplies it. New local
fallback entries are not written to the catalogue merely to manufacture IDs.
Brand/model text and normal manual-entry payloads remain sufficient for listing
creation. Selection does not grant price provenance, manufacture bookings or
change clean training evidence. The OpenAPI contract is updated.

## Read-only live coverage

The aggregate audit issued only `find`/`getMore` commands, with zero database
writes and provider requests. It found brand and model suggestions in **22/22**
subcategories. **Nine** had eligible named-product evidence suggestions; others
used cache/curated identities. Counts below span brands/expanding windows, rather
than promising that every model is shown on the first page.

| Category | Specific category | Brands | Models/variants | Evidence models/variants |
| --- | --- | ---: | ---: | ---: |
| Devices | Smartphones | 45 | 107 | 2 |
| Devices | Cameras | 3 | 151 | 146 |
| Devices | Computers | 4 | 12 | 3 |
| Devices | Audio | 4 | 10 | 0 |
| Devices | Gaming | 3 | 8 | 2 |
| Devices | Other devices | 4 | 7 | 1 |
| Vehicles | Cars | 26 | 53 | 12 |
| Vehicles | Motorcycles | 19 | 33 | 15 |
| Vehicles | Bicycles | 8 | 14 | 6 |
| Vehicles | Other vehicles | 3 | 6 | 0 |
| Equipment | Event equipment | 3 | 6 | 0 |
| Equipment | Tools | 3 | 6 | 0 |
| Equipment | Sports equipment | 3 | 6 | 0 |
| Equipment | Other equipment | 4 | 9 | 3 |
| Books | Textbooks | 3 | 5 | 0 |
| Books | Reference books | 3 | 4 | 0 |
| Books | Fiction | 4 | 8 | 0 |
| Books | Other books | 3 | 4 | 0 |
| Clothing | Formal wear | 3 | 2 | 0 |
| Clothing | Costumes | 3 | 3 | 0 |
| Clothing | Traditional wear | 3 | 2 | 0 |
| Clothing | Other clothing | 3 | 6 | 0 |

Private audit: `services/api/.data/evidence/evidence-product-selection-2026-10-28/audit.json`.
Counts are a point-in-time diagnostic, not exhaustive catalogue coverage or a
price-accuracy measure. There may be valid price references without a known
manufacturer, particularly equipment/clothing; this does not justify inventing
brand/model suggestions. Missing evidence still permits manual entry/pricing.

## Verification and rollout

- Full API suite: **579 passed**, three optional skips. After final alias and strict-mode refinements, the affected catalogue suite passed **59 tests**.
- Full Flutter suite: **497 passed**, three skips. New tests cover ID-free brand/model selection, explicit online lookup, retained choices on failure, stale responses, account changes, draft/value preservation, and variant-aware merging. Form layouts passed at 360/390/1024 logical pixels with 1.4 text scaling.
- Full AI suite: **606 passed**. No AI source, fitted feature order, model artifact or pricing calculation was changed by this feature.
- Flutter analysis: **no issues**. Web and Android debug builds passed. Existing socket_io_common WebAssembly dry-run and Cupertino font warnings remain; the normal JavaScript web build succeeds.
- Launcher syntax, capability checks and disposable-process integration tests passed. No Auth0 analysis failures occurred in this run.
- API tests cover every subcategory fallback, mice/keyboards/monitors/controllers, Unicode names, category/brand isolation, packages, trusted aliases, missing canonical IDs, excluded provenance, active Owners, strict mode validation, authorization and deactivation without stale evidence.

The running API advertises `evidence-led-product-selection-v1`; the launcher
requires it to avoid reusing an old service that might ignore evidence mode and
perform provider refreshes. Restart/rebuild the Flutter Windows app or install
the new Android build to use the new selection flow. External source enablement,
live catalogue/listing records and database indexes were not changed. No real
Android camera/GPS/device interaction check was needed or performed for this flow.

The deployed price artifact SHA-256 remains:
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
The price-data gaps and frozen-model limitations documented in
[pricing quality results](AI_PRICING_QUALITY_AND_EVALUATION_RESULT.md) remain.
The proposed comparison-led pricing calculation is a separate follow-up.

## Commit message

```text
feat(catalog): add evidence-led product selection with optional online lookup

- browse eligible rental references and reviewed marketplace identities first
- retain cached/curated fallback across all 22 physical subcategories
- add read-only evidence mode without automatic catalogue refreshes
- support model selection by brand text without invented catalogue IDs
- preserve variants, packages, Unicode names and trusted existing aliases
- keep manual entry, drafts and local results through failures and stale requests
- retain XGBoost pricing, provenance gates and deployed model weights
- document live coverage, API compatibility and verification results
```
