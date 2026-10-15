# RentHub recommendation AI result

Last updated: 15 October 2026

## Current scope-aligned implementation (15 October)

Home now contains **Recommended For You**, **Trending Near You** and
**Recently Viewed**. Listing details contain **You Might Also Need**.
The existing five renter navigation destinations remain unchanged. Each section
has its own loading/empty/unavailable state, retry and a full list when results
exist. A failed section does not hide healthy sections. Section-only retries do
not rerun unrelated sections.

### Live signals and ranking

- Opening the live listing-details/booking page records a view, not an impression
  from Home, search, comparison or recommendation cards. Rebuilds do not record
  another view. Tracking failure does not block viewing or booking.
- `ListingView` records are unique per account/listing/Malaysian calendar day.
  The server supplies account, day and timestamps. TTL is 90 days, and read
  queries also enforce the time window rather than relying on immediate TTL cleanup.
- Viewed = rating 2 / precedence 0, below saved, booking, completed-rental and
  published-review signals. The export and Python training schema accept the same
  signal; no export, training or model replacement was automatically executed.
- Up to 100 current user's historical listing profiles are loaded separately
  from candidate results. A radius/category filter therefore does not erase a
  known interest merely because the older listing is outside that result page.
  Metadata is limited to eligible active listings, without private locations.
- Base hybrid relevance remains **60% content + 40% collaborative**. Reranking is
  `(0.75 × base + 0.15 × proximity + 0.10 × availability) / applicable weights`.
  Missing location/usable public pin removes the proximity component; service
  slot availability is not guessed and removes the availability component.
- Proximity uses the existing approximate public grid points and a linear
  `max(0, 1 − approximate distance / radius)` score. No exact distances or scores
  appear in ordinary recommendation cards.
- Physical availability uses selected dates when present, otherwise today's
  **Malaysian calendar date in RentHub's UTC-midnight date-only storage**. Existing
  approved/active/unresolved-physical-dispute/manual blocks are reused. Pending
  requests remain soft holds. “Available today—check your rental dates” is a guide,
  not a reservation or promise of availability on future dates.
- Trending uses real activity in the previous 30 days: strongest signal per
  renter/listing is viewed = 1, approved/active booking = 3, completed = 5.
  Scores sum across renters; proximity breaks ties. Active bookings use their
  activation timestamp where present. Rejected/cancelled/expired, demo-seed and
  synthetic bookings do not contribute. Promotion is not organic popularity.

### Complementary evidence and limits

Eligibility is controlled by reviewed generic-use rules, not unrestricted cosine
similarity. Cameras can suggest clearly identified tripods, suitable lighting
types or recording microphones; Event equipment can suggest clearly identified
PA/audio equipment. Current titles/product models must identify the compatible
generic item type in an eligible domain. Other domains intentionally return no
complements until a rule is reviewed; no new product category was added.

Within eligible results, real listing-level co-rentals take precedence when at
least three distinct renters rented the anchor and candidate, their start dates
were within seven days, and both start dates fall within the past year. Only
approved/active/completed marketplace records count. Otherwise the existing
content/proximity/availability ordering is the disclosed fallback. The message
asks renters to check compatibility; it does not guarantee mounts, connectors,
sizes, capacity or exact accessory fit.

### Interfaces, privacy and refresh

| Interface | Purpose |
| --- | --- |
| `POST /api/v1/listings/:id/views` | Authenticated renter detail-view signal |
| `GET /api/v1/listings/recommendation-feed` | Recommended, trending and recently viewed sections |
| `GET /api/v1/listings/:id/complements` | Eligible complementary suggestions |
| `DELETE /api/v1/users/me/browsing-history` | Clear only the current renter's browsing signals |
| Existing `/api/v1/listings/recommended` | Preserved list response with optional ranking metadata |

Feed/complement queries reuse existing filters, date validation and the
latitude/longitude/radius triplet. Feed additionally accepts optional
`section=recommended|trending|recentlyViewed` for independent retry. Sections
return `{status, items}` with ready/empty/unavailable/location_required states.
Candidate views are bounded, with at most 200 candidates to inference and
1–30 public results per section; recent history is distinct/newest first.

Own, inactive, blocked-Owner and restricted-account listings are excluded in every
section. Trending requires a selected centre; without one it prompts for an area.
Recently Viewed remains a history list rather than being silently radius-filtered.
Radius choices remain 5/10/25/50 km, default 10. Unpinned listings are omitted from
radius results, while ordinary browsing remains usable.

GPS is requested only on an explicit tap, with one 15-second reading. Accuracy is
displayed; coarse readings warn the renter to adjust the area. Denial, disabled
GPS and timeout retain manual area selection. No background tracking or automatic
reverse geocoding is used. Raw renter GPS is not sent to FastAPI, stored in view
records, exported as activity, or logged by the existing path-only diagnostics.
Listing serializers continue to remove private exact points and address details.

Returning from a listing, saving/booking changes, pull-to-refresh and area changes
refresh results. Foreground Home return refreshes dirty/results older than 60
seconds. Account/context generations and per-section request tokens discard late
responses, including overlapping retries; changed-account data is cleared.
Clearing history requires confirmation and does not delete saved listings or
bookings. No automatic retry of booking/payment writes was introduced.

Restart with the updated launcher. It requires API `recommendation-feed-v2` and
AI `hybrid-profile-v2` so old processes cannot silently omit the profile/feed.
Existing MyKad, licence and other readiness checks remain in place. The new
collection/indexes use normal model initialization; no bulk migration is run.

### Verification and accuracy boundary

- API: 330 passed / 3 skipped, including eight new scope/evidence/privacy tests
  against isolated temporary databases, not the live database.
- AI: 384 passed; new cases cover external-to-page profiles, weak view precedence
  and duplicate profile metadata. Existing hybrid/artifact tests remain intact.
- Flutter scope suite: 17 passed, including 360/390 mobile, 1100-wide aligned
  comparisons, increased text size, denial/timeout/coarse GPS, stale responses,
  independent retries, explicit legacy recovery and no booking/payment on navigation.
- Full Flutter suite: **332 passed / 3 skipped**; web and Android debug builds pass.
  Full static analysis still reports the two pre-existing Auth0 test
  constructor errors; application-only analysis is clean.
- Launcher regression passes. Existing dependency deprecation, Wasm/font and
  Android plugin migration warnings are unrelated.

Sparse real activity can leave Trending or complements empty and force conservative
recommendation fallbacks. The artifact was not retrained, and these tests do not
establish real-world ranking accuracy. The historic 4 October dataset/metrics below
are an earlier measurement, **not a new audit of today's database**. Bounded
activity/candidate queries and request-time SVD remain FYP-scale limitations;
larger deployments need aggregation and model lifecycle work. Real-device GPS,
network interruption and multi-account demonstration checks remain handoff tasks.

See [comparison scope/UI result](COMPARISON_SCOPE_AND_UI_RESULT.md) for comparison
rules, rollout, complete verification and the commit message.

## Historical baseline report (4 October 2026)

The following baseline architecture, training measurements and verification are
retained for provenance. Current behaviour is described above.

## Scope and architecture

Recommendation remains part of **Listing Management / Discovery**. It is not a
separate functional module and does not use external browsing, social profiles,
messages, payment details, or product-catalog records as training signals.

```text
Flutter renter Home
  -> GET /api/v1/listings/recommended
  -> Express reads current MongoDB marketplace state
  -> FastAPI /recommend/items
  -> TF-IDF/cosine content score + Surprise SVD collaborative score
  -> ranked active listings and truthful reasons
  -> Flutter "Recommended for you"
```

Every request reads current saved listings, bookings, completed rentals, and
published renter reviews. Saving, booking, completing, or reviewing therefore
affects the next request without waiting for offline retraining. Periodic
training still improves the saved collaborative artifact.

## Hybrid algorithm

The approved weighting is preserved:

```text
final score = 0.60 * content score + 0.40 * collaborative score
```

Content vectors use listing title, category, subcategory, brand, product model,
description, location, and condition. They do not use owner IDs, payment IDs, or
canonical-product IDs as semantic features. The collaborative path prefers the
reviewed `recommendation_svd.pkl` artifact, fits a deterministic request-time SVD
when enough live interactions exist, and otherwise uses the active listing's
rating/popularity as an explicitly named cold-start fallback.

Adapter values identify the actual path used:

- `hybrid-svd-cosine-v1`: saved Surprise SVD artifact and cosine content score.
- `hybrid-live-svd-cosine-v1`: request-time SVD and cosine content score.
- `content-cosine-with-popularity-fallback-v1`: no usable collaborative model.
- `marketplace-ordering-fallback-v1`: FastAPI returned no ranked results, so
  Express retained its active marketplace ordering.

## Canonical marketplace interactions

The same canonical builder is used by live requests and the training export.
Only one signal is retained for each `(userId, listingId)` pair. A newer signal
breaks ties at the same precedence; signals are never arbitrarily averaged.

| Interaction | Rating | Precedence |
| --- | ---: | ---: |
| Saved listing | 3.5 | 1 |
| Eligible booking | 4.0 | 2 |
| Completed rental | 4.5 | 3 |
| Published renter review | Explicit 1-5 value | 4 |

Cancelled, rejected, and expired bookings are excluded. `demo_seed` records are
excluded from live recommendation by default and cannot be enabled in production.
The read-only export labels them separately if present. User identifiers are
one-way SHA-256 pseudonyms; names, emails, phone numbers, addresses, documents,
messages, and payment data are not exported.

One limitation is that the current user document stores saved listing IDs but no
per-save timestamp. The canonical saved signal therefore uses the user record's
latest update time. Booking and review timestamps remain event-specific.

## Candidate eligibility

Express sends at most 200 current candidates to FastAPI and returns the requested
top 1-30 results. Candidates must be active and must not be:

- owned by the requesting renter;
- owned by a user the renter blocked; or
- owned by a suspended, banned, deactivated, or otherwise restricted account.

This prevents a dual-role user from receiving their own listing. Availability
for a particular future date is still enforced by the booking flow; the Home
request has no requested date and therefore treats current `status = active` as
marketplace availability.

## Reproducible dataset and training

From the repository root:

```powershell
cd services/api
npm.cmd run export:recommendation-data

cd ../ai
.\.venv\Scripts\python.exe -m app.training.train_recommendation
```

The first command writes the ignored
`services/api/.data/recommendation_interactions.json`. The second validates and
canonicalizes rows, performs a per-user chronological holdout with no repeated
user/listing pair across train and test, evaluates SVD, retrains on the full
dataset, atomically saves `services/ai/models/recommendation_svd.pkl`, reloads it,
and performs a finite smoke prediction before deployment.

The 4 October 2026 development export and deterministic seed-42 run produced:

| Measure | Result |
| --- | ---: |
| Users | 124 |
| Listings | 185 |
| Canonical interactions | 3,368 |
| Real marketplace interactions | 8 |
| Demo-seed interactions | 0 |
| Explicitly synthetic interactions | 3,360 |
| Train interactions | 2,645 |
| Test interactions | 723 |
| RMSE | 0.9011 |
| MAE | 0.7127 |
| Precision@5 | 0.0182 |
| Recall@5 | 0.0578 |
| HitRate@5 | 0.0909 |
| Ranking users evaluated | 88 |

The real records contain 7 booking signals and 1 published-review signal across
4 real users and 5 real listings. Synthetic records remain labelled
`source_type = synthetic`; they are bootstrap data, not real RentHub activity.
The low ranking metrics and tiny real share mean these figures are development
pipeline evidence, not a production-accuracy claim.

## Cold start and explanation behaviour

- **New user:** active listing rating/popularity provides a useful baseline; no
  reason falsely claims rental-history personalization.
- **Known user:** content uses known interacted candidate listings; compatible
  artifact or live SVD supplies collaborative personalization.
- **New listing:** TF-IDF content and rating/popularity remain available even
  when SVD has never seen the listing.
- **Missing/corrupt artifact:** the endpoint attempts live SVD when the canonical
  data is sufficient, otherwise returns the named content fallback.
- **Sparse marketplace:** the endpoint returns available active listings without
  inventing an SVD result or crashing.

## Development E2E result

An isolated live-process check used the configured development MongoDB, FastAPI
on port 8002, and Express on port 3002. The renter request
`GET /api/v1/listings/recommended?limit=10` returned HTTP 200 with ten eligible
listings. `l-camera` ranked first at 0.7846 using
`hybrid-svd-cosine-v1`; an unseen Canon camera listing used the truthful content
fallback. The response also included active Services, Clothing, Equipment,
Vehicles, and Books candidates, confirming that recommendation ranks RentHub
listings across categories rather than external catalog products. Temporary
processes were stopped after the check.

Flutter parses the recommendation object and displays its reason under cards in
the existing renter Home section. When personalization is unavailable, Express
still returns useful active marketplace listings, so there is no separate empty
Recommendation screen.

## Verification

- Express: 109 passed, 0 failed, 3 intentional environment-dependent skips.
- Recommendation-specific Express: 3 passed.
- FastAPI/Python: 27 passed, including 11 recommendation tests.
- Flutter: 92 passed, 2 conditional skips; static analysis has no issues.
- Artifact: atomic save, reload, compatibility smoke prediction, and runtime
  `hybrid-svd-cosine-v1` adapter test passed.

Tests cover content relevance, all six marketplace categories, saved artifact,
live SVD, missing-artifact and new-user fallbacks, unseen listings, sparse data,
60/40 calculation, duplicate precedence, source provenance, chronological
leakage prevention, own/inactive/blocked/restricted exclusions, API payload and
fallback truthfulness, and Flutter parsing/rendering.

## Remaining limitations and retraining workflow

The real marketplace dataset is too small to validate production quality.
Collaborative ranking is dominated by deterministic synthetic bootstrap data,
and new users/listings necessarily depend more on content and marketplace
popularity. Request-time interaction queries and live SVD are appropriate for
the FYP dataset size but would need batching, indexing, monitoring, and scheduled
artifact deployment at production scale.

A practical FYP retraining cycle is:

1. export the latest MongoDB interactions;
2. inspect provenance, invalid-row count, distributions, and dataset hash;
3. train and evaluate with the chronological holdout;
4. compare RMSE, MAE, Precision@5, Recall@5, and HitRate@5 with the current run;
5. deploy the reviewed artifact only after reload/smoke validation; and
6. keep synthetic and real results separate in the final report.

## Home refresh reliability follow-up — 15 October 2026

See [Home/cards/notification results](HOME_CARDS_NOTIFICATIONS_RESULT.md) for per-section successful freshness, coalesced requests, post-write activity refreshes, retained results on transient failure and eligible AI-ID fallback checks. Ranking weights and fitted artifacts are unchanged; this work fixes refresh/presentation reliability rather than claiming better learned accuracy or fabricating history.
