# User UI, conversations and record pagination

2 November: [actual Android viewing verification](ITEM_RECOGNITION_ROTATION_AND_ANDROID_CHECK_RESULT.md)
confirmed an existing paid-pending agreement, grouped chats, profile navigation,
old-message menu, map cancellation, role separation and Owner pagination. The later
[two-account payment/approval/return walkthrough](ANDROID_TWO_ACCOUNT_LIFECYCLE_CHECK.md)
also completed; its results and follow-up fixes are recorded below.

Implemented 28 October 2026. Existing uncommitted administrator, trust and pricing work is preserved.

## User-visible changes

| Area | Behaviour |
| --- | --- |
| My Bookings | Previous/Next, accurate server totals and 10/20/50 rows per page. Later pages fetch their associated authorized rentals so rental actions do not disappear. Focused booking details remain focused, without collection paging. |
| Owner requests | Independent Owner pages; outgoing renter records never enter this feed. Refreshes preserve the selected page. |
| Owner listings | Server-side paging over the entire filtered collection. |
| Owner orders | **View all orders** opens a paginated rental/service history. Home keeps a short preview. Dashboard counts come from database totals, independently of the loaded page. |
| Messages | One conversation per other account, even when there are several bookings. Conversation list paging counts people rather than booking threads. |
| Chat history | Latest 20 messages first, with **Load earlier messages**. Cursor paging prevents new arrivals from causing skipped history; duplicate IDs are merged and older-event revisions cannot restore edited/recalled content. |
| Notifications | Paged server records, independent category filters and preserved notification-target navigation. |
| Points activity | New account-scoped paginated history endpoint; the rewards summary retains its existing preview. |
| Reviews | **My reviews**, **View all reviews** on Owner Home, and **Read all reviews** on listing details. Pages use the existing review endpoints and accurate totals. The listing preview explicitly describes its recent-review sample instead of claiming that the first page is the complete review history. |
| Wishlist | Local paging of the complete saved-listing collection; this does not slice a truncated API batch. |
| Explore/search results | 10/20/50 results per page, preserving category, location, date, price and sort inputs. Home's bounded recommendation previews remain swipeable. |
| Listing cards | The rental/service price appears above the title in list/grid/swipe cards and in the main listing information card. Existing price units and promotional amounts remain intact. |
| Comparison | Selected comparison icons and the populated comparison shortcut turn blue immediately. Existing three-item/category restrictions remain. |
| Search | Debounced dropdown of up to eight distinct eligible listing titles, keyboard selection, a clear button and explicit search. Provider/network failure leaves manual searching available. |

The shared footer defaults to 20 rows and retains successful records during a failed refresh. Collection-specific loading/errors, request generations and account guards prevent stale pages from replacing another account's results. Changing accounts clears private record caches. Empty pages caused by removals return to the nearest valid page when a server total is available.

Short forms, bounded comparison selections, protected single-record detail screens and old prototype-only screens do not gain unnecessary pagination.

## Conversations without destructive merging

Historical booking threads and message IDs are **not rewritten, moved or deleted**. The API groups a participant's threads by the other account before counting/pagination, and reads messages across the same exact two participants. Grouped rows have a stable representative thread, all associated thread IDs, booking count, latest visible message and combined unread count.

Both participants' renter/Owner roles can occur across their bookings without creating a second visible person. Booking-based entry points and push targets retain their existing thread/booking references and open the same combined history. If a historical thread is closed but another thread for that pair is open, new messages use an open thread; a fully closed conversation remains closed. Blocking, account restrictions, protected uploads and participant authorization remain enforced.

Read receipts mark the relevant incoming messages across the grouped conversation. Deleted-for-me messages are excluded before counts/history and do not affect the other person's unread counts or copy. Recalled messages have a placeholder and do not count as unread content.

## Message actions and location sharing

The user confirmed these rules:

- **Delete for me:** any visible message, at any time. Only that participant's copy disappears.
- **Edit message:** the sender's text within 15 minutes. Text changes preserve an attached image or pin; they do not replace either. Messages without text cannot be edited.
- **Recall for everyone:** the sender only, within 15 minutes. Both participants see **Message recalled**. Text, image metadata and pin are absent from ordinary responses.
- **Report message:** retains the existing recipient report flow.

Long press works on mobile; secondary click opens the same menu on desktop. Delete/recall ask for confirmation. Server-side time, ownership and expected-revision checks enforce the rules even when Flutter restrictions are bypassed. Recalled/deleted entries cannot reappear because of a delayed older socket event.

The original content and a bounded history of the latest 20 revision snapshots remain private; existing reported-text snapshots are not rewritten. Recalled media stays referenced as protected evidence and cannot be deleted through the ordinary upload-removal endpoint. Recipients cannot download recalled media through its old message attachment link. These records are not included in ordinary message serialization.

**Share location** opens the existing map/search/GPS picker. Its final button says **Share location**, and a visible notice identifies the recipient. There is one final map confirmation, without an extra address checkbox or another send dialog. GPS retains the existing explicit foreground-permission behaviour; the receiver sees a read-only shared pin and can zoom/pan. The address label is the mapped/user-confirmed description, not a guarantee of a verified unit/entrance address.

Only an intentionally shared point is sent to the conversation participants. Location push/notification text is simply **Shared a location**, without coordinates or the address label. Sharing never changes a booking destination or unlocks an Owner's private pickup point. Failed location sends retain the confirmed selection with explicit retry/removal controls. Text failures retain the draft and show an inline error without covering the send button.

Text and location sends carry an optional stable attempt ID. The API deduplicates identical retries, including concurrent attempts across the grouped threads; changed content needs a new ID. Retries do not duplicate messages or notifications. No automatic write retry was introduced. Existing clients without attempt IDs remain compatible.

Recall cannot remove a screenshot, previously received notification, downloaded copy or the private moderation evidence.

## Receiver profile

Tapping the conversation header opens a safe participant profile: display name, avatar placeholder, identity-verification flag and aggregate trust history. The endpoint requires access to the conversation. It excludes email, telephone, saved addresses, private documents, fingerprints and payment data. Blocked/inactive/deleted profiles show a recoverable unavailable state. Session/account changes hide the old participant's profile.

## Payment-success agreement recovery

The reported device was Android. The agreement continues to load from the same configured RentHub API as checkout, using the saved booking ID and server-owned accepted terms; it does not open a second payment flow.

Read-only agreement requests now reconnect once after a closed HTTP connection or timeout, using a bounded timeout. Authentication, permission and validation errors are not retried. Request/account guards ignore stale responses. A failed load has an explicit Retry action and explains that the booking has not been changed.

A widget regression opens **View agreement** from an already-paid pending checkout, simulates **Connection closed before full header**, and verifies that the saved agreement opens, remains pending and causes zero payment writes. API tests also retain agreement ownership, charge snapshots, terms/history and pending-location privacy checks.

The user's exact physical-device failure was not independently reproduced from camera/device logs. This change addresses transient connection loss and verifies the navigation path; it cannot make an unreachable PC backend reachable. On-device confirmation is still required with the existing Android backend/USB or LAN setup.

## Interfaces and compatibility

- Existing `/messages/threads` and `/messages/threads/:id/messages` paths and list data shapes remain; grouping, paging metadata and structured location/edit/recall fields are additive.
- `before=<messageId>` is an opaque history cursor. Use it with page one; page/limit remain available for legacy callers. Totals apply to the current visibility/cursor filter.
- `PATCH /api/v1/messages/:messageId` accepts `action`, optional text and expected revision.
- `GET /api/v1/messages/threads/:threadId/participant` returns the safe participant profile.
- `GET /api/v1/rewards/entries` exposes the current account's complete points ledger with paging.
- `GET /api/v1/listings/search-suggestions?q=...&category=...` uses stored active listings, excludes own/blocked/restricted/unpublished entries and respects enabled categories. It never contacts external catalogue APIs.
- Existing rental lists accept a bounded `bookingIds` filter while still applying renter/Owner ownership. Owner booking metadata adds database-derived dashboard counts.
- The Flutter API client preserves list compatibility while retaining server metadata, so pagination does not invent totals from loaded page lengths.
- Message storage adds optional fields and indexes, including a partial unique index for populated sender/attempt IDs. Startup awaits message index initialization. No historical record migration or bulk cleanup is needed or run.
- `user-records-messaging-v2` is required by launcher readiness, preventing reuse of an older API that rejects the new chat payloads.

No production dependency, Auth0 flow, payment calculation, approval rule, pricing/recommendation model, AI weight or blockchain contract changed.

## Verification and handoff

Isolated database tests cover grouped conversations/counts, history cursors with intervening arrivals, unread counts, per-user deletion, revision conflicts, time windows, protected original/report evidence and recalled media, participant profiles, invalid pins, source-free search suggestions, own points, duplicate sends and foreign access. Flutter tests cover account changes, retained pages/drafts, keyboard suggestions, long press, recall/edit/profile navigation, pin retry, failed sends, price placement and later-page rental actions.

Mobile chat/list checks include 360/390 pixels with increased text size; checkout/agreement checks also cover 1024 pixels. Existing full-suite admin and role-switching regressions remain intact. Opt-in live-provider/database-write/UI-capture tests are not claimed as executed by the default suites.

| Final check | Result |
| --- | --- |
| Complete Express API suite | 621 passed, 3 opt-in skips |
| Complete Flutter suite | 553 passed, 3 opt-in skips |
| Flutter analysis | No issues |
| Complete AI suite | 606 passed; four existing dependency/sparse-fixture warnings |
| Launcher syntax/capability regression | Passed, including rejection of an older messaging API |
| Disposable launcher process-tree integration | Passed with Windows process-inspection access; only owned test fixtures were stopped |
| Administrator and main web builds | Passed |
| Android debug APK | Passed |
| Whitespace/diff check | Passed |

Existing nonblocking web Socket.IO WebAssembly dry-run, Cupertino-font and Android Kotlin-plugin migration warnings remain. Standard JavaScript web and debug Android builds succeed. No unrelated Auth0 analyzer failure was observed. The latest tests also simulate out-of-order socket events so recalled or deleted-for-me content cannot be restored by a delayed event.

The pricing artifact checksum remains `2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

### Device check after restart

1. Rerun the launcher and hot-restart/rebuild the Android application so the new client and API capability are loaded.
2. With two dedicated accounts and two bookings between them, check one Messages row, combined history and unread counts.
3. Send/edit/recall text, delete only one copy, and verify the other account independently. Test a message older than 15 minutes.
4. Share a confirmed map pin once, deny GPS permission and use map/search instead, then interrupt/recover connectivity without losing the chosen location/draft.
5. Tap the chat header; verify public profile access without phone/address/document disclosure.
6. Browse beyond 20 bookings/listings/notifications/orders/points/reviews and check filters, ranges and record actions. Check selected blue comparison icons and dropdown keyboard navigation.
7. Complete demo checkout, open the agreement and confirm pending Owner approval, saved charges and protected pickup details. Repeat after closing/reopening the app.

Native camera/GPS, physical Android connectivity, desktop pointer interactions and delivery of actual FCM notifications remain real-device handoff checks, not automated accuracy or production-readiness claims.

## Commit message

```text
feat(ui): paginate user records and unify booking conversations

- group conversations by participant while preserving booking history
- add cursor message history, precise location sharing and profile navigation
- support own text edits, timed recall and private per-user deletion
- retain protected moderation evidence and reject stale message revisions
- deduplicate retried sends and preserve drafts and selected pins on failure
- paginate bookings, listings, orders, notifications, points and reviews
- retain complete wishlist paging and filter-aware Explore results
- show selected comparison controls in blue and lead cards with rental prices
- add keyboard search suggestions from eligible marketplace listings
- recover readonly agreement loads without replaying payment writes
- test authorization, privacy, paging, retry and responsive user layouts
```
## 2 November: completed staged Android lifecycle

The [two-account Android walkthrough](ANDROID_TWO_ACCOUNT_LIFECYCLE_CHECK.md)
subsequently completed new checkout, agreement access from the payment result,
actual Owner approval, handover, renter return and Owner confirmation. It found
and corrected stale new-booking page totals, internal listing IDs on Owner order
cards and a narrow-screen agreement-action overflow. The associated calendar
job fix prevents same-day physical rentals becoming overdue before their final
Malaysia day ends. Full post-fix results: 560 Flutter tests passed (three opt-in
skips), 626 API tests passed (three opt-in skips), analysis clean, web and Android
debug builds passed. The private screenshots and staged records are not real
rental evidence; the configured phone app needs its normal launcher rebuild to
display the Flutter changes.
# 3 November 2026 follow-up: photos, trust history and page dots

- Public listing cards, recommendation thumbnails and the booking summary now
  resolve stored `upload://UPL-…` image identifiers to the existing public content
  endpoint. General URL resolution and protected document downloads are unchanged.
  The API also protects current listing images referenced by either supported
  format from deletion. Private documents remain inaccessible through public URLs.
- Read-only inspection found 12 active labelled demo listings, 12 referenced public
  upload assets and matching configured storage providers. Two sampled stored
  image objects matched their saved SHA-256 checksums. No listings, image objects
  or price provenance were rewritten.
- Shared dot pagination is used by renter/Owner server-paged records, complete
  local collections and administrator record/history/CSV-preview controls. It
  shows a bounded moving window, a blue current-page indicator, Previous/Next,
  accessible page labels and retained count/page-size controls. All page changes
  still use the existing server pagination; unknown totals do not invent pages.
- Trust details now explain recorded demo completions near the top, and show demo
  activity before the calculation explanation. The inspected Owner has one
  qualifying demo completion and zero genuine marketplace completions/reviews.
  Demo payments do not become genuine reputation, AI evidence or a fabricated score.
- Android GPS/address-return and Firebase delivery checks are recorded in
  `MAPS_AND_PUSH_NOTIFICATIONS_RESULT.md`. Local services still need a running PC
  and launcher; this work does not provide hosting.

Verification on 3 November: full API suite **627 passed, 3 existing opt-in skips**;
full Flutter suite **568 passed, 3 existing skips**. Focused photo/location/push
tests passed (80); admin/dot tests passed (39). The loyalty contract fixture now
includes its paginated points response and scopes scrolling to the content list,
so a fixture error does not dominate the page under the larger footer. Launcher
syntax, owned-process guards and Android service-retention decisions passed.
The configured Android debug build was rebuilt/installed using the normal launcher.
Main web build passed with existing Socket.IO Wasm/Cupertino-font warnings.
The separate administrator web build also passed, and final full Flutter analysis
reported no issues. After the account holder completed normal Auth0 sign-in, the
rebuilt Android app displayed the demo-history notice and one demo completion.
The Owner's listing dots switched from rows 1–20 of 21 to row 21 of 21, and back.
Opening the existing booking-request notification reached the correct completed
demo booking, and View agreement loaded its saved terms and charges. No new
booking, payment, review or dispute was created. Normal role switching and the
selected notification's read receipt are the expected UI writes. The phone was
returned to Owner Home with the services-only backend still ready. No credential
bypass or fabricated session was used. Administrator layouts remain widget/build
verified rather than a claim of Android administration testing.

Suggested commit message for this follow-up:

```text
fix(ui): restore listing photos and add accessible dot pagination

- resolve public upload references in listing cards and booking summaries
- retain photos attached through stored listing references
- share bounded page dots across renter, Owner and admin record lists
- explain demo trust history without changing genuine reputation
- retain local services after Android debug disconnection
- add a services-only launcher mode for the installed Android app
- verify GPS address autofill, Firebase delivery and protected photo access
- extend photo, paging, trust and launcher regression coverage
```

## 3 November 2026: uncluttered pagination controls

The 10/20/50 items-per-page selector now sits at the top right of each record
list in a shared outlined dropdown labelled **Show**. The record range remains
on its left. Bottom controls contain only page dots, Previous/Next and the page
label. Changing page size resets that collection to page one without changing
other collections or their filters.

Coverage includes Explore, renter/Owner bookings, Owner listings and rental
orders, conversations, notifications, reviews, reward history, saved lists,
administrator tables, expanded detail histories, saved rental-price references,
source lists and CSV previews. Existing server pagination and whole-file CSV
validation remain intact. Display-style controls retain their existing behavior.

Verification: **574 Flutter tests passed, 3 existing skips**; full analysis
reported no issues. Main and administrator web builds passed with the existing
Socket.IO Wasm/Cupertino-font warnings. Widget checks cover 360/390/1440-pixel
widths at 1.6 text scale, top-right placement, disabled loading controls,
collection isolation, local-list page reset and Explore filter preservation.
On Android, changing Owner listings from 20 to 10 items updated the range from
1–20 of 21 to 1–10 of 21 and changed the dots from two pages to three. The phone
subsequently locked normally; no account or marketplace record was changed.
The configured running app received the final Explore update by hot reload.
The final Android debug build also passed (existing Kotlin plugin migration
warning); this build-only check was not installed over the configured app.

Suggested commit message for this pagination polish:

```text
style(ui): move page-size controls into top-right dropdowns

- share a compact record-count and page-size toolbar across live lists
- keep bottom pagination focused on accessible page dots and navigation
- preserve collection filters and reset only the resized list to page one
- cover mobile text scaling, loading states and Explore paging in tests
```
