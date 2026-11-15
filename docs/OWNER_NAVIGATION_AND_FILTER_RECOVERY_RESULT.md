# Owner navigation, filters and review access

Implemented 15 November 2026. Covers live renter/Owner screens and their existing APIs. No migration, new dependency, pricing/scoring change, payment change or live record update.

## Visible changes

| Area | Result |
|---|---|
| Discovery filters | Space between Choose location and Search radius. Recently Viewed now applies the selected category, type, prices, public locality/radius and rental-date availability before selecting results. All Home sections share specific-category filtering when supplied. |
| Booking filters | Removed Category. The combined booking type reads All. Applying/searching clears obsolete category constraints rather than keeping an invisible filter. |
| Rental agreement | The introductory card separates review, final-charge and approval information into short lines. Saved/versioned agreement terms are unchanged. |
| Profiles | One Trust score link opens separate Owner and Renter score cards, stacked on mobile and placed side by side when space allows. Existing score calculations remain unchanged. |
| Application settings | Enabled push status no longer mentions API registration. Permission, connectivity and availability states remain visible. |
| Completed rentals | Reviews opens saved feedback by this participant and published feedback from the counterpart. Older feedback remains readable after its edit window. Existing create/edit rules still apply. Agreement remains accessible. |
| Owner Home | Refreshing/viewing an existing booking or rental replaces it in place. The second action card no longer jumps to the first position on return. New records can still be added; actual lifecycle changes retain their existing rules. |
| Owner listings | Drafts open the existing edit form. Other statuses open a private Owner details page with permitted Edit, gallery, supplied facts, description and location. Physical-item Photo checks is a separate action. Pending/inactive records have no Edit action; services have no physical condition/photo-check controls. |
| Photo enlargement | Owner photo-check images and saved listing photos in the edit form use the full-screen black swipe/zoom viewer. Saved tentative detection overlays remain available; opening images does not rerun analysis. |
| Listing cards | Corrected text-width measurement and kept action controls at the card bottom with normal padding below. Removed the extra empty region below wishlist/comparison controls. |
| Saved places | X clears the selected place without deleting the saved address. Unchanged auto-filled destination text/pin clears with it; independently edited destination drafts remain. |
| Wishlist and Owner lists | Photo thumbnails replace generic icons. Existing authorized image loading and failed/missing-image placeholders remain; tapping the thumbnail follows the row destination. |

Home's separate Nearby section retains its existing scope: with `separateNearby=true`, Recently Viewed and Trending are general results filtered by the other selected constraints, while Nearby uses the selected centre/radius. Without that option, radius filtering excludes unpinned records. Eligibility, blocking, account restrictions and approximate public-location privacy remain enforced. No result is invented to fill an empty section.

## Interfaces and safeguards

- Added authenticated `GET /api/v1/listings/owner/:id`. Requires the actual active Owner profile and uses the existing owned-listing projection. Foreign/missing records return 404. Public listing endpoints retain approximate locations and private-record restrictions.
- Added authenticated `GET /api/v1/reviews/rental/:rentalId`. Requires an actual rental participant and returns nullable `writtenReview` and `receivedReview`. The latter includes only published counterpart feedback. Explicit projections exclude moderation/flag metadata, private booking details and database internals. Viewing performs no write.
- The review page requests its own pair rather than searching a loaded/paginated review list. It preserves successful content during retry and guards late responses/account changes. Failed or malformed retrieval does not enable a duplicate review action.
- Owner listing details also guard account changes, foreign responses and superseded requests. Refreshing its cached snapshot preserves list order. Read access never creates a booking or authorizes payment.
- Existing endpoint paths and response shapes remain compatible; recommendation subcategory input is optional. No authentication behaviour or authorization policy was changed.

## Verification

Checks use temporary databases, fixture identities and isolated configuration; they do not operate on the shared demonstration database or real external services.

| Check | Result |
|---|---|
| Focused API checks | 24 passed: owned-status access, service records, authentication/foreign access, public-location privacy, review visibility/edit expiry, projection safety and filtered Home sections. |
| Full API suite | 793 passed, 3 existing skips, 0 failures. |
| Full Flutter suite | 946 passed, 3 existing skips, 0 failures, including draft/service navigation and edit-form gallery checks. |
| Flutter analyzer | No issues found. |
| Main web build | Passed. |
| Administrator web build | Passed. |
| Android debug APK | Passed. |
| Fixture render checks | 4 passed, producing 16 private previews across 360/390/1024/1440 widths. Inspected mobile filters/cards/details and desktop reviews. |
| Whitespace/diff check | Passed. |

Regression coverage includes stable role-specific list order, stale review/account responses, unavailable and malformed review results, expired review editing, clearable saved selections, protected thumbnail loading/row taps, draft/service details, edit-form photo enlargement, two-role trust presentation and compact layouts with 1.6x text scaling. Existing gallery, dispute-cutoff, agreement and other module checks remain in the full suite.

Private logs: `.data/testing/20261115-owner-flow/`. Fixture-only images: `apps/renthub_flutter/.data/owner-flow-previews/`. Neither uses personal photos or genuine condition evidence.

Existing non-blocking build warnings remain: the socket package's WebAssembly dry-run warning, Cupertino icon-font coverage warning and Android Gradle/Kotlin migration notices. These are not build failures. No AI, launcher, model, private configuration or production data changes were required.

Real-device navigation, TalkBack and live network/storage delivery were not manually exercised here. Automated layouts, fixtures and successful builds do not replace those observations.

## Quick walkthrough

1. Restart the API and rebuild/reopen the app so both new read endpoints are available.
2. Filter Home to one category; check every populated section. Select a location and inspect the Search radius spacing.
3. Open the second Owner action card and return; check that its position remains. Open completed Reviews and Agreement.
4. Tap an Owner listing: inspect details and Photo checks; enlarge a photo. Tap a draft to continue editing it. Check wishlist/list photos.
5. Open Trust score from a profile. In delivery booking, choose a saved place and clear it with X; independently edited address text should remain.

## Commit message

```text
fix: align Home filters and simplify Owner record navigation

- apply discovery constraints to Recently Viewed and specific-category feeds
- add protected Owner listing details and participant rental-review endpoints
- keep refreshed booking and rental records in their existing positions
- expose readable completed feedback through a dedicated Reviews page
- combine profile trust links while keeping separate role scores
- add photo thumbnails and full-screen photo-check enlargement
- tighten card spacing and make saved places clearable
- simplify agreement copy, notification status and booking filters
- add API/widget regressions and responsive layout verification
```
