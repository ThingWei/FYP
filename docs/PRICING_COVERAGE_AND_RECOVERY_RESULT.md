# Pricing coverage and recovery

Implemented and audited on 9 November 2026. This covers all **22 current physical-item subcategories**, rather than speakers alone. Existing uncommitted UI changes were retained. No database records, source enablement settings or trained models were modified; no rental history or price observations were invented.

## What changed

1. **Completed demo rentals can support an explicitly separate FYP fallback.** Set `PRICING_EVIDENCE_MODE=demonstration` in the private API environment, then restart the API. This laptop has that non-secret setting configured. Other laptops need the same setting once. The default/example is `clean`; production rejects demonstration mode. The older development-only `PRICING_INCLUDE_DEMO_SEED` opt-in is also respected.
2. **Clean comparisons take precedence.** Compatible independent asking prices or clean completed rentals prevent simulated history from entering that prediction. Demo history has its own counts and cohort; it never becomes verified-payment history, earned real-world trust or clean training/evaluation data.
3. **A usable quote need not become a failure just because XGBoost is unavailable.** The existing statistical fallback remains. If it cannot produce a result, a single compatible observation or identical observations can provide a **Rental price guide** using the observed median. A single observation has no fabricated interval; multiple observations show their observed minimum/maximum. Confidence stays low. This guide is explicitly not a new model prediction or a validated market price. XGBoost still runs first; its artifact, feature order and inference route are unchanged.
4. **Exact named products no longer require a guessed type keyword.** Within the same category/subcategory, matching normalized brand and model can use a reference even if the model name has no recognizable item-type word. Different models cannot use that exception. Existing edition, capacity, package, period and reviewed-class constraints remain.
5. **Useful type distinctions were added.** Portable/general speakers remain separate from PA speakers and sound-system packages. Explicit wattage and RMS/peak standards must agree. Projector screens are separate from projectors; screen size remains constrained. The RENTISM parser can accept supported Audio types beyond microphones when explicit eligible quotes exist. These changes do not manufacture quotes absent from a publisher.
6. **Missing data is a normal guided state.** Owners see **Set your daily price**, a short explanation, relevant pricing tips and **Enter my price**, which focuses the existing price field. Missing-data states do not invite a pointless immediate retry. Temporary failures retain retry. No raw error or technical detail is displayed. Prices, photos, drafts and manual-entry behavior remain intact.

Source-specific parser versions changed to 4 for RENTISM and The Rental Guy. All other adapters retain their versions and existing access/collection gates. No new site, source URL or category was enabled.

## Current database findings

The bounded native MongoDB audit used read-only queries and wrote only a private aggregate report. It found **391 eligible external observations across 16 of 22 subcategories**. An observation can be another duration band of the same offer; this count is not a count of independent products, businesses or successful transactions. All active platform listings currently fail the separate clean-price eligibility policy; none was automatically relabelled or approved as independent evidence.

| Category | Specific category | Eligible external observations | Important missing product types |
|---|---|---:|---|
| Devices | Smartphones | 2 | Exact-model coverage remains limited |
| Devices | Cameras | 224 | Camera accessories, cinema cameras |
| Devices | Computers | 3 | Mice, keyboards, monitors, desktops |
| Devices | Audio | 8 | Speakers, PA speakers, headphones, mixers; existing quotes are microphones |
| Devices | Gaming | 6 | Controllers, VR headsets |
| Devices | Other devices | 6 | Tablets, watches, printers |
| Vehicles | Cars | 87 | Model, package and period coverage still varies |
| Vehicles | Motorcycles | 16 | Model, package and period coverage still varies |
| Vehicles | Bicycles | 10 | Model and period coverage still varies |
| Vehicles | Other vehicles | 0 | Electric/mobility scooters, electric unicycles |
| Equipment | Event equipment | 15 | Projector screens, mixers, tripods, tents, tables, chairs |
| Equipment | Tools | 1 | Hammers, saws, ladders, sanders, grinders |
| Equipment | Sports equipment | 0 | All currently declared sports types |
| Equipment | Other equipment | 5 | Existing coverage is limited to cleaning equipment |
| Books | Textbooks | 0 | No per-title rental references |
| Books | Reference books | 0 | No per-title rental references |
| Books | Fiction | 0 | No per-title rental references |
| Books | Other books | 0 | No per-title rental references |
| Clothing | Formal wear | 1 | Suits, formal dresses |
| Clothing | Costumes | 3 | Coverage remains garment-specific |
| Clothing | Traditional wear | 3 | Hanfu, Malay traditional garments |
| Clothing | Other clothing | 1 | Rainwear |

These are stored-data counts at audit time, not a promise that every request will find compatible evidence. Some existing quotations have unknown age, condition or package details. Those values remain unknown. A category containing prices is not evidence for all products within it.

The audit found **3 completed physical records**: **1** has a saved product snapshot and eligible simulated capture, while **2** lack historical product snapshots. No completed record qualifies as independently verified paid-rental evidence. The eligible simulation is in Cameras; it is only used when no clean compatible comparison is available and the requested period fits. Old records were not reconstructed from the listing's present-day model/condition.

Private aggregate reports:

- `services/api/.data/pricing-coverage-20261109.json`
- `services/api/.data/pricing-readiness-20261109.json`

Repeat the aggregate-only audit from `services/api`:

```powershell
npm.cmd run audit:pricing-readiness -- --output .data/pricing-readiness-NEW.json
```

Output must be a new path. The audit is bounded, refuses partial results beyond its limits, creates no database indexes or records, and exports no participant identifiers, identity documents or addresses.

## Publisher checks and remaining collection work

The current [RENTISM price list](https://www.rentism.com.my/price-list/) contains microphone rental quotes but no speaker/headphone entries in the retrieved page. Expanding its Audio parser cannot supply a quote the publisher does not list.

[The Rental Guy's AV page](https://therentalguy.com.my/av-solution/) provides a speaker-and-microphone package and projector-screen references, with date/charge distinctions. The package belongs under Event equipment and must not price a portable speaker. Its screen now has a valid separate pricing type for a future approved refresh. The public check made no import or enablement change and does not independently establish reuse permission. Existing source approvals and bounded collection remain authoritative.

The largest collection priorities are portable audio, computer peripherals, gaming accessories, sports equipment, other vehicles and per-title book rentals. Reviewed quotes or appropriately recorded completed simulations are still required there. No unrelated category average, retail-price conversion, fixed brand-price rule or synthetic model-only number was inserted to fill a gap.

## Demonstration eligibility and provenance

A simulated completed rental must have:

- A physical booking in `completed`, with a valid past completion timestamp.
- An immutable saved category, subcategory, brand and model.
- A known Owner-entered or external-reference price origin; AI-derived and unknown-origin prices remain excluded to prevent a feedback loop.
- Captured/settled booking payment status and a successful recorded MYR simulated capture covering the original rental amount, dated no later than completion.
- A compatible item domain, specifications, package and rental period for the current request.

The price uses the saved base rental charge and original rental-day count, excluding the deposit, delivery and waiver. Existing duration rules remain: a completed multi-day average is not advertised as a confirmed one-day rate. Seed rows without the required capture/snapshot cannot become rental evidence simply because an environment flag is enabled. No administrator review or real payment was invented.

Additive response fields include `evidence_mode`, `evidence_cohort`, separate simulated/demo completed counts, `estimate_kind=reference_guide`, and structured `pricing_guidance`. Existing endpoint paths and fitted features stay compatible. The client cannot select the server's evidence mode in its request body.

## Verification

- API: **704 passed, 3 existing skips** in `.data/testing/20261109-231748-f49834d4/`.
- AI: **639 passed** in `.data/testing/20261109-231936-f3aa16fe/`.
- Flutter: **719 passed, 3 existing skips**, clean analysis; main web, admin web and Android debug builds passed in `.data/testing/20261109-231821-adf088df/`.
- Model-artifact checksums remained unchanged. No retraining, deployment or live record cleanup occurred.
- New API tests exercise no-data recovery and exact-reference guides through the endpoint for all 22 subcategories. These controlled identities/prices are isolated fixtures, not additional marketplace observations.
- Tests cover explicit mode selection, production rejection, simulated capture and snapshot requirements, AI/unknown exclusion, clean precedence, unchanged stored records, period compatibility, sparse/identical references, exact unknown-type identities, PA/portable/microphone separation and power standards.
- Flutter tests cover manual-pricing recovery, retry distinctions, explicit price application, visible simulation limitations and retained existing pricing/CSV behavior at 360/390/1024 pixels with enlarged text.
- Four fixture renders passed at 390/1024 pixels with 130% text. The 390-pixel missing-data and demo-guide cards were visually inspected. Final copy/currency/snapshot-guard follow-up passed 8 focused API tests and 49 Flutter/render checks (one existing skip). API environment validation also confirmed this laptop uses the valid development demonstration configuration without printing credentials.

Real Android interaction and independent numerical pricing accuracy were not evaluated in this task. The change improves coverage handling and recovery; it does not establish real-world accuracy or guarantee an amount for every catalogue entry.

## Commit message

```text
feat(pricing): add demo-history fallback and clearer price recovery

- audit all 22 subcategories and report product-type evidence gaps
- keep eligible completed simulations separate from clean pricing and exports
- offer factual guides for sparse or identical compatible price observations
- preserve exact named matches and distinguish audio packages and projector screens
- replace dead-end unavailable states with manual pricing guidance and useful retry
- add API and Flutter regression coverage without retraining deployed models
```
