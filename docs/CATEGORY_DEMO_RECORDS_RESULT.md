# Category-complete demonstration listings

5 November 2026. Published **40 new labelled demo listings**, adding to the 24
existing demos. RentHub now has **64 active demo listings across two existing,
MyKad-approved Owners**, with at least two examples for every current physical
subcategory and two service packages. Existing records were retained.

| Category | Specific category | Active demos | Example products |
|---|---|---:|---|
| Devices | Smartphones | 4 | Samsung S23, S24 |
| Devices | Cameras | 12 | Canon 5D / R6 II; Sony A7 III |
| Devices | Computers | 7 | Dell laptops/monitor; Logitech mouse/keyboard |
| Devices | Audio | 2 | Sony WH-1000XM5; JBL Charge 5 |
| Devices | Gaming | 3 | PlayStation 5 Pro; DualSense controller |
| Devices | Other devices | 2 | Garmin Forerunner 265; Galaxy Tab S9 |
| Vehicles | Cars | 2 | Toyota Camry |
| Vehicles | Motorcycles | 2 | Yamaha NVX 155; Honda ADV160 |
| Vehicles | Bicycles | 2 | Giant Escape 3; Trek Marlin 5 |
| Vehicles | Other vehicles | 2 | Segway and Xiaomi scooters |
| Equipment | Event equipment | 2 | Epson projector; Yamaha portable sound system |
| Equipment | Tools | 2 | Bosch and Makita drills |
| Equipment | Sports equipment | 2 | Wilson tennis rackets |
| Equipment | Other equipment | 2 | Karcher vacuum and pressure washer |
| Books | Textbooks | 2 | Calculus; Precalculus |
| Books | Reference books | 2 | DK Knowledge Encyclopedia; The Science Book |
| Books | Fiction | 2 | The Hobbit; The Lord of the Rings |
| Books | Other books | 2 | Lonely Planet travel guides |
| Clothing | Formal wear | 2 | Unbranded suit and evening dress |
| Clothing | Costumes | 2 | Generic wizard and pirate costumes |
| Clothing | Traditional wear | 2 | Baju Melayu and Baju Kurung |
| Clothing | Other clothing | 2 | Uniqlo travel outerwear |
| Services | Existing package-based taxonomy | 2 | Event photography; online mathematics tutoring |

Services do not have a fixed specific-category dropdown in the current live
listing form. These examples use the existing package names and venue modes;
no new subcategory or Toys & Entertainment taxonomy was introduced.

## Data and presentation

- New physical records have sample condition/age, deposit, fulfilment and delivery
  details. Physical locations use the existing public Dataran Merdeka demo point,
  with normal approximate-location privacy. The online session has no physical pin.
- New images are original, code-rendered Material-icon illustration cards with a
  visible **DEMO / ILLUSTRATION** label. They are category graphics, not photographs
  of possessions, copyrighted book covers or item-verification evidence.
- The 40 new prices are explicitly fictional presentation values, not independently
  researched market quotations. They must not be described as real-world accuracy.
  The user's subsequent student-affordability concern requires a separate price
  audit, including the older commercially sourced demo prices.
  The subsequent [student demo price review](STUDENT_DEMO_PRICE_REVIEW_RESULT.md)
  corrected eight older camera entries using checked one-day quotes; the full
  student-price review remains incomplete.
- No account or identity approval was created/changed. No item verification,
  ratings, reviews, bookings, rentals, payments or achieved transaction prices
  were fabricated. Every new listing retains `sourceType = demo_seed` and is
  excluded from clean AI-pricing evidence.
- Original generated illustrations remain attached to the older 24 demos; no
  existing photographs or listings were overwritten by the coverage operation.

## Validation

- Five isolated manifest/schema checks passed: all 40 valid documents and assets,
  distinct Owners, complete domain union, physical/service separation, peripherals,
  stable identifiers and invalid-Owner rejection.
- Read-only preview validated the complete batch before database/storage writes.
- Applied: **40 listing inserts and 40 upload assets**; zero account, booking,
  rental or payment count changes. A repeat verification planned zero new writes.
- Public API verification loaded both pages, found every new listing and all 64
  demos, checked every domain, and downloaded/hash-verified all 40 new images.
  Services omitted physical-only fields and exact location details stayed private.
- The larger inventory exposed an existing unstable-sort bug in public Explore
  pagination: equal dates/prices/ratings could repeat or omit records across pages.
  Added an immutable `_id` tie-breaker while preserving each selected primary sort.
  A disposable-database regression failed before this fix and passed afterward.
- **44 listing/maps/privacy/pagination API tests passed**, using test/mock child
  settings and disposable databases. The first broader run inherited live Auth0
  mode and failed fixture authentication; rerunning with test-mode settings resolved
  it without modifying saved environment configuration or Auth0 behaviour.
- Eighteen demo/provenance/pagination checks also passed. No Dart/AI implementation
  changed for this task, so no new Flutter build or model training was required.

Private manifests, code-native card renderer, schema checks and receipts:
`services/api/.data/evidence/category-demo-coverage-2026-11-05/`.
Private image copies: `services/api/.data/demo-category-images-v1/`.
Both are Git-ignored; published images are in the configured shared storage.

Refresh Explore and use category filters to demonstrate the coverage. The older
categories have more than two records because their existing data was preserved.
Owners can rent the other account's examples; self-booking and normal renter
identity/driving requirements remain enforced.
