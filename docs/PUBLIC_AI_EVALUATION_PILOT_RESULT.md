# Sourced prices and public-photo evaluation pilot

2 November follow-up: [rotation-conflict correction and Android checks](ITEM_RECOGNITION_ROTATION_AND_ANDROID_CHECK_RESULT.md).
After using the failures to develop a fix, this pilot is a known regression set,
not an independent holdout. The original results below remain preserved.

Executed 1 November 2026. The user asked whether real-world records could simply
be generated and item images collected from Google. This round collected actual
advertised-price facts and reusable public photos. It did not manufacture
transactions, personal preferences, independent accuracy or user-study consent.

## Deliverables and boundaries

| Deliverable | Actually prepared | Meaning |
| --- | --- | --- |
| Price research preview | 13 observations, 11 originating offers, four publisher pages | Published asking tariffs, not achieved rentals or approved imports |
| Public recognition photos | 11 downloaded photos with creator/licence/source/hash records | Public smoke-test material; pretrained-model overlap unknown |
| Recognition cases | Nine manually boxed positives, two details, 22 category-negative checks | 33 cases from 11 photos; negatives reuse two photos |
| Recommendation activity | Zero new interactions/bookings/reviews | Personal choices and satisfaction were not invented |
| Production changes | No deployment, threshold adjustment, source enablement or database writes | Existing pricing/ranking/payment behaviour preserved |

Private outputs:

- `services/api/.data/evidence/public-source-research-2026-11-01/rental_price_candidates.json`
- `services/api/.data/evidence/public-source-research-2026-11-01/summary.json`
- `services/ai/.data/evaluation/public-photo-pilot-2026-11-01/README.md`
- Same photo directory: `reviewed_sources.json`, `ATTRIBUTION.md`, `reviewed_cases.json`,
  `training_exclusions.csv`, `overlap_check.json`, `recognition_result.json`,
  `pilot_summary.json` and `unlabelled_risk_scores.json`.

These remain Git-ignored. No public photo was attached to a live Owner listing
as if the Owner possessed that item. Existing demo listings remain demos.

## Price observations: source facts, not invented records

| Source | Observation | Advertised daily rate | Duration context |
| --- | --- | ---: | --- |
| [iRent](https://irent.my/product/monitor-rental/) | Dell 24-inch monitor, exact model unspecified | RM20 | One day |
| iRent | Same monitor | RM14 | Daily tariff within 2–7 days |
| iRent | Same monitor | RM12 | Daily tariff within 8–30 days |
| [The Rental Guy](https://therentalguy.com.my/camping-equipment-2/) | Double-room camping tent, up to four people | RM80 | One-day reference before tax |
| The Rental Guy | Single-room camping tent, up to two people | RM60 | One-day reference before tax |
| The Rental Guy | Mini projector, model unspecified | RM50 | One-day reference before tax |
| The Rental Guy | Mini Bluetooth speaker, model unspecified | RM30 | One-day reference before tax |
| [ITPA](https://itpa.my/pc-rental.php) | Dell Latitude 7390 | RM100 | Daily on-site rate |
| ITPA | Dell Latitude 7420 | RM150 | Daily on-site rate |
| ITPA | Lenovo laptop, model unspecified | RM70 | Daily on-site rate |
| [RENTISM](https://www.rentism.com.my/price-list/) | Canon EOS R50 + 18–45mm lens | RM100 | Daily kit quote |
| RENTISM | Canon EOS R100 + 18–45mm lens | RM90 | Daily kit quote |
| RENTISM | Canon EOS 5D Mark IV | RM250 | Daily body-only quote |

The monitor headline minimum is not treated as a one-day rate. Its ambiguous
31+ yearly tier was excluded. Daily duration-band tariffs are not invented total
booking amounts. Refundable deposits remain separate. Camping tax, transport,
setup and free handling-day distinctions are retained. Laptop on-site restrictions
and delivery/setup exclusions remain. Camera kit/body packages are distinct.

Unknown condition/age/manufacturer/exact model remain null or explicitly
unspecified. Specification-only offers have no invented canonical product ID.
Camping tent observations map to Sports equipment; there is no automatic
production expansion of the current source registry. Incompatible camping bundles,
retail prices, library fines and subscription/book bundles were not converted
to individual-item daily tariffs. Books remain a documented pricing gap.

Some publisher pages/products already occur in stored references. A fresh visit
does not create an independent product/business or erase train/test overlap.
The private file uses originating-offer keys and records all candidates as
`sourceType=external_asking_price`, `imported=false`, `cleanTrainingEligible=false`
and reuse review not independently established. Factual rate review is separate
from publisher access/reuse clearance. No disabled source was restored, no new
adapter enabled, no page scraped by the scheduler and no candidate imported.

## Licensed public-photo collection and review

Google/search results were used to locate primary sources. Images came from
file-specific Wikimedia CC0/public-domain statements, not an assumption that
anything visible in search is reusable. See Wikimedia's [reuse guidance](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia).
The local attribution record preserves the actual creator, file page, licence,
downloaded rendition and content hash. No local pixel edits were made.

The 11 reviewed photos show a phone detail, camera detail, mouse, keyboard,
all-in-one desktop, headphones, car, motorcycle, generic books, bicycle and drill.
Primary examples include [the mouse](https://commons.wikimedia.org/wiki/File:ComputerMouseCloseup3.jpg),
[the books](https://commons.wikimedia.org/wiki/File:Blank_books_stacked_on_a_table.jpg),
[the bicycle](https://commons.wikimedia.org/wiki/File:White_bicycle.jpg) and
[the drill](https://commons.wikimedia.org/wiki/File:Drill_%2B_tools.jpg).

The agent inspected the actual downloaded images before writing the nine visible
object boxes. Close-up phone/camera crops are detail-only; no whole-object success
was fabricated. An iMac search result was corrected to all-in-one desktop rather
than used as a standalone-monitor positive. Generic blank books remain Other books,
not four invented genres. Artwork/icons and irrelevant search hits were excluded.

The book publisher discloses removed cover text. That documents an edit, not a
known genuine item, original/altered pair, counterfeit or labelled real rental-photo
risk cohort. Its photo-risk ground truth stays unestablished.

The bounded metadata probe requested two candidates per domain/type. Later
requests returned HTTP errors, recorded as unavailable rather than no-match.
No access restriction was bypassed. Three additional specific reusable files
were fetched through a bounded metadata request. Source errors did not justify
reclassifying unrelated images into missing categories.

There were zero exact byte matches against 1,582 local detector training/development
images. Hash checks do not rule out resized copies, related shots, semantic overlap
or unknown general/YOLO-World pretraining. This is public diagnostic material,
not independently held-out real-world accuracy. Preserve it from later tuning
if continuing to use it as a regression set.

## Actual recognition results

Existing thresholds and local models were retained. A positive requires an
appropriate object label and at least 0.50 IoU with a manually reviewed box.
Detail views have no invented localization denominator. Inference was available
for every case in each variant.

| Variant | Localized positives | False-positive category checks |
| --- | ---: | ---: |
| Configured + general detectors | 7/9 | 2/22 |
| YOLO-World alone | 2/9 | 1/22 |
| Production hybrid | 7/9 | 3/22 |

The 22 negative checks reuse a mouse across 21 subcategories and headphones for
Computers. They are two underlying photographs, not 22 independent negative
examples. Positive images cover seven subcategories, not all 22. The hybrid's
false category matches occurred in Computers, Audio and Gaming. The generic book
and all-in-one computer failed positive localization. These failures are useful
regression cases; they do not justify lowering thresholds or claiming full coverage.

The original 198-case collection is still incomplete. These 33 cases must not be
presented as its completion, full-product accuracy or authenticity verification.

The evaluation previously required identical label spelling even for aliases
already in the reviewed type registry. It now accepts aliases only within the
actual ground-truth object type: mouse/computer mouse, for example, while still
rejecting laptop/keyboard as a mouse. This does not add detector labels, change
production routing or permit broad/fuzzy text matches. Regression tests cover
typed/untyped aliases and cross-type rejection.

Reproduce from `services/ai`, choosing a new report filename:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/public-photo-pilot-2026-11-01/reviewed_cases.json `
  --training-manifest .data/evaluation/public-photo-pilot-2026-11-01/training_exclusions.csv `
  --report .data/evaluation/public-photo-pilot-round2.json
```

## Risk and recommendation evidence remain separate

The enabled risk classifier raised its existing warning on five of these 11
public photos. Their risk labels are unknown: correctness/accuracy remain null.
That count cannot become true-positive or false-positive accuracy. A public
photograph is not proof of unaltered pixels, authenticity, condition or ownership.
The preceding frozen benchmark results remain in `AI_VALIDATION_ROUND2_RESULT.md`.

No genuine recommendation records can be created from these prices/photos.
Invented browsing/saves/bookings describe a simulator, not personal preferences
or satisfaction. The current 17 staged interactions remain useful functionality
tests and remain inadequate independent evaluation. Testers must make their own
choices and supply actual feedback; use `PRICING_RECOMMENDATION_TEST_SESSION.md`.

## Verification and handoff

- Focused recognition/readiness/risk checks: 39 passed.
- Full AI suite: 623 passed, four existing dependency/sparse-fixture warnings.
- Public recognition inference: all 33 cases completed in three variants.
- Private media/source JSON and price-preview structure checked; no paths became
  live API payloads or production dataset rows.
- Deployed model/metric checksums retained; no Flutter/API runtime changes, so
  Flutter builds and the complete API suite were not repeated for this pilot.
- Existing denied Ultralytics profile-cache messages remain; local inference
  succeeded and JSON reports are valid. No model download or rights bypass.

Recommended next work is targeted collection/evaluation of the actual misses and
unrepresented categories, permission-cleared price ingestion where suitable,
and a small consented recommendation study. This pilot does not replace those
steps or promise that additional generated records would improve accuracy.

```text
test(ai): add sourced public-photo and rental-price evaluation pilot

- collect reusable public photos with file-specific licences and attribution
- review object boxes, photo context and local training-hash exclusions
- evaluate baseline, World and hybrid detection without threshold changes
- accept reviewed ground-truth aliases while preserving object-type isolation
- prepare sourced price candidates with duration, package and provenance limits
- document failed cases and keep simulated activity out of real-world claims
```
