# UI Implementation Batch 2 Proposal

## Scope and approval boundary

Batch 2 proposes the complete renter physical-item discovery-to-pending-request journey. It contains eight closely related mobile screens because the Stitch inventory includes a dedicated pre-agreement booking-details screen.

This document is a proposal only. No Batch 2 Flutter source, model, repository, controller, mock-data, or test implementation has been made. Stitch was read only and was not modified.

## Stitch verification

Stitch project `2362719991600770029` was resolved through `list_projects`. The project inventory in `STITCH_UI_COMPARISON.md` was checked rather than relying on the failing `list_screens` endpoint. A fresh Stitch MCP `get_screen` call was made for every selected screen ID below.

The inventory confirms `Physical Item Booking Details` (`237d562602b24265816651a0c8c914c0`). It is labelled Step 1 of 3 and appears before `Rental Agreement Review` (Step 2) and `Simulated Payment` (Step 3). It is therefore included as the authoritative place for date, fulfilment, location, availability, deposit, and price selection.

## Selected screens

| Screen | Stitch ID | Existing Flutter mapping |
| --- | --- | --- |
| RentHub Home | `b8415964ef6b47c7af179b73751f17dd` | `lib/features/renter/renter_app.dart` — `RenterHome`; partial discovery UI. |
| Search Results | `6b11258ef8b8401b991a3a6770b344fe` | `lib/features/renter/renter_app.dart` — `ExplorePage`; search and verified-only filtering exist, advanced filters are incomplete. |
| Item Details | `1e621b4492184f30b453262fe903a62f` | `lib/features/renter/renter_app.dart` — `ListingDetailsPage`; physical-item detail content and booking entry exist. |
| Physical Item Booking Details | `237d562602b24265816651a0c8c914c0` | `lib/features/renter/renter_app.dart` — physical branch of `BookingFlowPage`; current date fields are inactive and fulfilment/price validation is incomplete. |
| Rental Agreement Review | `0d4d14f752c543c1933ef94f7a78efc7` | `lib/features/renter/renter_app.dart` — current review step; no dedicated agreement screen or acceptance gate. |
| Simulated Payment | `c24c80dc4aa446c0a1ca8b919be2d9a7` | `lib/features/renter/renter_app.dart` — current review/payment step and `PaymentResultPage`; currently too simplified. Existing prototype payment classes are under `lib/modules/payment/`. |
| Booking Request Submitted | `f373c9b4e78d442495d561e449102561` | `lib/features/renter/renter_app.dart` — `PaymentResultPage`; current copy says payment succeeded and does not create a booking. |
| My Bookings | `42e8f4e0ceba4d74a1689a57bf87c60c` | `lib/features/renter/renter_app.dart` — `BookingsPage`; static cards exist without a real Pending tab data flow. |

Excluded from this batch are Wishlist, Compare Items, services, cancellation, active-rental tracking, extension, return evidence, reviews, and disputes. They are separate journeys and would dilute the state and navigation work required for a reliable physical-item request flow.

## Authoritative visual and interaction mapping

### 1. RentHub Home

- Preserve the Stitch location header, RentHub mark, notifications action, discovery headline, search field, category row, recommended items, service teaser, and five-destination renter navigation.
- Cards open Item Details. Search and category actions open Search Results with the chosen query/category already applied.
- Reuse current `RenterShell`, `RenterHome`, `RentHubLogo`, `ListingCard`, `MockData.listings`, and native `NavigationBar`.
- Required states: loading skeletons, empty recommendations, retryable load error, and normal content.

### 2. Search Results

- Match the Stitch search header, query field, result count, reset action, filter chips, compact result rows/cards, and Explore-active bottom navigation context.
- Filters must be functional for category/type, location, price, availability, and verified Owner. Physical item is the selected type for this batch.
- Filter state stays in the existing Explore page state or a route-scoped presentation controller. Returning from Item Details must not clear the query, filter values, or scroll position.
- Required states: loading, no results with clear-filter action, retryable error, and populated results.

### 3. Item Details

- Match the Stitch image area, title, price per day, location, rating/reviews, verified Owner and trust cues, condition, equipment/accessory information, availability/rental-policy/fulfilment/deposit sections, and fixed `Book Now` action.
- Reuse `Listing`, `MockData.listings`, `ListingDetailsPage`, `StatusBadge`, `confirmAction`, and the current report/block confirmation behavior.
- `Book Now` opens Physical Item Booking Details with the same listing and a single route-scoped booking draft. No booking is created at this point.
- Required states: loading, listing unavailable/inactive, retryable error, and normal detail.

### 4. Physical Item Booking Details — Step 1 of 3

This dedicated Stitch screen is the explicit pre-agreement selection surface required by the amended scope.

- Rental start and end dates: use native `showDateRangePicker` or two native date selectors. End date must be on or after the valid minimum rental end and both fields remain visible after selection.
- Availability validation: validate the entire inclusive range against local mock unavailable dates before enabling `Review Agreement`. Show the unavailable date/range in text and keep the user on this screen when invalid.
- Pickup or delivery: use the Stitch segmented selection. Options shown must come from the listing's mock fulfilment policy.
- Pickup/delivery location: show the Owner pickup location for pickup; show a selectable saved renter address or validated local address field for delivery. The label and help text change with the method.
- Quantity: show a native stepper only when the listing's UI policy supports more than one rentable unit. Single-unit items display `Quantity 1` read-only so price calculations remain explicit without inventing stock.
- Deposit and totals: show daily rate × rental days × quantity as rental subtotal, optional damage-waiver line, refundable deposit, and total due/authorized. Use Malaysian Ringgit with two decimals.
- Preserve the Stitch rental-purpose field as optional prototype context; it must not replace any existing booking business field.
- `Review Agreement` is disabled until required values are present and availability passes. `Save Draft` may preserve route-local state only and must not create a booking.
- Required states: pristine, validating, available, unavailable, invalid end date, field error, and ready-to-review.

### 5. Rental Agreement Review — Step 2 of 3

- Show the selected item, exact dates/duration, quantity when applicable, Owner/renter parties, fulfilment method/location, deposit, subtotal, and total from the same booking draft.
- Use the Stitch required acceptance checkbox. `Proceed to Demo Payment` remains disabled until the renter accepts the agreement.
- Back returns to Booking Details without losing dates, fulfilment, location, quantity, availability result, or calculated totals.
- No booking, payment, confirmation, or status transition occurs here.
- Required states: unchecked/disabled, checked/enabled, validation mismatch, and retryable draft error.

### 6. Simulated Payment — Step 3 of 3

- This is a **prototype-only simulated authorization**, not a real charge or captured payment. The screen must visibly say that no card, bank account, FPX session, or external payment service is contacted.
- Reuse `PaymentController` and `MockPaymentRepository` if practical, scoped to the flow and kept fully local. Do not add a live gateway, secret, SDK, network call, or real payment behavior.
- Present the same item/dates and price breakdown from the draft. Demo Card and Mock FPX remain presentation choices only.
- States: ready, processing, simulated authorization success, simulated failure, and retry. Disable repeated submission while processing.
- A successful demo authorization permits one call to `BookingController.create`. Guard the flow with the resulting booking ID/submission state so a retry or double tap cannot create a duplicate request.
- The authorization result may be described as `Simulated authorization held for demo`; it must not label the booking Paid, Confirmed, Approved, or Active.

### 7. Booking Request Submitted

- The created booking must have status `pending`, consistent with `MockBookingRepository.create`.
- Match the Stitch pending-owner-approval presentation, request reference, dates/duration, fulfilment, total, and progress/status explanation.
- Required copy: the Owner still needs to approve; no real payment occurred; the demo authorization is not a captured payment.
- `View in My Bookings` navigates to the renter shell's Bookings destination with the Pending tab selected. `Return Home` returns to Home without creating another request.
- Back/re-entry must reuse the existing submitted booking ID and never call create again.

### 8. My Bookings

- Match the Stitch Pending, Active, Completed, and Cancelled tabs and the five-destination renter navigation with Bookings active.
- The newest `BookingController.latest` record is merged into the displayed booking view by ID and appears first under Pending immediately after submission.
- Pending cards state `Awaiting Owner approval`; they must not show Active, Confirmed, Paid, collection/return controls, or rental tracking.
- Existing mock bookings remain consistent and are grouped by their existing statuses. An empty tab uses the shared empty state.
- Required states: loading, per-tab empty, retryable error, and populated tabs.

## Booking draft, availability, and price rules

Implementation should add presentation-layer flow state rather than reshaping backend/domain models for visual convenience. A small route-scoped `BookingDraft`/controller may hold:

- listing ID and immutable listing reference;
- start date, end date, inclusive rental-day count;
- pickup/delivery method and selected location;
- quantity and listing-specific maximum quantity;
- daily rate, rental subtotal, optional damage waiver, refundable deposit, and total;
- availability state and validation message;
- agreement accepted flag;
- demo authorization state; and
- created booking ID/submission guard.

Mock availability and fulfilment policy should live in the central mock-data layer keyed by the existing listing ID. It may include unavailable date ranges, pickup address, delivery availability/fee, deposit, waiver price, and maximum quantity. Existing backend services, `Listing`, `Booking`, authentication, and repository contracts remain authoritative and are not replaced.

Calculation rules must be centralized so Booking Details, Agreement, Payment, Submitted, and My Bookings cannot display different amounts. At minimum:

```text
rental days = inclusive calendar-day span
rental subtotal = daily rate × rental days × quantity
total authorization = rental subtotal + selected extras + refundable deposit
```

## Routes and navigation

Continue using the repository's `Navigator`/`MaterialPageRoute` convention; do not introduce a second router.

```text
RenterShell / Home
├─ Search or category → Search Results
│  └─ Result → Item Details
└─ Recommended item → Item Details
   └─ Book Now → Booking Details (Step 1)
      └─ Review Agreement → Agreement (Step 2)
         └─ accepted → Simulated Authorization (Step 3)
            └─ one Pending booking created → Request Submitted
               ├─ View in My Bookings → RenterShell / Bookings / Pending
               └─ Return Home → RenterShell / Home
```

- `Navigator.pop` from Item Details restores Search Results with its filters and scroll state.
- `Navigator.pop` from Agreement restores the same Booking Details route and draft.
- The shell should expose a small callback or equivalent existing-state mechanism to select Home or Bookings; do not push a duplicate `RenterShell`.
- Successful submission replaces the payment route so device Back cannot repeat authorization or booking creation.
- Deep links are outside this batch; named routes are not required.

## Flutter files to reuse, update, or add after approval

### Reuse and update

| File | Proposed Batch 2 responsibility |
| --- | --- |
| `lib/features/renter/renter_app.dart` | Preserve the shell and current logic while splitting/refining Home, Explore, Item Details, booking steps, result, and Bookings as needed. |
| `lib/shared/widgets/renthub_components.dart` | Reuse `RentHubLogo`, `ListingCard`, `StatusBadge`, confirmations, and feedback; extend without duplicating styles. |
| `lib/shared/widgets/account_components.dart` | Reuse the shared buttons, form patterns, cards, app bars, and loading/empty/error/success states created in Batch 1. |
| `lib/core/theme/app_theme.dart` | Keep the RentHub blue colour tokens, typography, radii, field, card, button, and navigation styling authoritative. |
| `lib/shared/mock_data/mock_data.dart` | Add consistent local availability/fulfilment/booking-view policy keyed by existing IDs; do not replace existing records. |
| `lib/shared/models/domain_models.dart` | Preserve `Listing` and `Booking`; avoid changes unless an approved implementation proves a small backward-compatible field necessary. |
| `lib/modules/booking/controllers/booking_controller.dart` | Reuse `create`/`latest` and loading/error behavior; make one guarded create call after simulated authorization. |
| `lib/modules/booking/repositories/booking_repository.dart` | Preserve the contract and `pending` result from `MockBookingRepository`; no backend integration. |
| `lib/modules/payment/controllers/payment_controller.dart` | Reuse for local simulated authorization if practical. |
| `lib/modules/payment/repositories/payment_repository.dart` | Keep `MockPaymentRepository`; never add or call a real payment provider. |

### Likely presentation files after approval

Exact names may follow the existing feature structure, but the intended separation is:

```text
lib/features/renter/booking/
  booking_draft.dart
  booking_details_page.dart
  agreement_review_page.dart
  simulated_payment_page.dart
  request_submitted_page.dart
  booking_price_breakdown.dart
  booking_availability.dart
lib/features/renter/discovery/
  renter_home_page.dart
  search_results_page.dart
  item_details_page.dart
```

This split is optional if smaller extracted widgets keep `renter_app.dart` readable. No new state-management or payment dependency is required.

## Reusable components required

- RentHub colour theme: existing `AppColors` only; blue guides actions, while warning/success/error colours retain semantic meaning.
- Typography: existing centralized Material 3 text theme, responsive wrapping, and no network font.
- Buttons: shared primary, secondary, outline, text, destructive, loading, and disabled variants with 48-pixel touch targets.
- Form fields: shared labelled fields plus native date range, location selector, segmented fulfilment control, and conditional quantity stepper.
- Cards: listing card/row, booking summary card, price/deposit summary, Owner trust card, agreement section, and pending booking card.
- App bars: branded Home header and shared back/step app bars.
- Bottom navigation: existing five-destination renter navigation; Home, Explore, and Bookings selected states remain consistent.
- Feedback: shared loading, empty, error, and success widgets; add inline validation and payment-processing states rather than duplicating whole-screen styles.
- Status badges: `Pending` uses text/icon plus warning colour; demo authorization uses explicit prototype wording and is not a booking status.

All UI will use native Flutter widgets. Stitch HTML/CSS is a visual reference only.

## Business-logic and integration boundaries

- Preserve `AuthController`, `ListingController`, `BookingController`, repositories, dependency injection, domain models, and role-shell selection.
- The existing `MockBookingRepository` remains the booking creator and returns `pending`.
- Do not mark a submitted request Active, Confirmed, Approved, or Paid. Owner approval is a later journey.
- The simulated payment represents only a local demo authorization. It does not capture funds, create a real transaction, or contact any service.
- Do not modify Stitch designs or add production/network dependencies.
- Physical-only fields remain confined to this journey; service scheduling must not inherit condition, deposit, delivery, or return controls.

## Implementation order after approval

1. Add route-scoped booking draft, centralized pricing, mock availability policy, and deterministic test fixtures.
2. Refine shared responsive listing rows, filters, booking summary, date/fulfilment/location controls, price breakdown, and feedback states.
3. Implement Home and Search Results while preserving search/filter/scroll state.
4. Implement Item Details and pass the selected physical listing into one booking draft.
5. Implement Physical Item Booking Details with date, availability, fulfilment, location, conditional quantity, deposit, subtotal, and total validation.
6. Implement Agreement Review with acceptance gating and state-preserving back navigation.
7. Implement prototype-only simulated authorization, retry handling, and exactly-once Pending booking creation.
8. Implement Request Submitted and route it to My Bookings with Pending selected and the latest record first.
9. Run formatting, analysis, all tests, web build, and 360/390 visual and interaction checks against all eight Stitch references.

## Required tests after approval

The Batch 2 implementation is not complete until these tests exist and pass:

1. Back navigation from Item Details retains Search Results query, filters, and scroll state; back from Agreement retains selected dates and all booking fields.
2. A range overlapping a mocked unavailable date is rejected and cannot continue.
3. An end date before the allowed end/start relationship shows an inline error and cannot continue.
4. Agreement acceptance gates the payment action; unchecked is disabled and checked is enabled.
5. A simulated payment failure can retry, and retry/double tap results in exactly one booking-repository create call and one booking ID.
6. Booking Request Submitted and `BookingController.latest` remain `pending` after submission.
7. `View in My Bookings` navigates from Request Submitted to the Bookings destination with Pending selected.
8. The latest created booking appears first under the Pending tab and not under Active/Completed/Cancelled.

Additional verification:

- Price calculations stay identical across Booking Details, Agreement, Payment, Submitted, and My Bookings.
- Pickup/delivery changes the visible location control and retains the appropriate value when navigating back.
- Quantity is absent or read-only for single-unit listings and bounded for multi-unit listings.
- Processing disables duplicate actions; error and retry states remain visible and accessible.
- All eight screens render without overflow at 360 x 800 and 390 x 844, including keyboard insets and increased text scale.
- Every primary card, filter, tab, back action, CTA, and bottom-navigation destination is functional or explicitly disabled.
- `dart format .`, `flutter analyze`, `flutter test`, `flutter build web`, and `git diff --check` pass.

## Approval requested

Approve these eight screens and the pending-request semantics before any Batch 2 implementation. In particular, approval confirms the dedicated Physical Item Booking Details page, prototype-only simulated authorization, exactly-once booking creation, and Pending status until Owner approval.
