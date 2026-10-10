# RentHub product catalog coverage result

## 10 October 2026: searchable selection and expanded starter identities

Brand opens a searchable sheet with an initial list. Choosing a brand immediately
opens a model sheet with its first page. Books display **Author/publisher** and
**Title/edition**. Search needs two characters; browsing needs none. The sheets
always offer manual entry, including during loading, empty results and outages.
Manual/catalogue switches preserve text but clear obsolete product IDs and price
estimates. Saved selections remain visible even if absent from the current page.
Request versions and identity/context snapshots discard stale results.

### Current coverage and representative test matrix

Every row below passes query-less brand browsing (at least three brands/authors)
and one matching model-page regression. There are at least two distinct named
products/titles **per subcategory**, not necessarily for every brand. Brand-only
apparel entries deliberately offer manual garment names rather than invented SKUs.

| Category | Subcategory | Starter brands/authors | Tested brand → product/title | Provider | Test |
| --- | --- | --- | --- | --- | --- |
| Devices | Smartphones | Apple, Samsung, Google | Apple → iPhone 15 Pro | smartphone graph + curated | PASS |
| Devices | Cameras | Canon, Sony, Nikon | Canon → EOS R6 Mark II | curated | PASS |
| Devices | Computers | Dell, Apple, Lenovo | Dell → XPS 13 | curated | PASS |
| Devices | Audio | Sony, JBL, Bose | Sony → WH-1000XM5 | curated | PASS |
| Devices | Gaming | Nintendo, Sony, Microsoft | Nintendo → Switch OLED | curated | PASS |
| Devices | Other devices | Garmin, Apple, Samsung | Garmin → Instinct 2 | curated | PASS |
| Vehicles | Cars | Toyota, Perodua, Proton | Toyota → Camry | vPIC + curated | PASS |
| Vehicles | Motorcycles | Yamaha, Honda, Kawasaki | Yamaha → Y15ZR | vPIC + curated | PASS |
| Vehicles | Bicycles | Giant, Trek, Specialized | Giant → Talon 2 | curated | PASS |
| Vehicles | Other vehicles | Segway, Xiaomi, Razor | Segway → Ninebot Max G2 | curated | PASS |
| Equipment | Event equipment | Yamaha, Epson, BenQ | Yamaha → MG10XU | curated | PASS |
| Equipment | Tools | Bosch, Makita, DeWalt | Bosch → GSB 18V-50 | curated | PASS |
| Equipment | Sports equipment | Wilson, Yonex, Head | Wilson → Pro Staff 97 | curated | PASS |
| Equipment | Other equipment | Karcher, Dyson, Nilfisk | Karcher → K2 Power Control | curated | PASS |
| Books | Textbooks | James Stewart, OpenStax, David Halliday | James Stewart → Calculus | Open Library + curated | PASS |
| Books | Reference books | DK, Oxford University Press, Merriam-Webster | DK → Knowledge Encyclopedia | Open Library + curated | PASS |
| Books | Fiction | J. R. R. Tolkien, J. K. Rowling, Agatha Christie | Tolkien → The Lord of the Rings | Open Library + curated | PASS |
| Books | Other books | Lonely Planet, Rick Steves, DK | Lonely Planet → Malaysia | Open Library + curated | PASS |
| Clothing | Formal wear | Padini, Hugo Boss, Uniqlo | Hugo Boss → Huge/Genius Suit | curated | PASS |
| Clothing | Costumes | Rubie's, Disguise, Smiffys | Rubie's → Wicked Witch Deluxe Adult Costume | curated | PASS |
| Clothing | Traditional wear | Jakel, Ariani, Rizman Ruzaini | Ariani → Afshin Baju Kurung | curated | PASS |
| Clothing | Other clothing | Uniqlo, The North Face, Columbia | Uniqlo → Ultra Light Down Jacket | curated | PASS |

All rows additionally use valid MongoDB cache, validated Wikidata on non-empty
search when no useful domain results exist, and unconditional manual fallback.
No manufacturer-specific API was added. Identity source links are stored on
every curated row in `catalog.curated.js` and normalized into
`specifications.identitySourceUrl`. These are manufacturer/publisher product or
collection pages, not rental-price sources. Some older product families may
require archived documentation or manual variant/edition entry.

### Provider, merge and identity rules

- Curated entries supplement structured providers, rather than being discarded
  after the first provider succeeds. Fresh/stale valid cache is merged too.
- Equivalent labels/aliases are deduplicated in category/subcategory context;
  a returned structured entry retains its actual provider ID. Model equivalence
  also removes redundant leading brand names. This is not global SKU resolution.
- Empty-query browsing never launches unrestricted generic Wikidata text search.
  Cars/motorcycles can browse typed vPIC makes; smartphones use the existing
  classified manufacturer graph. Books initially use curated/cache identities.
- vPIC model queries include vehicle type, including when resolving a curated
  make label to a provider ID. This avoids motorcycle/car cross-contamination.
  Type-only model queries are documented by [NHTSA vPIC](https://vpic.nhtsa.dot.gov/api/).
- Smartphone graph models require the selected manufacturer and smartphone class.
  Open Library authors/works now require relevant subcategory subjects or a known
  curated title. A curated author ID can resolve to the corresponding provider ID.
- General Wikidata fallback and its cache require **subcategory** semantics, not
  just broad category text. Underclassified legitimate products can be omitted.
- Legacy generic apparel style names were removed from starter suggestions.
  Existing saved listings are not migrated or deleted. Named examples include
  [Hugo Boss Huge/Genius](https://www.hugoboss.com/us/virgin-wool-suit-slim-fit-huge%2Fgenius/hbna50275643_021.html),
  [Uniqlo AirSense](https://www.uniqlo.com/my/en/special-feature/airsense/women),
  [Disguise costumes](https://disguise.com/brand/mario.html), and
  [Ariani collections](https://www.arianionline.my/).

### Price evidence remains independent

Curated identities contain no price rules. Separately reviewed CSV observations
live in `pricing_references`, never `bookings` or `product_catalog` prices.
See [pricing result](AI_PRICING_PRODUCT_CATALOG_RESULT.md) for import instructions,
provenance and inference limits. More identity choices do not imply more
completed rentals or a validated product-specific price.

### Current verification and remaining limits

- Relevant API suite: 56 passed, one optional live-AI E2E skipped.
- Flutter full suite: 203 passed, three skipped; new picker/import UI suite:
  12 passed, including 360/390 px picker, 390/1024/1440 px admin and larger text.
- AI pricing suite: 16 passed. Flutter web build passed.
- Targeted Flutter analysis is clean. Full analysis retains two unrelated existing
  Auth0 test named-parameter errors in `test/auth0_persistence_test.dart`
  (`latestLinkProvider`, `mobileLinkPollInterval`).
- Provider tests use controlled fixtures, not a guarantee that every external
  provider is currently online. Public rental source pages were checked separately.
- Full catalogue coverage means a reviewed starter strategy for all 22 domains,
  not every Malaysian brand, variant, size or edition. Manual entry stays essential.
- Native Android/iOS file picking was not device-tested; administrator CSV selection
  was verified with Tab/Enter and generated mobile/desktop previews were inspected;
  the selection/import logic and responsive layout have automated widget coverage.
- No existing uncommitted work, live database history or Auth0 configuration was
  reset. No production dependency, retraining or automated scraping was added.

## Earlier implementation details

Historical baseline: 4 October 2026 (verification figures below belong to that earlier implementation).

## Architecture

```text
Flutter Owner listing form
  -> existing authenticated RentHub Express catalog API
  -> category/subcategory coverage resolver
  -> merged provider/curated/cache strategy
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
| Clothing | Formal wear | RentHub curated | validated Wikidata -> manual | Hugo Boss -> Huge/Genius Suit; Uniqlo -> AirSense Jacket |
| Clothing | Costumes | RentHub curated | validated Wikidata -> manual | Disguise -> Luigi Classic Adult |
| Clothing | Traditional wear | RentHub curated | validated Wikidata -> manual | Ariani -> Afshin Baju Kurung |
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

The curated catalog guarantees at least three reviewed brands/authors and two named product/title
examples per subcategory for every current specific-category dropdown value. It is intentionally
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
MongoDB completed rentals / active comparables / reviewed asking-price references
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
