# Catalogue peripheral coverage: 24 October 2026

## Outcome and scope

Improved the existing provider integration rather than adding another vendor.
Computers now supports mice, keyboards and monitors alongside laptops/desktops;
Gaming supports controllers alongside consoles/VR headsets. These are product
types within existing subcategories, not new listing categories.

Flutter still calls only the authenticated Express `/api/v1/catalog/brands`,
`/models` and `/search` endpoints. No new credentials, dependencies, migrations,
bulk imports, production database writes, pricing rules or model training.
Unrelated uncommitted work is preserved.

## Inspected baseline and root cause

- `services/api/src/modules/catalog/catalog.coverage.js`: all 22 subcategories
  already had a provider/fallback strategy.
- `catalog.curated.js`: three starter brands per subcategory, but no mouse,
  keyboard, monitor or controller identities. Computers was laptop-centric;
  Gaming was console-centric.
- `catalog.provider.js`: generic Wikidata fallback required descriptive domain
  words plus model/product wording and the selected brand. Real records such as
  DualSense lacked those particular words despite valid type/manufacturer claims.
- `catalog.service.js` / `productCatalog.model.js`: existing provider-normalized
  MongoDB caching, deduplication, selection verification and source namespaces.
- `catalog.validation.js`, `catalog.routes.js`, `catalog.controller.js`: existing
  owner authorization and unchanged request/response shapes.
- `apps/renthub_flutter/lib/features/live/live_catalog_picker.dart`,
  `live_owner_shell.dart`, `live_renthub_controller.dart`: existing initial-page
  selection, manual entry, canonical-ID retention and stale-response handling.

Before this increment, actual provider searches for Logitech MX Master 3S,
Logitech MX Keys S, Dell U2723QE and Sony DualSense returned no results. This
was not proof that Wikidata lacked those product types.

## Provider strategy and filtering

`catalog.deviceDomains.js` centrally defines reviewed Wikidata class roots:

| Subcategory | Product types / class IDs |
| --- | --- |
| Computers | laptop Q3962; desktop Q56155; mouse Q7987; keyboard Q250; monitor Q5290 |
| Gaming | console Q8076; controller Q865422; VR headset Q19600329 |

Both use `wikidata-devices -> renthub-curated -> manual-entry`.
Other 20 provider strategies are unchanged. Initial query-less brand browsing
uses curated identities/cache, with no unrestricted generic search.

Text search discovers at most 24 candidate entities. A bounded structured query
then requires a supported instance/subclass relationship AND manufacturer/brand
relationship (`P176`/`P1716`). Model requests validate the selected brand/its
reviewed aliases; an explicit structured manufacturer ID must also match.
Typed model queries are candidate-ID constrained; initial model pages are
manufacturer-ID constrained. Invalid IDs, incompatible types, conflicting makers
and oversized names are discarded. Malformed upstream response schemas and
outages are unavailable checks, not reliable empty results. Existing timeouts,
rate spacing and public result limits remain in force.

Manufacturer punctuation is normalized consistently: `Apple Inc.` must not be
rejected solely because its trailing period becomes whitespace. A WDQS forward
property-path hint follows [official query optimization guidance](https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/query_optimization).

New records use namespaced `wikidata-devices:Q...` identifiers and contain
product type, Wikidata type, manufacturer entity, validation method and source
URL in `specifications`. Existing saved IDs are not rewritten. Generic old
Wikidata cache rows cannot bypass the new Computer/Gaming provider chain; rows
are not deleted and existing saved selections remain resolvable.

## Actual live checks, not just mocked fixtures

Read-only public requests were made from this machine. No live MongoDB data was
written by these checks. These are representative examples, not an exhaustive
or statistically representative accuracy benchmark.

| Product type | Query / selected brand | Actual result |
| --- | --- | --- |
| Mouse | Logitech / MX Master 3S | Wikidata Q125697788, mouse |
| Keyboard | Logitech / MX Keys S | Wikidata Q125697771, keyboard |
| Controller | Sony / DualSense | Wikidata Q89695113, manufacturer Sony Interactive Entertainment |
| Monitor | Apple / Apple Thunderbolt Display | Wikidata Q4781242, monitor |
| Monitor | Apple / Studio Display | Wikidata Q111154626, monitor |
| Monitor | Dell / U2723QE | Reviewed RentHub entry; no usable external match in this check |

Successful typed searches took roughly 1.6-3.9 seconds in the observed runs.
Some repeated typed searches, broad brand queries and Logitech model preloading
hit the existing four-second upstream timeout. The reviewed entries remained
available; this is not reported as external success. A Sony canonical-maker
first-page query returned consoles and controllers including DualSense.

Reviewed fallback identities are sourced individually, not invented:

- [MX Master 3S: Logitech support](https://hub.sync.logitech.com/mx-master-3s)
- [MX Keys S: Logitech product page](https://www.logi.com/en-us/shop/p/mx-keys-s.920-011406)
- [U2723QE: Dell Malaysia datasheet](https://www.delltechnologies.com/asset/en-my/products/electronics-and-accessories/technical-support/dell-u2723qe-monitor-pcf-datasheet.pdf)
- [DualSense: Sony manual](https://www.playstation.com/content/dam/global_pdc/en/corporate/support/manuals/accessories/ps5-accessories/dualsense-wireless-controller-cfi-zct1w/EN_FR_AMER_DualSense_Wireless_Controller_Instruction_Man_Web.pdf)

Only factual identity strings/source links were added; no manufacturer images,
manual text, price rules or training data were imported. Wikidata structured data
is [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing); that does not license
linked images or manufacturer documents for arbitrary copying/training.

## Verification

- `catalog-peripherals.test.js`: structured domain/manufacturer validation,
  duplicate/unknown entities, software exclusion, canonical-maker conflicts,
  corporate punctuation, unavailable/malformed/empty responses, and offline
  fallback for all four peripheral types.
- `catalog.test.js`: authenticated Express selection, MongoDB caching, preserved
  canonical identity, category-pair rejection, excluded old generic cache and
  all-22 initial browsing/model-page regressions.
- `catalog_peripherals_test.dart`: 12 selection cases at 360/390/1024 pixels with
  1.5x text, preserving structured/curated identifiers and manual-entry access.
- Existing catalogue widget suite: stale queries, failure recovery, manual
  switches and retained values; 29 focused Flutter cases passed in total.
- Full API suite: 472 passed, 3 existing optional live tests skipped.
- Full Flutter suite: 465 passed, 3 existing skips.
- Full Dart analysis: no issues.
- Flutter web build: passed. Existing Socket.IO WebAssembly dry-run warning
  remains; it does not prevent the JavaScript web build.
- No AI source/model changed in this increment. The deployed default pricing
  artifact remains SHA256
  `2B9B23AC8069A3FEE776181131F65D1EBC82AA135A88CA918ABEDCAE5059A976`.

## Limitations and next step

All 22 subcategories have tested starter coverage, not complete externally
verified coverage. Other domains still use their existing domain providers or
description-filtered general fallback; this increment does not certify those
fallbacks as complete. Wikidata may omit new models, regional variants,
manufacturer links or classifications, and English-label matching is limited.
Model-family records can appear; these do not establish an exact SKU/variant.

Product identity is not authenticity, ownership, condition or rental-price
evidence. No new Malaysian rental prices or completed transactions were created;
pricing can still need broader comparisons or manual entry. No vendor account
or new API is needed for this increment. A further provider should be evaluated
only against measured missing products and permitted access/reuse.

Restart the API (or let its watch process reload), then choose Computers ->
Logitech/Dell, or Gaming -> Sony. Models load a first page; type a model name to
search beyond it. Existing listings and manual values are retained. Rollback
can restore the previous two strategy rows/provider implementation without a
database migration or deleting cache rows. Never reset unrelated work.

Suggested commit message:

```text
fix(catalog): validate peripheral identities with structured Wikidata relations

- cover mice, keyboards, monitors and controllers within existing subcategories
- add reviewed fallback identities with per-model sources and product types
- preserve canonical IDs, MongoDB cache, manual entry and endpoint contracts
- reject incompatible category pairs and unverified generic device cache results
- test provider failures, matching, cache reuse and responsive product selection
- document live source results, timeout limitations and pricing isolation
```
