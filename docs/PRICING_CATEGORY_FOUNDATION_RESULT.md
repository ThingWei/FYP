# All-category pricing foundation — first-stage implementation

24 October follow-up: [low-cost Books and unfinished drafts](LOW_COST_BOOK_PRICING_AND_DRAFT_RESULT.md).
The RM1 Book limitation recorded below is superseded by RM0.01 physical-book
support; source availability and real-market validation gaps remain unchanged.

23 October 2026. **This delivers software support, not complete real-world price
coverage or validated accuracy across all 22 subcategories.** No sources were
removed, added, fetched or enabled. No live records, accounts, bookings,
environment secrets or deployed models were changed. No invented prices/rentals.

## Delivered

- `priceProductDomains.js` defines semantic product types for all 22 existing
  physical subcategories. Invalid category pairs and unknown mixed-domain types
  fail closed. These are identity rules, not price/depreciation rules.
- Reviewed CSV and automatic external references now share type, edition,
  variant, package and duration compatibility checks. Seven-day packages do not
  become advertised one-day quotes. Automatic duration bands retain their bounds.
- Explicit edition/capacity/package conflicts are excluded. Missing corresponding
  details cannot count as exact-product evidence just because catalogue IDs match.
  Plain camera models can use body-only offers as broader comparisons; with-lens
  packages require corresponding package context.
- Books need matching author/publisher and normalized title or matching validated
  ISBN. Conflicting editions/subcategories are excluded. ISBN-10/13 checksum
  validation preserves leading zeros and normalizes equivalent identifiers.
  Edition text may also appear in the entered title.
- Manual refreshes of the same URL/product are deduplicated at inference:
  fragments/known tracking parameters are ignored, newest observation wins and
  equal-time conflicting prices are excluded. Stored records remain intact.
  This is not complete syndicated-offer/business identity resolution.
- Optional CSV/API fields: `isbn`, `edition`, `variant`, `packageType`. Existing
  CSV headers/omissions remain valid. New metadata is validated, participates in
  import-conflict checks and is shown in admin preview/listing. Preview is still
  read-only and import still requires confirmation.
- Physical listing forms have **Product details for price comparisons**. Books
  show optional ISBN/edition; other products show version/capacity and included
  package. Values persist through listing create/edit and enter pricing requests.
  Identity changes clear obsolete details; metadata edits invalidate old and
  in-flight suggestions. Services do not show these controls.
- Offline export/evaluation applies the same compatibility rules and carries
  metadata as provenance, not new fitted features. Deployed XGBoost artifacts,
  feature contract, training and existing model/fallback priority are unchanged.

## Admin report

Open **Administrator → Listings → Rental-price references → Price evidence by
category**. **Refresh source status** refreshes these counts too. The existing
admin-only `GET /api/v1/admin/pricing-references/sources` adds `coverageReport`;
existing source/configuration/control fields and endpoint paths remain intact.

The bounded, read-only scan checks the newest 10,000 references with a truncation
flag. Every category appears, including empty rows. Counts cover stored, eligible,
excluded and unclassified observations; distinct normalized URL/product offers;
source websites; product groups; named versus specification-only references;
state/unspecified-location and product-type counts; periods, freshness and known
condition/age. Reviewer identities/raw records are not returned in report output.

Automatic references require enabled, maintainer-approved sources. Existing
365-day, MYR, valid amount/duration, review/validation, active and non-service-bundle
rules are reused. The report does not create/count completed or demo rentals.

`no_eligible_references`, `limited_reference_offers`, `multiple_reference_offers`
are descriptive diagnostics. Three offers/two websites separates the latter two
labels only: **not an accuracy, independence, permission or release threshold**.
Website count is not verified independent-business count. Subcategory counts
cannot establish coverage of every model, region, package or duration. Accuracy
is explicitly `not_established_by_coverage_counts`.

## All-22 semantic coverage matrix

Each representative pair has a passing software/reference fixture test, not an
imported observation or real-market evaluation. Source mappings are unchanged.

| Category | Specific category | Representative identity | Supported types/boundary |
| --- | --- | --- | --- |
| Devices | Smartphones | Samsung Galaxy S24 | Smartphone; known storage/version conflicts |
| Devices | Cameras | Canon EOS R50 | Camera versus lens; body-only versus with-lens package |
| Devices | Computers | Dell XPS 13 | Laptop versus desktop |
| Devices | Audio | JBL Charge 5 | Speaker, microphone, headphones, mixer |
| Devices | Gaming | Sony DualSense controller | Controller versus console or VR headset |
| Devices | Other devices | Garmin Forerunner 265 | Watch, tablet, printer, walkie-talkie, video capture |
| Vehicles | Cars | Toyota Camry | Car domain |
| Vehicles | Motorcycles | Honda ADV160 | Motorcycle domain |
| Vehicles | Bicycles | Giant Talon 2 | Bicycle domain |
| Vehicles | Other vehicles | Segway Ninebot Max G2 | Electric scooter, mobility scooter, electric unicycle |
| Equipment | Event equipment | Yamaha MG10XU | Mixer, PA set, lighting, projector, TV, stand, canopy, table, chair |
| Equipment | Tools | Makita DHP484 drill | Drill, hammer, saw, ladder, sander, grinder |
| Equipment | Sports equipment | Four-person camping tent | Racket, tent, sleeping bag, golf clubs, kayak, paddleboard, life jacket, snorkel, selected fitness equipment |
| Equipment | Other equipment | Karcher WD 3 | Vacuum versus fabric cleaner or pressure washer |
| Books | Textbooks | Calculus / author | Title/author and ISBN/edition when supplied |
| Books | Reference books | DK Knowledge Encyclopedia | Separate subcategory and edition checks |
| Books | Fiction | Tolkien The Hobbit | No unrelated-title/publisher-wide price matching |
| Books | Other books | Lonely Planet Malaysia | Same title/author or validated ISBN |
| Clothing | Formal wear | Blazer | Formal jacket, suit, formal dress |
| Clothing | Costumes | Jedi costume | Costume domain |
| Clothing | Traditional wear | Baju Kurung | Malay traditional, hanfu, kurta, identified traditional costume |
| Clothing | Other clothing | Columbia Powder Lite jacket | Winter garment versus rainwear |

These bounded text rules are extensible, not exhaustive product knowledge. They
do not independently verify publisher category claims, every alias/specification,
garment fit/quality or accessory compatibility. Unknown types remain excluded
from external comparisons. Owner manual pricing remains available.

## Remaining data/accuracy gates

1. Retain current sources; review access/reuse and parser behaviour before any
   new source is enabled. Research leads are not accepted/imported observations.
2. All four Books subcategories still need current usable offers. Other vehicles
   and Sports equipment need validated additional sources. Earlier data counts
   remain historical; this implementation did not audit the live database.
3. **Existing RM1 minimum daily-price limits remain unchanged.** Book packages
   below that equivalent rate remain unsupported. Do not inflate amounts or
   shorten periods. Supporting them needs an explicit coordinated UI/API/model
   business-limit change, not a fabricated workaround.
4. Do not invent condition/age, fees or package details from release dates or
   convert subscriptions, buy-back arrangements, hourly sessions or retail prices
   into daily rentals. A multi-day average is not an advertised one-day rate.
5. Existing model/statistical priority is unchanged. A new comparable-first
   estimator, cohort-specific validation/thresholds and model deployment are not
   completed by this task. Independent time/group-aware tests against a baseline
   are still needed before changing model priority or claiming better accuracy.
6. Source independence, complete price-change history, correction/deletion
   obligations and region/model accuracy remain review work. Current model
   training is heavily synthetic/demo-based; no retraining here.

## Verification and handoff

- Full API: **448 passed, 3 optional skips** (451 total).
- Full Flutter: **435 passed, 3 existing skips**; full Dart analysis clean.
- Full AI: **542 passed**, with existing dependency deprecation and missing-cohort
  imputer warnings. These checks do not measure improved market accuracy.
- Web and Android debug builds passed. Existing nonfatal Socket.IO Wasm/font and
  Firebase/preferences Kotlin migration warnings remain.
- Regression coverage: all 22 pairs, ISBN/edition/Unicode, lens/kit/controller/
  capacity conflicts, explicit periods, refreshes/conflicts, stale/disabled data,
  bounded/truncated private-safe reporting, preview-without-writes, persisted
  metadata and unchanged completed history. Flutter covers 360/390/1024/1440
  widths with increased text, invalid ISBN/no request, empty daily price and
  superseded edition responses.
- API suites use temporary MongoDB, mock auth and disabled FCM/email/blockchain,
  not live `.env`. The initial default-claim run exposed an existing Auth0 test
  fixture/config mismatch; explicit fixture name/email claim namespaces resolved
  it. No Auth0 code or actual environment configuration was changed.
- Real-device/public-source permissions and real-market validation remain open.

Restart the API and relaunch Flutter with the normal launcher. No database
migration, new production dependency, automatic import or production deployment.
Existing unrelated work is preserved.

Commit message:

```text
feat(pricing): add all-category matching and evidence coverage diagnostics

- centralize semantic types across all 22 physical subcategories
- apply product, edition, variant, package and period guards to external references
- persist optional ISBN and comparison details in listings and pricing requests
- deduplicate manual refreshes and exclude equal-time conflicting quotes
- show bounded reference coverage without claiming validated accuracy
- share matching metadata with offline evaluation and add regression coverage
- preserve sources, model artifacts, rental history and manual pricing
```
