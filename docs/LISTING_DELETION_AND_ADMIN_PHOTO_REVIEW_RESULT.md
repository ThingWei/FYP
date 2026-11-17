# Listing deletion and administrator photo assessment

Implemented 17 November 2026.

The subsequent photo-attribution, automatic-refresh and case-navigation update is documented in [Admin photo review and case workspace](ADMIN_PHOTO_REVIEW_AND_CASE_WORKSPACE_RESULT.md).

## Listing deletion

Owners can select **Delete listing** from their listing menu or listing details. Administrators can select it from record details. Each action requires confirmation.

Deletion is blocked by any pending, approved, active or disputed booking, scheduled/active/overdue rental, return awaiting inspection, unfinished service or unresolved case. The disabled action explains the restriction and provides access to bookings.

The API checks fresh linked records under the existing listing lifecycle lock. Booking creation checks current listing availability again inside that lock. Saved listing documents and atomic updates are guarded against restoring a deleted listing through stale writes. Availability changes use the same lock.

Deletion records `deletedAt` and a private actor reference, and makes the listing inactive. Deleted listings leave Owner/admin collections, discovery, wishlist/comparison results, recommendations and active-listing pricing inputs. Collection totals and Owner listing counts exclude them. Booking, payment, rental, review, agreement, dispute and upload records are retained. Authorized historical access continues.

Repeated requests return success. Administrators receive an audit entry for an actual deletion. The existing `DELETE /listings/:id` deactivation behavior remains available.

### API additions

| Interface | Behavior |
| --- | --- |
| `POST /api/v1/listings/:id/delete` | Authenticated Owner deletion of their listing |
| `POST /api/v1/admin/listings/:id/delete` | Administrator deletion |
| `409 LISTING_HAS_OPEN_BOOKINGS` | Open booking, rental or case prevents deletion |
| `deleteEligibility` | Additive Owner/admin response metadata with `allowed` and a readable blocking reason |
| `LISTING_DELETED` | Friendly recovery for a stale saved document |

Eligibility is batched on collection pages. Mutation responses also include current eligibility. Client metadata never authorizes a deletion.

## Administrator-controlled photo checks

The Owner AI checkbox has been removed. Server configuration controls processing. Older clients may still send the optional boolean `photoReviewConsent`, which is ignored. Historical consent records are preserved.

Eligible submitted physical listings are queued automatically. Bounded reconciliation includes existing pending listings with validated item photos. Published listings can be checked through the existing administrator action. Drafts, services and deleted listings cannot be processed.

The internal AI processing contract is now `renthub-item-vision-v2`, with server-provided `processing_authorized=true`. Only owned, registered listing-photo uploads are eligible. Identity documents, holder photos, vehicle grants, avatars, foreign uploads and arbitrary URLs remain excluded.

The admin detail page has one **AI photo assessment** section showing Gemini findings. It presents item type, across-photo consistency, visible condition and branding in compact responsive cells. Photo-linked concerns appear with thumbnails. Additional observations are collapsed. The old local-detector panel has been removed from the live admin detail flow. Local submission checks continue.

The panel uses cautious observations, including **Possible match**, **Difference detected** and **Unable to assess**. Approval and rejection remain administrator actions. A short visible explanation covers the limits of determining authenticity or ownership from photos.

### Configuration and recovery

- Current service availability is separate from saved assessment results. Earlier disabled/setup failures stop appearing as the current state after readiness recovers.
- Pending configuration-only failures can requeue safely. Successful snapshots remain cached. Changed item fields/photos, deletion or a different processing contract invalidate the snapshot.
- Shared worker leases, daily allowance, request spacing, storage bounds, provider deadlines and bounded retries are retained. A spacing wait and an exhausted local daily allowance have distinct reasons.
- Refresh reads status. Check/Try again queues work promptly and polls for its result. Repeated taps and stale-account responses are guarded.
- API health/readiness expose the running enable flag and processing contract without credentials. The launcher checks the new API capabilities and identifies stale API settings, AI configuration disagreement and older review contracts.

Both existing private enable flags read `true` during inspection. The AI service was offline at that point. Configuration files and credentials were left untouched during this implementation.

Restart the original RentHub launcher and reopen the admin portal after updating the code. A reused older process can retain its previous environment or processing contract.

## Verification

All automated API/provider checks used isolated configuration, temporary databases and mocked external effects. Shared marketplace records were untouched. No item photos were sent to Google during verification.

| Check | Latest result |
| --- | --- |
| Full API suite | 833 passed, 3 existing skips |
| Focused deletion/photo-review API suite | 39 passed before the additional readiness regression, also covered by the full suite |
| Full AI suite | 666 passed, 4 existing dependency warnings |
| Focused Gemini Python suite | 27 passed |
| Full Flutter suite | 975 passed, 3 skips, 1 existing unrelated gallery test failure |
| Flutter analysis | Clean |
| Main web, admin web and Android debug builds | Passed |
| Launcher, reliability, Atlas access, Atlas automation and Android discovery suites | Passed |
| Responsive previews | Passed at 360/390/1024/1440 widths with enlarged text |
| Model/metrics artifact checksums | Unchanged |
| Live Google inference and physical-device walkthrough | Pending |

The existing failing Flutter test is `item_detail_polish_test.dart`, **full photo gallery starts on selected image, swipes, zooms and closes without losing the draft**. It expects the semantics label `Preview Camera, photo 2`, which the existing carousel does not expose. This failure was documented before this change. Gallery behavior was left untouched by this work.

Deletion regression checks cover both roles, foreign access, incomplete drafts, every unfinished booking/rental/case state, preserved history, filtered totals, stale writes, repeated deletion and concurrent lifecycle decisions. UI checks cover confirmation, cancellation, fresh server conflicts, account changes and readable disabled controls.

Photo-review checks cover removal of Owner control, old-client compatibility, private upload exclusion, configuration recovery, provider unavailability, shared worker deduplication, quotas, stale snapshots, service isolation and the single admin results panel.

Private logs are under `.data/testing/listing-photo-review-20261117-120712/`. Fixture-only previews are under `apps/renthub_flutter/.data/listing-photo-review-previews/`.

### Remaining walkthrough

1. Restart the original launcher and confirm the API and AI readiness messages.
2. Open a pending physical listing in admin and check its photos. Verify the actual Google/storage response and latency with an eligible photo set.
3. Verify Delete is disabled for a listing with an open booking. Use an expendable, booking-free listing to check the confirmation and refreshed collection.
4. Check phone gestures and screen-reader navigation. Real-photo accuracy requires a reviewed evaluation set.

## Commit message

```text
feat: add safe listing deletion and platform-controlled admin photo assessments

- add confirmed Owner and admin deletion with shared lifecycle safeguards
- block removal while bookings, rentals, returns or disputes remain open
- retain historical records and guard against stale listing restoration
- refresh deletion eligibility, filtered collections and Owner counts
- remove the Owner Gemini checkbox and retire its processing gate
- version the internal platform-authorized image-review contract
- recover stale configuration failures and retain shared queue limits
- distinguish service readiness, waiting, quota and saved assessment states
- replace duplicate admin panels with concise Gemini findings and photo previews
- detect outdated API contracts and mismatched running launcher settings
- add API, AI, widget, launcher and responsive-layout regression coverage
- document setup, verification results and remaining live-provider checks
```
