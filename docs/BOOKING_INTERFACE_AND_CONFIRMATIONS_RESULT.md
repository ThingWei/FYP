# Booking interface and confirmation improvements

Implemented for the live RentHub app on 7 November 2026. Existing uncommitted
Atlas/launcher and rental-condition work is preserved.

## User-visible changes

### Confirm important actions

- Renter and Owner profile **Log Out**, and administrator **Log out**, now ask
  **Log out of RentHub?** with **Stay signed in** and **Log out** actions.
  Repeated taps cannot open multiple logout prompts. Staying signed in or
  dismissing the prompt does not call logout.
- Owner service start/delivery, physical return confirmation and extension
  decisions now require confirmation before the existing operation runs.
- Renter service completion also requires confirmation. Existing agreement,
  booking approval/rejection, handover/return photo, destructive and payment
  confirmations remain in place.
- Session-expiry **Sign in again** recovery and logout after an explicitly
  confirmed account closure retain their existing behavior; no redundant logout
  prompt or automatic Auth0 launch was added there.

### Horizontal rental progress

Physical rentals show icon-and-label stages: **Request, Approved, Handover,
Renting, Return, Completed**. Services show **Request, Approved, Service, Review,
Completed**. The strip is visible without expanding the condition-photo section.

Narrow screens scroll sideways and include a swipe hint. The current step is
brought into view when the saved stage changes. Labels wrap at larger text sizes;
manual scrolling is retained across ordinary rebuilds. Completed/current/future
steps have distinct styling and semantic descriptions. Paused/cancelled/disputed
journeys retain their actual state and the explanatory next-step text.

This is a visual presentation of recorded lifecycle states. It does not add
courier dispatch/transit events, live parcel tracking or automatic handover.
Future approved physical bookings still wait for the booked day and the Owner's
explicit handover. Existing photos remain in expandable details.

### Clearer dialog actions

All 18 live feature files that construct ordinary alert dialogs now use the
shared `rentHubDialog` helper, as does shared `confirmAction`. It still returns a
standard Flutter `AlertDialog`, preserving form validation, navigation and
accessibility behavior.

Actions use equal-width columns **side by side**, with a 12-pixel gap and at
least 48-pixel touch height. Button text can wrap within its own button;
important actions do not overlap or fall into an unspaced overflow stack.
The shared padding is compact enough for three actions on narrow screens.

Cancellation now explains the action before asking for a reason, presents
**Keep Booking** and **Cancel Booking** separately, and distinguishes the
cancellation action in red. Its title/content can scroll when space is reduced.
A failed validation retains the reason and sends no cancellation request.

The three demo checkout outcomes are peers: **Cancel**, **Decline**, **Pay demo**.
They remain distinct and retain their existing success/decline/cancel semantics.
No payment write occurs merely by opening or closing the dialog. One-action
viewers retain their Close action; bottom sheets and full-page forms keep their
existing navigation rather than being converted into alert dialogs.

### Booking search and filters

Both **My Bookings** and Owner **Booking Requests** now provide:

- Explicit search by item/service title, participant name or booking reference.
  Press the keyboard Search/Enter action to apply it; the X clears the search.
- A compact filter icon with an active-filter count.
- Status: awaiting approval, scheduled, in progress, completed, issue under review,
  cancelled, declined or expired.
- Physical-item/service type, category, payment status and rental date range.
- Sorting: newest request, oldest request, earliest start date or latest start date.
- Clear active-filter labels, total results and a useful no-match state.
- **10/20/50 bookings per page** within the filter dialog. Existing dot pagination
  remains at the bottom, keeping the top of the screen uncluttered.

Back/dismiss in the filter dialog preserves current filters. Apply resets the
page to one. Clear filters resets the selection; changing page retains it.
Renter and Owner filters remain separate and clear on account changes/logout.
Focused notification booking details ignore the surrounding list filter so the
specific authorized record can still be opened. Fetching a focused detail does
not make an unmatched record appear in the filtered result page.

## API and request behavior

Existing booking endpoint paths and data/meta shapes are retained. Optional
parameters extend `/bookings/mine`, `/bookings/owner` and `/bookings/admin`:

`q`, `status`, `listingType`, `category`, `paymentStatus`, `fromDate`, `toDate`,
`sort`, plus existing `page` and `limit`.

Filters apply before database counting and pagination, so results are not a
client-side slice of an already truncated first page. Search text is limited to
100 characters and treated literally, including regex punctuation. Unknown
statuses/types/sorts, malformed dates and reversed ranges are rejected. Existing
participant ownership, role checks, booking/payment rules, public-location privacy
and authorizations remain unchanged.

Date ranges mean any overlap with the chosen days. Physical-item dates remain
calendar dates. Service instants use Malaysia day boundaries, with the service
end treated as exclusive at midnight. Sorts use a stable identifier tie-breaker.
Unfiltered clients retain their original behavior and sorting, including the
administrator endpoint's default updated-time order.

The controller retains filter context for refreshes and pagination. Changing
filters invalidates older page and full-workspace responses; account generation
guards prevent cross-account writes to the cache. Requests keep independent
renter/Owner state. Failed requests show recovery rather than a false empty result.
Pagination bootstrap rechecks session/permission failures before sending a
scheduled request so it cannot overwrite those failures with an empty collection.

No database migration, data cleanup, new production dependency, Auth0 change or
business-policy change was made. Category filtering uses saved category metadata;
legacy records without a category cannot match a specific category filter and
remain visible without that filter. No category is guessed or backfilled.

## Verification

- Flutter analysis: **no issues**.
- Full Flutter suite: **623 passed, 3 existing optional skips**.
- Added eight tests for server-bound/paginated filter parameters, role/account
  isolation, superseded responses, failure recovery, logout confirmation and
  repeat taps, cancellation-button geometry/horizontal steps at 360/390/1024,
  and explicit search/clear/filter-dialog navigation.
- Existing checkout action-layout assertions were updated to verify the three
  separated peer actions. Existing progress tests now verify horizontal labels
  and icons. Existing session-expiry/permission recovery, checkout, admin,
  validation, photo and role-isolation checks pass.
- API lifecycle/dispute/filter run: **44 passed**, explicitly excluding the
  previously documented unrelated legacy paid-pending expiry/duplicate test.
  New regression data spans more than one page; assertions cover filtered totals,
  second-page results, literal punctuation, owner/renter/foreign-account isolation,
  date overlap, malformed input, stable sorting and Malaysia service boundaries.
- No live bookings, payments, records or database settings were changed by tests.
- Web build: **passed** (`build/web`). Existing `socket_io_common` WebAssembly
  dry-run warnings and the existing Cupertino icon-font warning remain. The
  normal web build succeeds; no WebAssembly compatibility is claimed.
- Android debug build: **passed** (`build/app/outputs/flutter-apk/app-debug.apk`).
  Existing future Kotlin Gradle Plugin migration warnings for `firebase_core`
  and `shared_preferences_android` remain; no plugin changes were needed.
- `git diff --check`: **passed**. Formatting was applied to changed Dart files.
  No changes were staged or committed.

The excluded existing test is `legacy paid pending requests block duplicates
after their payment timer, ahead of newer unpaid duplicates`. It expects a
duplicate rejection after expiry while the existing expiry policy expires that
request. This task does not silently change that policy or claim an unfiltered
API suite passes. See `RENTAL_PROGRESS_AND_CONDITION_RESULT.md` for the earlier
failure details.

## Try the updated interface

1. Restart through the usual launcher so the new API and Flutter build are used.
2. Open Bookings, enter part of an item name and press Search/Enter. Clear with X.
3. Apply a status, category or date range. Change page and verify filters remain.
4. Switch to Owner Requests; its filters and records should remain independent.
5. Expand a booking and swipe the icon strip. Check that future approved items
   remain scheduled and no courier statuses are invented.
6. Open cancellation, inspect the separated buttons, then choose Keep Booking.
7. Tap Log Out, choose Stay signed in, then confirm logout when ready.

Real Android touch/camera/GPS and a supervisor walkthrough have not been operated
in this task. Widget geometry/text-scaling checks and builds do not replace that
final device check. Existing prototype-only screens were not otherwise redesigned.

## Commit message

```text
feat(ui): improve booking filters, progress and confirmation dialogs

- confirm logout and key rental lifecycle actions before writing
- show horizontal icon-based rental progress with accessible stage labels
- standardize separated responsive dialog actions across live screens
- simplify cancellation and demo checkout button layouts
- add server-side booking search, filters, date ranges and stable sorting
- retain independent role filters and reject stale/account-switched responses
- cover pagination, access isolation, responsive layouts and recovery states
```
