# Listing preview, rental dates and checkout design

Updated 5 November 2026. Changes apply to the live Flutter listing-detail and
checkout screens. Existing uncommitted work is preserved.

## Owner viewing their own listing

- Match the signed-in controller account ID to the listing's Owner ID; do not
  infer ownership from a display name or the currently selected role.
- Show **Your listing**, an Owner-preview notice, example rental charges where
  applicable, photos, product details, availability and reviews.
- Hide the rental/service booking form, agreement acceptance, payment estimate,
  checkout action, wishlist and self-report/block actions. Do not preload the
  date picker, log a self-view or request complementary-item recommendations.
- Keep a **Back to Explore** action and guidance to switch to Owner for editing
  or managing requests. Opening the preview does not change the active role.
- Empty-review copy no longer invites an Owner to book/review their own item.
  The existing API self-booking prohibition remains authoritative; the local
  submit action also guards ownership.
- Service previews retain the physical/service distinction: no item condition,
  physical deposit or delivery-fee summary is shown for services.

## Date selection

The end-date picker now validates the entire inclusive rental range from the
selected start. Dates before the start, unavailable dates, and otherwise-free
dates beyond an intervening unavailable day cannot be selected.

The start picker still permits a later available period. Changing the start
resets an incompatible end to the new start, rather than leaving a range that
crosses a blackout. End-date selection requires an available start date. A fully
blocked calendar displays guidance instead of passing an invalid initial date to
Flutter's picker. Calendar bounds use today's Malaysian date and the existing
two-year horizon.

Existing confirmed availability data is reused; pending requests remain soft
holds. The existing pre-submit availability recheck and server validation remain
in place. No booking status or server availability policy changed.

## Checkout dialog

- White, rounded dialog with payment-method icon and a readable blue total panel.
- One full-width **Complete demo payment** action, followed by **Cancel** and
  **Simulate decline** side by side.
- Actions stay in the dialog footer while explanatory content can scroll. Large
  text no longer pushes the secondary controls outside the tappable area.
- Card, FPX and Wallet simulation outcomes, session checks, server-controlled
  amounts, idempotency and Owner approval rules remain unchanged.

## Verification

- Formatting and Flutter analysis: passed, no issues.
- Full Flutter suite: **585 passed, 3 existing opt-in tests skipped** (two live
  MongoDB E2E phases and one screenshot capture). No live E2E writes were enabled.
- Added regression tests for physical/service Owner previews, no self-view writes,
  end-date range boundaries, starting after a blackout, resetting the end date,
  fully unavailable calendars, and checkout button positioning/reachability.
- Layout checks cover 360/390-pixel mobile and 1024-pixel desktop widths with
  150% text. Existing checkout tests continue to cover success, decline, cancel,
  session changes, uncertain responses and agreement access.
- Separate mocked visual renders at 360/390 pixels with 130% text passed and were
  inspected. Private captures/logs are in
  `apps/renthub_flutter/.data/ui-design-checks/` and are Git-ignored.
- Web build and Android debug APK build: passed. Existing non-blocking dependency
  notices remain: Socket.io Wasm dry-run compatibility, missing Cupertino font
  family notice, and Firebase/shared-preferences Kotlin migration warnings. No
  unrelated dependency or platform configuration was changed.
- `git diff --check`: passed. No account, listing, booking or payment records were
  changed during this UI task. No device installation or real-payment test was
  performed; restart/hot-reload Flutter to view the new screens.

## Commit message

```text
fix(ui): distinguish own listings and improve booking date checkout controls

Show an Owner preview without self-booking actions, prevent end dates from
crossing unavailable ranges, and reset incompatible date selections.
Redesign demo checkout with a clear total and pinned responsive actions.
Cover ownership, range boundaries and accessible mobile/desktop layouts.
```
