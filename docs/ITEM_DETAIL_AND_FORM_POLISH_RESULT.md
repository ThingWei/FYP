# Item details, photos and form polish

Implemented 15 November 2026. Earlier uncommitted work was preserved.

## What changed

- Item summaries show price/title, a tappable location name and the Owner's profile link. The Owner-trust button, duplicate location, pickup-point paragraph and “View approximate area” button are removed. The map still uses the coordinates and precision allowed by the existing API; no private pickup point is newly exposed.
- Physical-item details show saved age, brand/model, variant/package and book edition/ISBN when supplied, in separated cards. Unknown age stays absent. Services do not inherit physical condition/age controls.
- Listing and condition carousels open a full-screen black photo route at the tapped image. It supports swiping, pinch zoom, previous/next, a counter, retry, Close and keyboard Escape/arrows. Zoomed images pan without accidentally paging. Closing retains the underlying carousel, draft and scroll state.
- Gallery bytes use the existing authorized loader and stay within the route. Account changes remove the photos; late downloads cannot restore them. Identity-document/PDF viewers, image-review overlays and upload-confirmation dialogs retain their existing behavior.
- Public and self profiles label Owner and Renter trust scores separately. Previously, the item page used the Owner summary while the contact profile used the overall summary. Different values were therefore possible without a calculation defect. Tests deliberately use Owner 69%, overall 73% and Renter 81% to verify role selection and navigation. No score weights, policy or historical activity were changed.
- Received reviews identify the **author's** role, such as “Alice · Owner”. The misleading “Review as renter/Owner” subtitle is removed. Historical reviews with no author role show only the saved author name.
- The case heading shows the saved initiating name and category, such as “Alice: Late return”; identical category/summary text is not repeated. Missing names are not reconstructed from another account.
- Agreement sections retain **Booking agreement**, a Review action and smaller acceptance text. Mandatory terms review, accepted version and submission validation are unchanged.
- Handover shows one future-date notice, **Available from [date]**, with a neutral disabled action. Repeated date paragraphs and optional footer prose are removed. Photo requirements, accuracy consent, error recovery and renter receipt confirmation remain.

## Forms and pagination

- Service location type, location input, Choose location and duration have distinct gaps. The shared location field has a 16-pixel gap before its map button.
- Duration/deposit/delivery presets use a horizontally scrolling single row. Fixed-size selection icons and consistent label weight prevent selection from changing chip width or wrapping other chips. Touch and mouse dragging work; existing adjustment controls, cents, bounds, cancellation and explicit confirmation remain.
- Location search and GPS actions are separated by 20 pixels; city/state/postcode have 16-pixel gaps. Routine search/GPS prose, raw coordinates, successful lookup commentary and the numeric device-accuracy readout are removed.
- Lookup/permission/timeout errors, retry, loading, map attribution and a concise limited-accuracy warning remain. Accuracy metadata, private-pin behavior, structured address values and one final location confirmation are preserved.
- Record pagination uses transparent Material instead of an opaque footer. It retains its own layout space, page controls and touch targets; it does not cover records. Administrator dot pagination already has no separate painted background and remains unchanged.

## Data limits

This follow-up adds no API endpoint, database field, source collection, model training or dependency. Existing listing fields are reused. There is no general custom technical-specification field in today's listing schema; this change does not invent RAM, engine capacity or manufacturer specifications from a product name. New structured specification entry would be a separate feature.

## Verification

- Relevant isolated API checks: **42 passed**, covering trust policy/cache, safe profiles, review evidence and location privacy.
- Final full Flutter suite: **921 passed, 3 existing skips, 0 failed**, including the final card-spacing adjustment.
- New tests cover role-specific scores/navigation, review-author attribution, approximate map links, saved/missing age, full-screen swipe/zoom/close/retry, account changes and late photo responses, case initiators, horizontal touch/mouse chip selection, transparent footer layout and service/map spacing.
- Widget layouts cover **360/390/1024/1440-pixel** widths with increased text size. Private Inter-font previews cover the same widths at 1.3x text. Representative mobile item/gallery/service/preset/map views were visually inspected; adjacent item cards were then given explicit spacing.
- Existing API paths, payment/booking rules, identity-document access, location privacy and trust calculations are preserved. No live records or AI artifacts were modified.
- Final analysis: **No issues found**. Main web, administrator web and Android debug builds all passed. Four private visual-render tests passed; final mobile item spacing and wide-screen service/gallery previews were inspected.
- No unrelated failing check remains. Existing web Wasm/icon-font and Android Gradle/Kotlin migration warnings remain non-blocking build warnings.

Private logs: `.data/testing/20261115-detail-polish/`. Private previews: `apps/renthub_flutter/.data/detail-polish-previews/`. Images in these previews are code-generated UI fixtures, not real listing or condition evidence.

Real-device gestures, TalkBack, the Windows mouse/keyboard walkthrough and live-map delivery were not performed in this task. Automated gestures/builds are separate from those observations.

## Try it

Rebuild/reopen the app. Open an item, tap its location, open a photo and swipe/zoom/close it. Open the Owner profile to see the two labelled role scores. Check service location fields and swipe the amount/duration presets. Existing records need no migration.

## Commit message

```text
feat: simplify item details and add full-screen photo viewing

- replace duplicate location copy with a named map action
- show supplied item age and product details in separated cards
- add swipe/zoom photo viewing with retry and session privacy guards
- distinguish Owner/Renter trust and correct review-author attribution
- identify dispute initiators and shorten agreement/handover wording
- space service/map fields and keep preset choices in a stable swipe row
- remove opaque pagination backgrounds and add regression coverage
```
