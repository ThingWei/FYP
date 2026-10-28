# Automatic rental-price sources — implementation result

Current implementation: [source cleanup and automated evidence review](PRICING_SOURCE_CLEANUP_AND_READINESS_RESULT.md).
iRent, RentSmart, 12RENT, Goritta and AVM are removed. The older onboarding notes
below are historical; do not use them to re-enable those sources.

27 October later checks: [iRent/ITPA/12RENT diagnostics and evidence evaluation](PRICING_EVIDENCE_FOLLOWUP_RESULT.md).
No collection settings changed; access/parser success and reuse clearance remain separate.

27 October follow-up: [independent evidence and reuse-review audit](AI_PRICING_REAL_WORLD_EVIDENCE_RESULT.md)
adds a read-only review preview and an unregistered camping-page research parser.
No source was enabled, no new quotes were imported, and the cleared preview is
empty because explicit reuse-review evidence was not supplied. Existing adapter
enablement, technical quote eligibility and reuse clearance remain separate.

24 October onboarding preparation: [Goritta tent parser and strict permission gate](GORITTA_PRICE_SOURCE_ONBOARDING_RESULT.md).
There are now 16 registered sources; Goritta is not enabled and adds no live
observations yet. Its four-day quote parser was tested offline. Books still lack
reliable accessible product-price evidence; scooter model association is unresolved.

24 October coverage audit: [334 observations, 16/22 subcategories and collection priorities](PRICE_EVIDENCE_GAP_AUDIT_RESULT.md).
New Sports/Books/mobility-source research leads are not approved/enabled adapters.
No new source data was imported. Use `npm.cmd run audit:price-coverage` for a fresh,
bounded, read-only aggregate audit rather than assuming configured coverage is data.

24 October: [low-cost book quote support](LOW_COST_BOOK_PRICING_AND_DRAFT_RESULT.md)
retains original multi-day amounts and periods. No book source was added or
enabled, and no live data was imported.

23 October foundation: [all-category matching and measured coverage report](PRICING_CATEGORY_FOUNDATION_RESULT.md).
The 15 source registrations and permission gates remain unchanged. Admin source
status now reports actual eligible reference counts separately from configured
category mappings. All 22 types have software strategies, not a claim of complete
source availability. No source was enabled, fetched or imported in this change.

21 October recheck: [AI validation/readiness handoff](AI_VALIDATION_AND_DEMO_READINESS_RESULT.md).
iRent still yields six bounded quotes but is not permission-approved/enabled here;
12RENT remains access-restricted; RentSmart's three allowlisted pages have not
established a usable structured price catalogue. No source was enabled or imported.

Initially implemented on 12 October 2026; source follow-up on 20 October 2026 below. Product identities are separate from
price observations. These are **advertised asking prices**, not completed RentHub
transactions and not a promise of current availability or a guaranteed market price.

## What runs automatically

The registry (`priceSources.registry.js`) defines all 22 current physical domains,
allowlisted pages, adapter IDs and explicit gaps. Source-specific parsers normalize
quotes into the existing `pricing_references` collection. A separate `pricing_sources`
collection holds enablement, access-check metadata, health, next run and MongoDB leases.
No catalogue/provider, price source or scheduler change adds a new listing category.

The API checks due sources once a minute; each successful source is due again after
24 hours. A ten-minute atomic MongoDB lease prevents overlapping workers, including
different API processes. A crashed lease expires. Fetches are sequential, capped at
20 pages/500 observations, 2 MB/page, 15 seconds/request and five minutes/collection.
Discovery is confined to DRIVOR's allowlisted vehicle paths and the reviewed
iRent/12RENT product paths from category pages. Requests cannot follow
redirects, arbitrary links, query URLs or administrator-supplied URLs. Robots restrictions
are checked every collection, including discovered pages. A confirmed robots HTTP
404/410 means no published robots policy, not denied access or reuse permission;
maintainer approval remains required. Access denials, rate limits, redirects, server
failures, HTML challenges and timeouts still stop collection. Discovered pages have
a one-second inter-request delay.

Failure backs off 1, 2, 4, 8, 16, then 24 hours. A failed/empty collection does not
replace previous quotes or advance their observation date/last-success date. Successful
collections update only accepted observations. Missing products are not falsely refreshed.
The existing 365-day pricing-evidence window still applies. A manual refresh is explicit
and can bypass the next scheduled due time, but never an active lease or disabled source.

## Actual availability and coverage

Read-only public-page/parser probes made **no MongoDB writes**. Counts below are
observations/duration bands, not transactions or distinct products, and may change
when publishers update pages. `Parser usable` does **not** establish reuse permission.
All sources remain disabled by default pending the one-time access/reuse review.

| Category | Specific category | Source / current result | Fallback / test |
| --- | --- | --- | --- |
| Devices | Smartphones | [RENTISM](https://www.rentism.com.my/price-list/) parser usable; [iRent](https://irent.my/product-category/smartphone-rental/) explicit product-tier parser usable: 6 duration bands across 2 models in the 20 October read-only probe | RentHub/estimate/manual; coverage + smartphone/tier fixtures passed |
| Devices | Cameras | RENTISM parser usable; camera bodies/lenses remain different product types | RentHub/estimate/manual; coverage + camera fixture passed |
| Devices | Computers | [ITPA](https://itpa.my/pc-rental.php) usable: 3 quotes; [RentSmart electronics](https://rentsmartasia.com/product-category/rent-equipment/electronics/) pending | RentHub/estimate/manual; coverage + laptop fixture passed |
| Devices | Audio | RENTISM microphone quotes usable; RentSmart pending | RentHub/estimate/manual; coverage + microphone fixture passed |
| Devices | Gaming | [Cilt Tech](https://cilttech.com/ms/sewaan) usable: 6 period-specific console quotes; RentSmart pending | RentHub/estimate/manual; coverage + console fixture passed |
| Devices | Other devices | RENTISM identifiable walkie-talkie/video-capture quotes usable | RentHub/estimate/manual; coverage + walkie-talkie fixture passed |
| Vehicles | Cars | [DRIVOR](https://drivor.my/vehicle/toyota-camry/) usable: 70 duration-band observations over bounded 20-page discovery | RentHub/estimate/manual; coverage + car/band fixture passed |
| Vehicles | Motorcycles | [Alquiler Motorbike published catalogue](https://alquilermotorbike.com/llms.txt) usable: 15 daily quotes; no private/disallowed APIs | RentHub/estimate/manual; coverage + motorcycle fixture passed |
| Vehicles | Bicycles | [Ecocana Sports](https://ecocanasports.com/rent) usable: 10 explicitly daily-rental bicycle quotes | RentHub/estimate/manual; coverage + bicycle fixture passed |
| Vehicles | Other vehicles | [RentSmart scooters](https://rentsmartasia.com/product-category/rent-vehicles-vessels/scooters/) adapter pending: retrieval/currency/period not validated | RentHub/estimate/manual; registry + unavailable fallback tested |
| Equipment | Event equipment | [The Rental Guy](https://therentalguy.com.my/av-solution/) usable: 7 specification quotes, one unsupported type excluded; [PC Rent](https://www.pcrent.com.my/home/rental_rates) usable: 3 specification-only daily projector quotes after missing-robots handling fix | RentHub/estimate/manual; coverage + projector/type fixtures passed |
| Equipment | Tools | [JomRentPro](https://jomrentpro.com/) cordless-drill quote usable; [12RENT](https://toolrent.instantestore.com/cat-power-tools.cfm) labelled lease/minimum-period parser implemented, but current malformed robots response blocks collection | RentHub/estimate/manual; coverage + labelled drill/period fixtures passed |
| Equipment | Sports equipment | [RentSmart sports](https://rentsmartasia.com/product-category/rentals/sports/) adapter pending; no automatic quotes currently accepted | RentHub/estimate/manual; registry + unavailable fallback tested |
| Equipment | Other equipment | JomRentPro cleaning-equipment quotes usable; total 6 accepted across cleaning/tools, one unknown type excluded | RentHub/estimate/manual; coverage + washer fixture passed |
| Books | Textbooks | No verified Malaysian per-title rental source | RentHub/estimate/manual; no-source strategy tested |
| Books | Reference books | No verified Malaysian per-title rental source | RentHub/estimate/manual; no-source strategy tested |
| Books | Fiction | No verified Malaysian per-title rental source | RentHub/estimate/manual; no-source strategy tested |
| Books | Other books | No verified Malaysian per-title rental source | RentHub/estimate/manual; no-source strategy tested |
| Clothing | Formal wear | [Partymix](https://partymix.com.my/product-tag/men/) usable, explicit four-day garment rentals | RentHub/estimate/manual; coverage + blazer fixture passed |
| Clothing | Costumes | Partymix usable; unbranded titles retained without fabricated maker | RentHub/estimate/manual; coverage + costume fixture passed |
| Clothing | Traditional wear | Partymix usable; 7 accepted across three clothing domains over two allowlisted pages | RentHub/estimate/manual; coverage + Hanfu fixture passed |
| Clothing | Other clothing | [Futago Winter](https://futago.twinsjapantrading.com.my/) usable: one broad 10-day per-garment quote | RentHub/estimate/manual; coverage + package fixture passed |

RENTISM's probe accepted 200 observations across its five domains. This is deliberately
incomplete coverage, not every advertised product: ambiguous lines, accessories and
unsupported types are excluded. DRIVOR's car parser excludes clearly labelled
vans/buses/trucks/MPVs rather than quietly assigning them to Cars. Its discovery is
bounded, not a complete fleet import. [AVMProjector](https://www.avmprojector.com/rental)
is an optional disabled candidate with no adapter, not a dependency.

## Quote validation and matching

- Explicit RM/MYR amount and period required. Reject headline minimums, retail
  consumables, mixed sale/rental offers, conflicting same-product quotes, unknown
  periods, unsupported types and inseparable service bundles. No exchange-rate guesses.
- Prices have at most two monetary decimals; periods/bands are whole days 1–365;
  daily equivalent respects existing RM 1–1,000,000 limits. Non-finite values fail.
- A four-day garment package remains an amount **for four days**; its normalized
  daily equivalent is a feature, not a claim of an advertised one-day tariff.
  Vehicle band quotes retain minimum/maximum days and only match compatible requested
  duration. One source product contributes once even if compatible bands overlap.
- Specification-only projectors/TVs/sound sets retain specifications in their titles
  and package notes. Tax and separately quoted delivery/setup are disclosed. They
  never acquire invented brands, reviewer identities or catalogue IDs, and cannot
  count as exact-product/same-brand evidence. A projector cannot price a PA system;
  a camera lens cannot price a camera body.
- Named products resolve exact IDs only against the local curated catalogue/cache;
  no fuzzy ID is fabricated. Unmatched names remain text. No manufacturer API calls.
- Automated rows use `sourceType=external_asking_price`, `collectionMethod=automatic`,
  `sourceId`, stable product/band keys, parser version, `validationStatus=accepted`
  and `validatedAt`. `observedAt` is the successful collection time, **not** a fabricated
  publication date. `reviewedBy/reviewedAt` are absent on automatic rows.
- Stable source/product/type/band keys deduplicate refreshes even as amounts change.
  Existing `active=false`/administrator deactivation fields are never reset. Source
  disablement excludes all its automatic observations immediately; legacy reviewed
  CSV observations keep their existing contract. Failures preserve previous valid data.

Pricing still follows RentHub's existing evidence hierarchy, fitted features, XGBoost
and statistical fallback. External references join asking-price evidence only, within
the requested category/subcategory and product type. Metadata separates platform
listings, automatic asking references, reviewed asking references and completed rentals.
No booking/history mutation, price rule, training run or external ingestion occurred
against the live database during this implementation.

## One-time onboarding and day-to-day use

1. Check the publisher's current access/reuse terms and obtain permission where
   necessary. Public visibility and an allowing robots file alone are not permission.
2. Run the read-only diagnostic from `services/api`:

   ```powershell
   npm.cmd run inspect:price-sources
   npm.cmd run inspect:price-sources -- rental-guy
   ```

3. After that review, list **only approved adapter IDs** in your API `.env`, then
   restart the API. No real `.env` values were modified by this implementation.

   ```dotenv
   PRICE_SYNC_JOBS_ENABLED=true
   PRICE_SYNC_APPROVED_SOURCES=rentism,itpa,cilt,drivor,alquiler,ecocana,rental-guy,jomrent,partymix,futago
   ```

   This is an example, **not a permission recommendation**. PC Rent (`pc-rent`) may
   also be included after access/reuse review; its missing robots file no longer
   incorrectly blocks the accessible price page. Do not add pending adapters until
   implemented and validated.
4. Administrator → Listings → Rental-price references → Sources → **Enable source**.
   Enabling performs a fresh read-only access/parser probe and writes only source
   configuration/audit metadata. Due jobs then collect; **Sync now** explicitly queues
   a background refresh. Source health shows availability, last success, counts and
   safe failure messages. No CSV work is needed for approved automatic sources.
5. Disable a problematic source or deactivate an individual incorrect reference.
   CSV selection, blank template, preparation guide, preview and reviewed confirmation
   remain under **Advanced / manual import**. They are not scheduled or auto-replayed.

Admin-only endpoints (existing authentication/authorization preserved):

| Method | Endpoint | Behaviour |
| --- | --- | --- |
| GET | `/api/v1/admin/pricing-references/sources` | Read-only status, coverage and future candidates |
| PATCH | `/api/v1/admin/pricing-references/sources/:id` | `{enabled: boolean, confirmed: true}`; access review/probe before enable |
| POST | `/api/v1/admin/pricing-references/sources/:id/sync` | `{confirmed: true}`; 202 background job, 409 busy/disabled |

## Future Toys & Entertainment — not enabled

| Candidate | Limitation |
| --- | --- |
| [PleyLore](https://pleylore.com/plan) | Subscription/credit plans are not individual toy daily rental evidence |
| [FnD Mindspot](https://www.fndmindspot.com/game-rental) | Specific game, amount, rental period and package need verification |
| [Carnival Games Rental — Giant Chess](https://www.carnivalgamesrental.my/product/giant-chess) | Delivery/setup/crew packages excluded unless equipment costs can be separated |

Gaming consoles remain Devices → Gaming. Future toy categories require explicit
approval and coordinated taxonomy, UI/API, catalogue, product-type and pricing-model
support. The current registry does not automatically inherit pricing for unseen domains.

## Verification and remaining work

- Relevant API tests: **92 passed**. Tests cover all
  22 strategy entries, every implemented parser, fees/periods/bands, type guards,
  conflicts, auth, leases, deactivation, backoff, stale evidence and inference metadata.
- Full Flutter tests: **220 passed, 3 skipped**. Focused source/CSV tests: **29 passed**;
  widths 360/390/1024/1440 and 1.3–1.4 text scaling, keyboard navigation, failure recovery,
  explicit confirmation, no automatic write retry and malformed status responses.
  Repaired the off-screen CSV confirmation test with real scroll gestures.
- Changed Flutter files: analyzer clean. Full analyzer still reports two **existing,
  unrelated** named-parameter errors at `test/auth0_persistence_test.dart:41/43`
  (`latestLinkProvider`, `mobileLinkPollInterval`); Auth0 was deliberately untouched.
- Relevant AI tests: **26 passed**, two existing dependency deprecation warnings.
  Flutter Web build passed; existing socket.io WebAssembly dry-run and Cupertino-font
  warnings remain. The ordinary web build is successful; no Wasm claim is made.
- Source-control screenshots inspected at 360/390/1024px; tests cover
  larger text. Native file dialogs and publisher permission are not established by
  widget tests. Live source enablement/import was deliberately not performed.

Pending RentSmart/iRent/12RENT adapters, Books sources, individual
product coverage, ambiguous offers and predominantly synthetic model training remain
limitations. Source maintenance is still needed when pages change. More asking prices
do not prove achieved prices or resolve insufficient real completed-rental evidence.

## 12 October 2026: PC Rent enablement and local feedback fix

PC Rent's public price page returned HTTP 200, while its robots file returned HTTP
404. Previously any non-2xx robots response aborted the enable probe. The transport
now treats **only confirmed 404/410 robots responses** as an absent policy, consistent
with [RFC 9309 unavailable-status handling](https://www.rfc-editor.org/rfc/rfc9309.html#section-2.3.1.3),
with stricter handling retained for denials and operational failures. This exception
does not apply to price pages, bypass URLs or replace the maintainer review gate.

A fresh read-only probe accepted **3** projector observations (2200/2700/3500 ANSI
lumens), with **0 database writes**. These remain specification-level comparisons,
not named-model or manufacturer matches. No live source was enabled or imported.

Source actions now show progress, success and safe errors immediately above their
own buttons, rather than only at the top of a long list. Enable failures retain a
safe diagnostic code; raw exceptions/URLs remain hidden. Controls recover after
failure and retries are explicit. Unfinished adapters (iRent, RentSmart, 12RENT and
optional AVM) remain unavailable; approval settings cannot create a missing parser.

To use the fix, restart the actual API process and relaunch RentHub using
`run-renthub.ps1 -Admin`, then refresh source status and explicitly enable PC Rent.
The launcher may reuse an already-running API: closing a launcher that reused it
does not stop that older API. Avoid starting a second API on port 3000.

Focused verification: **97 API tests passed**, **31 Flutter source/CSV tests passed**;
changed Flutter files passed analysis. Missing robots, explicit restrictions,
price-page failures, permission gates, no-write enable probes and source-local
progress/error/retry in a long list at mobile width have regression coverage.
Final Flutter Web build passed (existing socket.io Wasm dry-run warning). Source-local
failure layouts were inspected at 360/390/1024px. Full analysis still reports only
the two unrelated Auth0 test named-parameter errors documented above.

## 20 October 2026: adapter completion and current blockers

See [Auth0/source/lifecycle handoff](AUTH0_SOURCES_AND_LIFECYCLE_RESULT.md) for
current probes, exact source semantics, setup and test results. This section
supersedes historical pending-adapter/analyzer statements above.

iRent now yields six explicit product/duration-band quotes in a bounded seven-page
read-only probe. Headline minimums and ambiguous yearly tiers are excluded. 12RENT's
lease-field parser is implemented, but an HTTP-200 robots response containing
unrendered template markup blocks automatic collection. RentSmart's directly
retrieved old/current public category pages are empty; it remains unavailable,
and search-index excerpts are not imported. Unsupported-source diagnostics are
now explicit rather than silent. No live source was enabled or imported.

Flutter analysis is now clean after matching Auth0 constructor signatures. Full
verification: API 389 passed/3 skipped; AI 482 passed; Flutter 407 passed/3 skipped;
Web and Android debug builds passed. Existing Wasm/Kotlin warnings remain.
