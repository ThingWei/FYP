# RentHub product catalog coverage result

Date: 4 October 2026

## Architecture

```text
Flutter Owner listing form
  -> existing authenticated RentHub Express catalog API
  -> category/subcategory coverage resolver
  -> ordered provider chain
  -> common RentHub brand/model schema
  -> MongoDB product_catalog cache
  -> explicit manual-entry fallback
```

Flutter does not call NHTSA, Wikidata, Open Library, or a manufacturer API.
External and curated results use the same response fields:
`entityType`, `brand`, `model`, `catalogBrandId`, `canonicalProductId`,
`catalogSource`, `description`, `aliases`, and optional `specifications`.

The executable matrix is in
`services/api/src/modules/catalog/catalog.coverage.js`. Curated identity data is
in `catalog.curated.js`. Curated records contain identity metadata only; no
rental price or pricing adjustment is stored there.

## Coverage matrix

| Category | Subcategory | Primary source | Ordered fallback | Verified example |
| --- | --- | --- | --- | --- |
| Devices | Smartphones | Structured Wikidata smartphone graph | RentHub curated -> validated Wikidata -> manual | Apple -> iPhone 15 Pro |
| Devices | Cameras | RentHub curated | validated Wikidata -> manual | Canon -> EOS R6 Mark II |
| Devices | Computers | RentHub curated | validated Wikidata -> manual | Dell -> XPS 13 |
| Devices | Audio | RentHub curated | validated Wikidata -> manual | JBL -> Charge 5; Sony -> WH-1000XM5 |
| Devices | Gaming | RentHub curated | validated Wikidata -> manual | Nintendo -> Switch OLED |
| Devices | Other devices | RentHub curated | validated Wikidata -> manual | Garmin -> Instinct 2 |
| Vehicles | Cars | NHTSA vPIC | RentHub curated -> validated Wikidata -> manual | Toyota -> Camry |
| Vehicles | Motorcycles | NHTSA vPIC motorcycle makes | RentHub curated -> validated Wikidata -> manual | Yamaha -> Y15ZR |
| Vehicles | Bicycles | RentHub curated | validated Wikidata -> manual | Giant -> Talon 2 |
| Vehicles | Other vehicles | RentHub curated | validated Wikidata -> manual | Segway -> Ninebot Max G2 |
| Equipment | Event equipment | RentHub curated | validated Wikidata -> manual | Yamaha -> MG10XU |
| Equipment | Tools | RentHub curated | validated Wikidata -> manual | Bosch -> GSB 18V-50 |
| Equipment | Sports equipment | RentHub curated | validated Wikidata -> manual | Wilson -> Pro Staff 97 |
| Equipment | Other equipment | RentHub curated | validated Wikidata -> manual | Karcher/Kärcher -> K2 Power Control |
| Books | Textbooks | Open Library author/works | RentHub curated -> validated Wikidata -> manual | James Stewart -> Calculus |
| Books | Reference books | Open Library author/works | RentHub curated -> validated Wikidata -> manual | DK -> Knowledge Encyclopedia |
| Books | Fiction | Open Library author/works | RentHub curated -> validated Wikidata -> manual | J. R. R. Tolkien -> The Lord of the Rings |
| Books | Other books | Open Library author/works | RentHub curated -> validated Wikidata -> manual | Lonely Planet -> Malaysia |
| Clothing | Formal wear | RentHub curated | validated Wikidata -> manual | Padini -> Slim Fit Two-Piece Suit |
| Clothing | Costumes | RentHub curated | validated Wikidata -> manual | Rubie's -> Darth Vader Costume |
| Clothing | Traditional wear | RentHub curated | validated Wikidata -> manual | Jakel -> Baju Melayu Modern |
| Clothing | Other clothing | RentHub curated | validated Wikidata -> manual | Uniqlo -> Ultra Light Down Jacket |

Unknown future subcategories receive `validated Wikidata -> manual-entry` until
they are deliberately added to the matrix.

## Provider behavior

### Structured sources

- NHTSA vPIC brand results come from the requested vehicle type. Car and
  motorcycle searches keep separate in-memory provider caches. Models are
  requested using the selected canonical make ID.
- Smartphone brands are not generic text matches. A brand must manufacture an
  entity classified as a smartphone model, smartphone model series, or mobile
  phone series. Models must use both an allowed smartphone class and the
  selected canonical manufacturer ID.
- Open Library resolves a canonical author first and then retrieves works using
  that author ID.

### Curated fallback

The curated catalog guarantees at least one reviewed brand and two model
identities for every current specific-category dropdown value. It is intentionally
small and version-controlled. It is not a claim of complete worldwide product
coverage and is not a price dataset.

### Validated Wikidata fallback

Generic Wikidata results are discarded unless their label/description contains
the requested product-domain terms and an appropriate brand or product entity
marker. This favors a safe no-match/manual flow over showing journals, software,
places, or similarly named unrelated entities.

### Failure and manual entry

Provider chains continue after a provider error or zero-result response. If an
external provider is offline but a curated match exists, the curated match is
returned. If no provider has a useful identity, Flutter keeps manual entry
available. A provider outage therefore never prevents saving a manual listing.

## MongoDB caching

All successful provider results are normalized before being upserted into
`product_catalog`. Cache identity includes source, provider entity ID, entity
type, category, and subcategory. Cache lookup is restricted to sources declared
by that subcategory's provider chain, preventing an old generic cache record from
overriding a domain-specific source.

Model search supports an empty query after brand selection, so Flutter can load
an initial model page immediately. Typed searches still use debounced filtering.

## Pricing isolation

No provider and no curated record supplies rental prices. Catalog identity is
used only to improve comparable matching. Pricing remains:

```text
MongoDB completed rentals / active comparables
  -> renthub-price-v2 request
  -> trained XGBoost artifact
  -> calibrated suggestion and confidence
```

## Test results

The automated matrix test iterates all 22 current subcategories. For each row it
verifies that a representative brand is searchable, a model page can be loaded
after brand selection, normalized specifications identify curated provenance,
and the code/documentation matrix has no uncovered dropdown value.

Additional regressions verify:

- `Devices -> Smartphones -> appl` excludes journal/software results;
- `Devices -> Audio -> JBL` retrieves Charge, Flip, and PartyBox products;
- Apple retrieves iPhone models through the selected manufacturer ID;
- Toyota retrieves Camry and Corolla through NHTSA vPIC;
- external failure falls through to the curated catalog;
- query-less model preloading works through the Express API;
- provider failures, no-match, and match-found remain distinct UI states;
- MongoDB caching and server-side canonical identity verification remain active.

Final verification:

- Express/API: 105 passed, 3 optional E2E tests skipped;
- live Toyota and Apple provider E2E: 2 passed;
- Flutter: 91 passed, 2 intentionally skipped;
- Flutter analyzer: no issues;
- FastAPI/AI: 16 passed;
- OpenAPI YAML: parsed successfully.

See `docs/AI_PRICING_PRODUCT_CATALOG_RESULT.md` for the pricing evidence,
completed-rental cold start, and item-age sensitivity audit.

## Known limitations

- The curated catalog is representative, not exhaustive. Owners may still need
  manual entry for local, new, rare, edition-specific, size, or storage variants.
- NHTSA vPIC is US-oriented and may omit Malaysia-only vehicle models.
- Open Library works are author-centric; publisher and exact edition coverage is
  incomplete.
- Wikidata classification completeness varies, especially for newly released
  devices.
- Curated updates currently require a reviewed code/data change; there is no
  administrator catalog editor yet.
- Product identity improves evidence matching but does not solve the lack of real
  completed-rental history.
