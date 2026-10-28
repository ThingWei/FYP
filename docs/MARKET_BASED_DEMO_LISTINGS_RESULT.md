# Source-based demo listings for demonstration and pricing tests

27 October 2026, Malaysia time. **Twelve clearly labelled demo listings are now
active in the existing active, MyKad-approved Owner account specified by the
user.** They were first created as drafts, then completed and published following
the user's explicit selection of labelled demonstrations excluded from clean AI
evidence. The account address/identifier is not included in this public handoff.

## Where to find and test them

1. Sign into that account, switch to Owner and refresh **Listings → Active**.
2. Open a title beginning **[Demo]**. Samsung S23, Dell Latitude 7390 and Toyota
   Camry are useful initial cases because the functional check found matching
   external asking-price evidence.
3. Each listing already has an illustrative image, example condition/age,
   deposit/delivery charges and a public demonstration meeting point. These are
   fictional test details, not facts supplied by the source website.
4. Press **Suggest a daily price**. No completed rental is required. For this
   price-only check, you do not need to publish the listing or create a booking.
5. **Use this price** remains optional. Publishing these demos did not add clean
   rental-price evidence or trigger model training.

For any actual offering, use your own photos, actual item condition/age, confirmed
pickup point, availability and charges. The drafts do not establish possession,
authenticity or permission to advertise another company's inventory. Normal KYC,
image checks and administrator submission/approval rules for genuine listings
remain unchanged. This developer-only utility can publish only these selected
demo drafts; it does not grant item verification.

## Published rate basis

The committed source manifest is
`services/api/src/scripts/data/marketDemoListings.json`. These are explicit
one-day advertised amounts, checked against primary pages on 27 October. They
are not claimed to be achieved transaction prices or each product's market average.

| Demo product | Advertised one-day rate | Source |
|---|---:|---|
| Samsung S23 | RM190 | RENTISM |
| Samsung S24 | RM230 | RENTISM |
| Canon 5D, body only | RM100 | RENTISM |
| Canon 5D Mark III, body only | RM180 | RENTISM |
| Canon Eos R6 Mark ii, body only | RM350 | RENTISM |
| Canon Eos R5, body only | RM400 | RENTISM |
| Sony A7 Mark iii, body only | RM210 | RENTISM |
| Sony A7S Mark iii, body only | RM450 | RENTISM |
| Dell Latitude 7390 | RM100 | ITPA |
| Dell Latitude 7420 | RM150 | ITPA |
| Toyota Camry | RM500 | DRIVOR |
| Sony PlayStation 5 Pro | RM80 | Cilt Tech |

[RENTISM's list](https://www.rentism.com.my/price-list/) distinguishes body-only
equipment and multi-day/promotion rates. [ITPA's computer page](https://itpa.my/pc-rental.php)
states on-site rates, with delivery/setup separate. [DRIVOR's Camry page](https://drivor.my/vehicle/toyota-camry/)
lists RM500 per day for 1–3 days; the lower headline minimum was not used.
[Cilt Tech's rental page](https://cilttech.com/ms/sewaan) lists a Daily PS5 Pro
package, with a refundable deposit separately quoted. Source deposits were not
silently assigned to this Owner's draft.

No source photographs, company descriptions, identities or customer information
were copied. At initial seeding, condition, age, location and images were empty.
The later completion uses generated illustrations and explicitly fictional
condition, age, deposit and delivery charges. Only the daily advertised rates are
source-based. These are not genuine inventory offers.

## Illustrations and example presentation

The built-in `image_gen.imagegen` tool generated twelve square product
illustrations using the imagegen skill. Each carries **DEMO • ILLUSTRATION**;
the title begins **[Demo]** and the description begins **DEMO LISTING**. Generated
depictions can differ from actual hardware. One illustration per listing is used;
these are not three independent photographs or item-verification evidence.

Local assets: `services/api/.data/demo-market-images-v1/*.png`.
The complete prompt set, output paths and generator information are saved in
`services/api/.data/demo-market-images-v1/prompts.json`. These private assets are
Git-ignored; the application uses owned public upload references in the existing
Supabase bucket. For another database installation, restore/generate these assets
before running publication; committing the script alone does not ship the images.

`marketDemoPresentation.json` records all fictional example details. The demo
meeting point is the public Dataran Merdeka landmark, not the Owner's address.
Normal public-location responses remain approximate; exact listing details follow
the existing ownership/booking privacy rules. No house number/postcode was guessed.

## Data safeguards and actual database result

- Each record is `sourceType = demo_seed`, now `status = active`, `verified = false`.
- Provenance is server-owned `external_reference`, `independence = unverified`,
  retaining an originating-offer key and source/date/amount in its description.
- No completed bookings, payment transactions, reviews, catalogue records,
  pricing-reference observations or account changes were created.
- Aggregate check: listings increased **14 → 26**. Bookings remained 25, payments
  25, pricing references 335 stored records, and users 16. Stored count and
  eligible-evidence count are different measures.
- All 12 have labelled illustrative images and complete example details. Their
  prices remain excluded from clean evidence and training exports. All twelve
  stored images were downloaded and checked against their SHA-256 hashes.
- Publication added 12 owned public `listing_image` upload records (99 → 111).
  All other collection counts above remained unchanged, including 26 listings.
- Future bookings inherit `demo_seed` from the listing. Views, saves and feedback
  on demo listings remain staged in recommendation exports; they do not become
  clean recommendation interactions or organic Trending Near You evidence.
- No source setting, matching secret, deployed model or production dependency
  changed. Existing listings were preserved.

This provides realistic example **listing amounts** and a usable test workflow.
It does not create real historical rental evidence or fix model accuracy by
duplicating third-party quotations into marketplace listings.

## Seeding utility

The new script defaults to preview. It requires an explicit, existing, active,
MyKad-approved Owner account and refuses production mode. It validates the full
bounded manifest/schema before insertion and requires the existing unique listing
identifier index; it does not create indexes. Deterministic account-scoped IDs
make retries idempotent. Existing demo edits are preserved; conflicting records
are rejected. Only new listing documents can be inserted.

From `services/api`:

```powershell
npm.cmd run seed:market-demo-listings -- --owner-email '<your login email>' --output .data/evidence/NEW-preview.json
# --apply explicitly inserts drafts. It was already run for the account supplied.
npm.cmd run seed:market-demo-listings -- --owner-email '<your login email>' --apply --output .data/evidence/NEW-applied.json
```

Outputs must be new files under the private API `.data` directory. The current
preview, application receipt, aggregate checks and functional inputs are under
`services/api/.data/evidence/market-demo-listings-2026-10-27/`. They contain no
login email or raw account identifier. They are Git-ignored.

The older `seed:pricing-demo` history generator was **not run**. Its fabricated
completed examples are not needed to test this flow.

### Explicit demo publication utility

`publish:market-demo-listings` defaults to preview and requires a new private
receipt path with `--apply`. It validates all twelve selected drafts and assets
before writing, refuses production mode, refuses unrelated/changed-identity
records, preserves source lineage and uses optimistic updates. Successful retries
skip already-published listings. Interrupted image uploads can be recovered only
when their stored bytes match; failures are not silently treated as success.

```powershell
npm.cmd run publish:market-demo-listings -- --owner-email '<your login email>' --output .data/evidence/NEW-publish-preview.json
# Already applied to the selected twelve demos; use a NEW receipt for any retry.
npm.cmd run publish:market-demo-listings -- --owner-email '<your login email>' --output .data/evidence/NEW-publish-applied.json --apply
```

Private `publish-applied-v1.json`, its `.result.json` and
`publication-verification-v1.json` record the actual run. Twelve listings were
published and twelve images created; zero bookings/payments were created.

## Draft editing fixes

Missing condition on an API draft now remains unselected instead of being
silently read as Good. A condition is required for requesting a price or submitting
for review, while unfinished drafts can still save without it. Unknown item age
remains empty. No real item condition or age was assigned by the seeder.

Flutter does not submit the server-reserved external-reference origin as a client
declaration. Express preserves external lineage/originating offer through edits;
accepting an AI price also retains the source lineage. Clients cannot grant review
status or convert a copied price into independent marketplace evidence.

## Functional inference check

The existing runtime pricing service was invoked offline, with the existing
eligible external asking references selected using RentHub's shared type,
package, period and comparable-tier helpers. Scenario: Good, age 1, one-day
rental, unknown area and neutral test Owner features. No artificial completed
history was supplied. **12/12 requests returned available suggestions.**

Example diagnostic outputs: Samsung S23 RM158.19, Dell Latitude 7390 RM92.73,
Toyota Camry RM424.65. These are model estimates under the stated test scenario,
not advertised rates, accuracy measurements or guaranteed app outputs. Actual
account/location/catalogue inputs can change the result.

Canon 5D and 5D Mark III both used a broader brand comparison in this check and
returned the same RM273.74, despite distinct advertised draft rates. This limitation
is disclosed rather than hidden. Completing real-data validation remains necessary.

Private result:
`services/ai/.data/evaluation/market-demo-listings-smoke-2026-10-27.json`.
The SHA-256 stayed
`2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.
No fitting, automatic deployment or independent accuracy claim was performed.

## Verification

Automated tests cover preview-without-writes, exactly 12 draft inserts,
idempotency/retained edits, account/KYC restrictions, invalid manifest/arguments,
unchanged transaction/account history, unknown fields and source-lineage retention.
Flutter tests cover saving an unfinished source-based draft without inventing
condition/age. Full suite and build results are recorded after final verification.

| Check | Actual result |
|---|---|
| Full API suite after publication changes | 503 passed, 3 existing skips, 0 failed |
| Focused publication/booking/pricing/export tests | 55 passed |
| Full Flutter suite from preceding draft/source work | 479 passed, 3 existing skips |
| Flutter analysis from preceding draft/source work | No issues found |
| Web / Android debug builds from preceding draft/source work | Passed; no Flutter code changed for publication |
| Existing runtime AI pricing service smoke check | 12/12 suggestions available with external asks and zero rental history |
| Actual native publication verification | 12 active labelled demos, all images checksum-verified, all 12 excluded from clean pricing evidence |
| Existing local API public-image endpoint | HTTP 200, image/png, 1,766,145 bytes for sample illustration |
| Existing local API public listing search | HTTP 200; all 12 demos returned with images, labels, no private structured location details and no verification granted |
| Model artifact checksum and `git diff --check` | Passed/unchanged |

One pre-existing age-equality fixture was made deterministic by removing unrelated
wall-clock freshness from the comparison; no production relevance threshold was
changed. Existing nonblocking Socket.IO Wasm, optional Cupertino font and Kotlin
migration warnings remain. This is automated verification, not completed on-device
or authenticated live-UI UAT. No AI training or weights changed.

## Commit message

```text
feat(demo): publish source-based example listings with labelled illustrations

- prepare twelve dated Malaysian advertised-rate examples with source links
- add opt-in, account-scoped draft and publication utilities with preview receipts
- complete twelve demos with watermarked illustrations and fictional item details
- retain asking-price provenance and exclude demos from clean pricing evidence
- classify demo bookings, saves, views and feedback separately from clean activity
- preserve public-location privacy, genuine moderation and item verification
- retain external-source lineage through edits and AI-price acceptance
- keep draft condition unselected until the Owner chooses it
- verify price suggestions work with external references and no completed history
```
