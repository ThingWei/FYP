# RentHub recommendation AI result

Last verified: 4 October 2026

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
