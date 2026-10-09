# Photo previews, item-check disclosure and pricing safeguards

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
