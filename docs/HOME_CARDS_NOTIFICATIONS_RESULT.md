# Home recommendations, catalogue cards and notification navigation

Updated: 15 October 2026. Extends the existing live app and preserves the preceding uncommitted catalogue, delivery, maps and push work.

## Findings and fixes

### Home sometimes empty or outdated

The previous tab-return path refreshed only when `recommendationDirty` was set, not when successful results aged out. Failed requests replaced prior results and advanced a shared update timestamp. Saving also dirtied recommendations before the write completed, allowing a refresh to run against old saved-item data. The older bootstrap recommendation request ran separately from the section feed.

- Refresh scheduling now coalesces identical account/query requests. Home tab returns and foreground entry check missing, failed, dirty or over-60-second section results.
- Browsing, successful saving and booking changes update the behaviour revision. A change during a request queues a follow-up after that request completes. Saving triggers this only after the successful write; reads of a booking do not count as new activity.
- Same-context failures preserve the last successful cards and show a compact retry action. Section success timestamps and last-attempt time are separate. One failed section cannot mark the entire feed fresh.
- Account/query/location changes invalidate the old feed. Local search results also clear when their context changes; stale responses cannot overwrite a newer search. Recently Viewed clears locally after successful history deletion, including when the next refresh fails.
- Bootstrap no longer issues its own duplicate legacy recommendation request. The existing `/listings/recommended` endpoint remains compatible for searches and other callers.
- AI IDs are checked against the eligible candidate set and deduplicated **before** deciding whether to use marketplace highlights. Empty/unknown-only results now use the existing honestly labelled fallback rather than becoming an unexplained empty list.

Ranking weights, candidate eligibility, proximity privacy and the existing AI artifacts remain unchanged. No retraining, fabricated history, new model or relaxed radius/account restrictions were introduced. Genuinely empty eligible datasets remain empty, with an Explore action rather than invented results.

### Owner navigation and catalogue cards

- The Owner footer uses **Home** instead of Dashboard, retaining the dashboard icon, destination and accessible description. All five destinations remain. A large-text check also exposed fixed-ratio dashboard metric cards; their height now scales with text instead of overflowing.
- Swipe/grid cards use responsive **1:1 square images** with consistent cropping and existing local-icon error placeholders. List rows use the same square-image treatment.
- Visible card content is reduced to a capped title, MYR price, concise approximate area, applicable compact badges and short availability wording. Promoted listings remain explicitly marked.
- Longer explanations are behind **Why this item?**, including the full availability caveat. Full information remains on listing details. Wishlist/comparison actions remain available.
- Swipe/grid heights are measured against the actual card width and text scale, without adding vertical scrolling inside cards. Shared list summaries grow naturally.

## Notifications: contracts and navigation

Previously, notification-centre taps only marked notifications read. Flutter also dropped the server's `entityType` and `type`, and push routing depended on already-cached lists.

The notification model retains those fields, defaulting to empty strings for older records. Notification-centre and Android push taps now share one dispatcher and account-bound route guard. Repeated taps are coalesced per navigator/account/notification; changing accounts or logging out hides the old destination and ignores late responses. No automatic role switching or Auth0 browser launch is added.

### New authenticated endpoint

`GET /api/v1/messages/notifications/:notificationId/target`

The API verifies an active account, notification ownership and access to the referenced record. It returns only a navigation descriptor:

- `kind: booking` with `bookingId`, optional `rentalId` and `paymentId`.
- `kind: chat` with `threadId` and related booking identifiers.
- `kind: dispute` with `disputeId`, related booking/rental identifiers and optional `claimId`.
- `kind: rewards`, `verification` or `unavailable`.

Foreign/missing notifications return 404; unavailable or inaccessible referenced records return the same `unavailable` descriptor. Exact coordinates, identity evidence, fingerprints, private message contents and account details are not part of the descriptor. Opening the destination performs its normal independently authorized reads.

Bookings/rentals open the focused existing record and actions, not an unfiltered list. Payment notifications load the referenced transaction through the existing participant-only booking-payment endpoint and show its actual amount/status beside the related booking, clearly marked as demo money. Chat opens the exact conversation without requiring cached thread pagination. Dispute/claim navigation loads the actual case and rental. The existing participant `GET /disputes/:id` response adds its associated `claim`, when present, so cold-start claim navigation does not depend on a cached claims page. Review updates lead to their authorized booking context; rewards and verification use existing account-local pages.

The resolver is read-only. Opening a notification never approves, pays, books or creates a dispute. Mark-read is independent of navigation and updates local state without resetting the current category filter. A failed mark-read request does not block details.

Deleted, unsupported and legacy targets show the full original notification and available date with safe recovery guidance. Read timeouts reset loading and offer explicit retry; session expiry shows sign-in guidance without automatically launching Auth0. Raw server errors/URLs are not displayed.

## Verification

- Full Flutter suite: **360 passed, 3 skipped**.
- Full API suite using temporary databases: **348 passed, 3 skipped**. Real push delivery and background jobs were disabled during API tests; no live marketplace records were changed.
- New tests cover request coalescing, activity/save-write races, retained results, per-section failures and successful timestamps, Home-tab age/dirty refreshes, eligible-ID fallback/deduplication, notification ownership and target access for both participants, legacy/deleted targets and descriptor privacy.
- Widget checks cover square images, failed image placeholders, compact views at 360/390/1200 widths with 1.6 text scaling, the five-destination Owner footer, exact uncached booking/chat/payment/claim destinations, duplicate taps, read failure, late timeout responses, account changes and safe error fallbacks.
- Existing booking/payment/dispute/location privacy regressions pass. Changed Dart source/tests analyze cleanly. Full-project analysis still reports the two pre-existing Auth0 test parameters at `test/auth0_persistence_test.dart:41/43` (`latestLinkProvider`, `mobileLinkPollInterval`). No Auth0 implementation was changed.
- Launcher regression checks pass. The API advertises `notification-targets-v1`, so an older running API is not silently reused for the new route.
- Web JavaScript and Firebase-client-enabled Android debug APK builds pass. Existing socket_io_common Wasm-dry-run/Cupertino-font and Firebase/shared-preferences Kotlin-plugin warnings remain. No library upgrades were introduced for those unrelated warnings.

## Restart and device checks

Restart the original API/launcher terminal so it loads the new endpoint. Relaunch Android using the existing `run-renthub.ps1 -Device YOUR_ANDROID_DEVICE_ID` workflow. Firebase configuration from the preceding task is preserved; no secret or credential was added to tracked files.

On a real device, check Home after browsing/saving and switching tabs, swipe/grid/list presentation, Owner Home at a larger system font, notification-centre taps, background push taps and a cold-start push with a restored session. An expired or absent session must not open private records. Automated gateway/widget checks are not evidence of hardware notification delivery, and ineligible/empty marketplace data cannot be made into genuine personalized results.

## Commit message

```text
fix(home): refresh recommendations reliably and open notification details

- coalesce feed refreshes and preserve successful same-context results on failure
- refresh stale Home sections and rerank after completed behaviour writes
- validate and deduplicate AI item IDs before marketplace fallback
- use compact square-photo cards with expandable recommendation explanations
- shorten Owner navigation and fix large-text dashboard metric overflow
- resolve authorized notification targets independently of cached pagination
- share in-app/push navigation with focused booking, payment, chat and case views
- guard account changes, duplicate taps, read failures and timeout recovery
- add UI/API/launcher regressions and document verification limitations
```

This message describes this follow-up. The earlier uncommitted delivery/maps/Firebase work and its broader commit message remain documented separately.
