# Photo previews, item-check disclosure and pricing safeguards

## 22 October follow-up: false category matches and photo context

The reported 76% was an object-detector score, not a measured probability that
an upload is a relevant physical listing photo. A screenshot/photo containing a
phone can produce a valid phone-object detection without validating the upload
as product evidence. The item-risk classifier addresses labelled photo edits,
not semantic category relevance; enabling it does not resolve this distinction.

Two code-level problems were confirmed: `detect_photo` returned after its first
expected-label guess, bypassing other models' competing context; Flutter then
described raw/legacy label matches as "Item type looks consistent", including
partial-view counts. No submitted listing or private attachment was modified.

Changes:

- A positive guess now triggers one same-orientation pass through the remaining
  already-loaded local detectors, including the fixed-vocabulary YOLO-World
  context classes. No prompts, model download, threshold reduction or training.
  Ordinary orientation retries still precede fallback detection; calls are
  deduplicated and remain bounded by three models/four orientations.
- Preserve source-specific guesses and scores rather than hiding competing
  paper, poster, illustration, screen, credit-card or page regions. If such a
  region covers at least 80% of a candidate object box, flag context review and
  exclude that guess from category-match counts/aggregate detection scores.
  A nearby non-overlapping screen/paper does not invalidate another object.
- Add a bounded OpenCV layout diagnostic for strongly flat, almost monochrome
  images containing multiple boxes and long straight lines. All signals must be
  present; grayscale, text or a single rectangle alone is insufficient. This
  can flag flowchart/document-like uploads for review. It is a heuristic, **not**
  a trained screenshot classifier or a declaration that an image is fake.
- Return `photoContext`, `photoContextReviewRequired`, `context_needs_review`,
  `listingRelevanceVerified=false` and `physicalItemVerified=false`. Context
  concerns yield a warning/manual review, not an authenticity rejection or a
  fabricated focus/lighting failure. Book pages and other legitimate supporting
  detail views remain submit-able under the existing advisory/admin workflow.
- Ordinary Flutter copy now says "Possible item type detected … Admin review is
  needed", "Item type could not be identified", or "Photo content needs review".
  Even old saved label matches no longer say "looks consistent". Context warnings
  override contradictory older match flags. Per-photo copy says a detection is
  not a confirmed match. Numeric object scores remain only in opt-in admin
  diagnostics, with an explicit listing-relevance limitation.

Actual verification:

- Full AI suite: **542 passed**, four existing warnings (two third-party
  deprecations and two expected sparse-pricing fixture warnings).
- Controlled policies cover all 22 subcategories, 99%-score false-match fixtures,
  dominant versus nearby screen/paper boxes, retained raw scores, invalid boxes,
  multiple layout signals and positive-first detector context passes.
- Real local-model `/verify/item` smoke check with three **generated flowchart
  fixtures** returned `warning`, `context_needs_review`, zero matching views and
  aggregate detection score 0. The enabled risk classifier returned normally.
  These generated fixtures are wiring/diagnostic checks, not real-photo accuracy.
- Flutter photo-panel suite: **30 passed**, including 360/390/1024-pixel widths,
  1.5× text, legacy high-score flags, zero matches and context warnings.
- Full Flutter suite: **420 passed, three skipped**. Full Dart analysis and
  focused analysis: **no issues**. Default Flutter web build passed. Existing
  non-fatal web warnings remain for the dependency's Wasm interop check and a
  missing Cupertino font declaration; no Wasm/Android build was claimed.
- Flutter initially could not open its SDK cache lock in the sandbox. Tests/build
  succeeded with approved SDK-cache access. Local AI smoke inference emitted
  non-fatal Ultralytics user-profile settings/cache permission warnings.
- No Express endpoint, request payload, authorization, booking, KYC or model
  artifact was changed by this follow-up. API evidence storage was inspected and
  already preserves the structured AI result; its suite was not rerun.

Limits and device handoff:

The exact two attached images were visually inspected in the conversation but
were **not** replayed through local inference or committed as fixtures/training
data. No fix is claimed for every screenshot, wallpaper, photographed display or
wrong image. A photograph of a real phone with its screen on can itself trigger
context review; that is deliberately inconclusive, not automatic rejection.
The heuristics and YOLO context classes are not independent real-photo evaluation
and do not improve the trained detector's measured accuracy. Subcategory coverage
and the risk model's modest benchmark performance remain separate limitations.

Restart/relaunch `run-renthub.ps1` so Flutter and the AI code are current. Re-submit
the draft photos to obtain new context evidence; existing saved analyses are not
silently recalculated. On Android, retest the actual chart/screenshot, an ordinary
physical phone, a nearby unrelated screen, and legitimate book/detail photos.
Administrators must still inspect all images. No unrelated module was changed.

Commit message:

```text
fix(verification): avoid treating object guesses as confirmed listing matches

- inspect competing local-model context after a positive item prediction
- flag dominant document, illustration and on-screen regions for human review
- add conservative multi-signal line-art layout diagnostics
- retain raw scores without counting context-conflicted guesses as item matches
- replace consistent-type claims with tentative, legacy-safe photo summaries
- test all-domain context policy, nearby objects and responsive review messages
```

Updated: 9 October 2026.

## Photo input coverage

All existing live photo-picker inputs now show a local, zoomable confirmation
before upload. Cancel returns without uploading or submitting the attachment.
This does not change upload purposes or access permissions.

| Existing input | Preview behaviour |
| --- | --- |
| Owner listing creation/edit | Confirm before upload; selected thumbnails, remove and tap-to-enlarge |
| Manual MyKad / driving-licence evidence | Confirm before upload; selected document thumbnails and enlargement |
| MyKad camera capture | Existing retake/use-photo capture preview retained; uploaded selections gain thumbnails |
| Chat attachment | Confirm before upload/send; existing received-image viewer retained |
| Physical-item handover evidence | Confirm before upload and handover action |
| Physical-item return evidence | Confirm before upload and return action |
| Dispute submission and response | Confirm before upload; selected thumbnails, remove and enlargement |
| Insurance claim evidence | Confirm before upload and claim submission |

PDF evidence is confirmed with its filename and explicitly labelled as a PDF;
an inline PDF renderer was not added. There is no existing avatar photo-picker
input to wire. Service listings still do not receive physical-item checks.

## Listing review photo fix

The previous listing review dialog extracted an upload ID and requested the
private route even for public listing photos. The private endpoint correctly
returned 404 for those public uploads.

The shared loader preserves `/api/v1/uploads/public/ID/content` and public HTTP(S)
URLs. Private `upload://ID` references use the authenticated private route. Only
an ambiguous ID/reference returning private-route 404 can try the public route;
403 never triggers a fallback. Backend visibility/ownership checks are unchanged.

RentHub bearer/identity headers are attached only to matching API origin and
path-prefix downloads, not external storage URLs. Failed thumbnails offer retry.
Owner and Admin listing review dialogs use the same loader and zoom viewer.

## Item detection safeguards and remaining limitations

- Results include original photo index, image dimensions, quality details and
  normalized detector bounding boxes. Review dialogs draw boxes without modifying
  the image, including when zoomed.
- Overall confidence is now the sum of each photo's highest matching detection
  score divided by the number of submitted photos. Unmatched or missing views
  contribute zero. One 97% matching view among three is approximately 32.3%, not
  a 97% whole-submission result.
- All views must match for an overall positive category check. Partial/incomplete
  analysis is explicit. Raw per-object scores remain available.
- Scores are not authenticity probabilities. Wallpapers, illustrations and
  screenshots can produce confident false detections. Admin approval remains
  required; brand, model, ownership and stated condition are not authenticated.

These changes improve disclosure and inspection, **not the trained detector's
accuracy**. The inspected item model finished 60 epochs with validation mAP50
approximately 0.480 and mAP50-95 approximately 0.343. These are detection metrics,
not an 87%/97% authenticity success rate. The item EfficientNet risk artifact was
missing at audit time. A risk classifier is separate from correcting detector
false positives. Better negative examples and independent evaluation are still
needed; no model was retrained or replaced in this task. The reported wallpaper
itself was not supplied for inference or visual inspection.

Existing stored verification history is not retroactively reanalysed. New checks
receive the boxes/view-count fields; older checks remain readable without them.

## Pricing audit and safeguards

Brand/model, condition, age and rental duration reach the inference contract.
The repeated price is not a hardcoded `71.44` value. Unseen identities are encoded
with `OneHotEncoder(handle_unknown='ignore')`, so two unknown brand/model names
can produce the same features. Catalog recognition establishes identity, not a
market rental price.

The inspected saved pricing metrics report 5,000 synthetic and 19 real rows:
13 active asking prices, four accepted-booking targets and two completed-rental
targets. Synthetic brand selection does not establish real product values.
Saved product-model permutation importance is zero; brand influence is very small
relative to marketplace medians and item age. Good synthetic evaluation scores
do not establish real-market product-specific accuracy.

A controlled no-evidence request previously returned RM 84.86 for different
manual brands and for two distinct smartphone identities. That audit request
was not the user's exact RM 71.44 case. After this change the no-evidence path
returns `available=false` and no numeric prediction instead.

The read-only MongoDB audit found sparse product-specific evidence, many legacy
physical listings without brand/subcategory, and only two completed paid physical
bookings. No records were fabricated or inserted.

New response fields are `pricing_scope`, `product_specific_evidence`,
`evidence_status` and, for model predictions, `identity_model_coverage`.

- A positive count and finite positive price median are required for usable
  evidence. No usable listing/completed-rental evidence means no numeric model
  suggestion; manual daily-price entry remains available.
- Exact-product evidence is distinguished from brand, subcategory or category
  estimates. Broader estimates carry low-confidence warnings and explicitly
  disclose that different products may receive identical estimates.
- Unseen brand/model identities and predominantly synthetic/demo training are
  disclosed. Synthetic-heavy predictions are capped at low confidence.
- Statistical fallback remains separately labelled and has the same evidence
  scope disclosure. Catalog sources never supply rental-price rules.
- Flutter displays the evidence scope/warnings and discards a late response if
  the relevant pricing inputs changed while the request was running.

No arbitrary brand multiplier, fixed price or artificial price difference was
added. Product-specific accuracy still requires representative real pricing
observations and a retrained/evaluated artifact. A broad estimate is advisory,
not a validated current market quote.

## Validation

- Full AI suite: 277 passed, two existing dependency deprecation warnings.
- Express pricing evidence/catalog tests: 11 passed; one opt-in live-AI E2E test
  skipped because `RUN_AI_E2E` was not enabled.
- Flutter full suite: 160 passed, two skipped. Photo tests cover public/private
  routing, credential boundaries, 403 handling, retry, preview cancel/confirm,
  zoom and detector overlays, including 360/390/1024-width cases.
- Edited Flutter API/live sources: analyzer clean.
- Full Flutter analyzer: unrelated existing Auth0 test arguments
  `latestLinkProvider` and `mobileLinkPollInterval` are reported undefined in
  `test/auth0_persistence_test.dart`; no Auth0 source changes made here.
- Web build succeeded. Existing optional Wasm dependency and icon-font warnings
  remain; this is a standard web build, not a Wasm build.

No physical-device camera test was performed in this task. Tests use fixture
images and do not claim that real uploads or model accuracy are validated.
Existing user training outputs were preserved.

## Try the changes

Restart the existing Express and AI processes and rebuild/relaunch Flutter using
your normal configured launcher. Do not start a second copy on the same ports.
From `apps/renthub_flutter`, use `./run-renthub.ps1 -Device <flutter-device-id>`
with the connected Android device's current ID, or `-Device windows` for desktop.

Check a public listing's review dialog, select/cancel/enlarge attachments, and
request pricing for an item with no comparables and one with broad comparables.
For fresh detector boxes, explicitly submit a new photo check; this does not
silently modify past moderation records.
