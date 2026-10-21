# RentHub real-data collection kit

21 October 2026. Preparation only: no participant consent or publisher permission
is inferred, no activity is generated, and no real evaluation is claimed.

## 1. Image-source review

Use the ignored `services/ai/.data/evaluation/item-readiness-kit-v1/` pack.
Its `source_review.json` has fields for licence, attribution, permission evidence,
physical-item grouping and near-duplicate review. All start pending/empty.

For each proposed training source:

- Identify its original source, photographer/credit, applicable licence and
  permitted research/derivative/distribution use. Preserve the required attribution.
- Record the review evidence and restrictions privately. A downloaded file, public
  URL or SHA-256 hash is not a licence or authenticity check.
- Check exact and near duplicates; keep all photos of the same physical item and
  all derivatives in one split. Source-image hashes are only proxy groups.
- Exclude MyKad, driving licences, private uploads, faces/personal data and photos
  without a suitable basis for use. Do not upload raw photos to Git or a report.
- Only acknowledge permission after completing the review. Do not generate first
  and infer permission later. Training and deployment require separate decisions.

For item-risk labels, synthetic `normal` means no controlled edit; synthetic
`risky` means a known procedural alteration. Neither means genuine/counterfeit.
Reviewed-real labels need an independently documented manipulation basis; an object
being recognized, an unfamiliar brand or a low detector score is not a risk label.
Keep uncertainty unlabelled, rather than inventing normal/risky ground truth.

## 2. Recognition photos: all 22 specific categories

The pack's `collection_template.json` contains **198 unfilled slots**:
two distinct physical items per subcategory, each photographed as overview,
alternate angle and detail, plus three unrelated images per subcategory.

- Obtain permission for these photos and retain a private consent/source record.
- Choose unrelated cases deliberately, including ordinary unrelated objects,
  posters/wallpapers and confusing textures. Verify they actually lack the target.
- Use real subtype context for books/clothing; do not relabel generic objects to
  manufacture category coverage. Object detection does not verify genre or condition.
- Fill `path`, stable physical `item_id`, `reviewed=true`, and
  `permissionConfirmed=true` only after review. Positive cases also need the
  canonical object `label` and actual normalized `[left, top, right, bottom]` boxes.
- Move completed entries into `reviewed_cases.json`. Leave incomplete slots in
  the template. The evaluator refuses unreviewed/incomplete cases.
- Keep this set independent of training/development items. Supply
  `--training-manifest` to check known group/hash overlap. This cannot detect every
  differently named near-duplicate or prove physical-item independence.
- Record failures instead of tuning on the final holdout. Subsequent fine-tuning
  needs a new evaluation set. This small diagnostic set is not a reliability guarantee.

From `services/ai`, after real review:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_item_recognition `
  --reviewed-cases .data/evaluation/item-readiness-kit-v1/reviewed_cases.json `
  --training-manifest .data/datasets/YOUR_REVIEWED_TRAINING_SET/manifest.csv
```

Omit the manifest option only when no training/development manifest is available;
record that overlap checking was incomplete. This command must not be run on the
unfilled template as if it were ground truth. Missing models/cases are not passes.

## 3. Consenting testers and evidence collection

Suggested invitation, not a substitute for your institution's research process:

> Would you like to help test my RentHub FYP? Participation is voluntary. We will
> use demo payments, not real financial credentials or money. With your agreement,
> I will use your test actions and feedback to evaluate the app. Reports will use
> aggregate or participant-code results, not your identity documents or precise
> location. You can stop and ask me to exclude your test activity.

Follow any supervisor/institution requirements. Record agreement, permitted uses
and exclusions privately using participant codes. Never mark consent on someone's
behalf or ask them to share passwords, OTPs, identity images or payment credentials.
Use authorized, already prepared test accounts; do not bypass verification rules.

Use **dedicated staged-testing accounts**. Keep their account IDs in a private
JSON array under `services/api/.data/staged_test_users.json`; never commit it.
The export commands below label all interactions/bookings from those accounts as
`demo_seed` in the export only. A tester exercising a scripted scenario is not a
real commercial customer or completed marketplace transaction. Do not mix staged
and natural activity on the same account. Existing history is not rewritten.

Suggested scenarios (people perform actions themselves):

1. Renter chooses an area, browses several categories and opens personally relevant
   listings; note relevance and any unavailable results. Opening details is a view,
   not merely seeing a card.
2. Renter saves an item, revisits Home and checks recommendation refresh/recent views.
3. Renter reads the agreement, requests dates and tries demo decline/cancel before
   explicit demo success. Owner approval remains required; pending is a soft hold.
4. Actual Owner reviews and decides the request; continue an authorized physical
   or service lifecycle using test evidence, not invented real transactions.
5. Renter reports whether the suggestions were relevant, whether the location and
   availability were useful, and what was confusing. Keep feedback separate from
   implicit-action ratings; viewing/saving is not a satisfaction score.
6. Repeat with sparse/new-account history. Record cold-start behavior and failures,
   rather than asking everyone to select the same item to inflate ranking results.

Collect natural, permissioned marketplace activity separately when it exists.
The `marketplace` source label alone does not prove consent or a commercial rental.
Exclude a non-consenting participant entirely instead of relabelling their data.
Do not export their data until an appropriate exclusion workflow has been applied.

## 4. Safe exports and offline evaluation

From `services/api`, inspect aggregate counts without writing a file or database:

```powershell
npm.cmd run export:pricing-data -- --summary-only
npm.cmd run export:recommendation-data -- --summary-only
```

After consent/exclusion review, choose NEW filenames and identify staged accounts:

```powershell
npm.cmd run export:pricing-data -- --output .data/prices_reviewed_round1.json --staged-users .data/staged_test_users.json
npm.cmd run export:recommendation-data -- --output .data/interactions_reviewed_round1.json --staged-users .data/staged_test_users.json
```

Both commands use bounded native reads (10,000 per collection; explicit maximum
100,000), never create indexes/collections and refuse overwriting files. Exports
omit emails, identity documents, account identifiers and exact coordinates;
recommendation users are pseudonymized, not guaranteed anonymous. Keep exports private.
Pricing evaluation separately caps input at 10,000 observations.

From `services/ai`:

```powershell
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/prices_reviewed_round1.json `
  --report .data/evaluation/pricing_round1.json
.\.venv\Scripts\python.exe -m app.training.train_recommendation `
  --real-export ../api/.data/interactions_reviewed_round1.json `
  --evaluate-only --no-synthetic --report .data/evaluation/recommendations_round1.json
```

Reports must be new. Neither command deploys a model. Asking-price, accepted and
completed targets stay distinct; demo/synthetic observations cannot validate real
accuracy. Sparse holdouts remain insufficient/no-holdout, not zero error.

## 5. Price-source access review

For iRent, review current terms/access/reuse conditions and obtain clarification
or permission where needed. Keep a private record of source ID, reviewer/date,
relevant terms/permission evidence, permitted purpose and restrictions. Do not
fabricate approval from a working parser or an allowing robots file.

Use `npm.cmd run inspect:price-sources -- irent` for a bounded, no-write probe.
Only after actual review, add `irent` to the existing approved IDs (preserve other
entries), restart the API, explicitly enable it in Admin and inspect source health.
Enablement must still pass current policy/parser checks; this guide does not grant it.

12RENT needs a usable access policy or publisher-approved alternative feed;
do not bypass its malformed-policy block. RentSmart needs an accessible structured
catalogue with explicit MYR amounts/periods before adapter implementation. Keep
unavailable sources disabled and preserve manual pricing/RentHub evidence.
