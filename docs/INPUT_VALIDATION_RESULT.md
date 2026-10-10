# RentHub input validation result

Implemented 10 October 2026. Scope: existing live renter/owner/admin screens, authentication, account dialogs, and retained prototype forms. No routes, authentication providers, persistence schemas, pricing algorithms, migrations, credentials or dependencies were changed.

## Implementation

- Shared Flutter contracts: `lib/core/validation/input_validation.dart` and `input_rules.dart`. `RentHubTextField` accepts formatters and length limits.
- Whole numbers, money (at most two fractional digits), and other decimals use separate full-edit formatters. Letters, mixed paste, exponent notation, multiple decimal points, excess precision and overlong numeric edits are rejected as a whole, preserving the last committed text and selection. Empty/trailing-dot edits are permitted while editing, not as final numeric submissions.
- Active IME composition is not rewritten; formatter instances are cached per controller across rebuilds. This follows [Flutter's formatter guidance](https://api.flutter.dev/flutter/services/TextInputFormatter-class.html).
- Text length checks validate without silently truncating a paste, particularly passwords. Passwords are never trimmed by validation or submission. OTPs, card suffixes and postcodes remain strings, including leading zeros.
- Names, addresses, product-model numbers and descriptions accept Unicode and punctuation. Control characters are rejected; no letters-only name/product rules were introduced. Length validation mirrors API Unicode code-point lengths; visible graphemes are not forcibly truncated.
- Malaysian mobile rules match the API: local 01 prefixes or +60/60 mobile prefixes, allowing spaces and hyphens, maximum 24 characters. Landlines and foreign numbers are invalid. Optional profile phone may be empty.
- Existing Form validators are composed with stronger shared checks, preserving existing error copy and stricter rules. Standalone fields are now TextFormFields. Errors appear after interaction/submission, with up to three wrapped lines. Disabled fields are skipped.
- Form/dialog submit guards run before business mutations/API calls. Cancel and filter Reset still work. Dialogs containing inputs wait for their route to unmount before disposing local controllers, avoiding disposed-controller crashes during exit animation.
- AI pricing validates only its profile fields and rental duration, not listing title/daily price/deposit. Brand and model are required for a comparable suggestion, but remain optional in the listing API contract. Catalog query limits (80 characters) are checked separately from manual brand/model limits (100/120).
- Filter min/max relationships and availability/promotional interval ordering are checked. Physical bookings retain existing same-calendar-day rental semantics; this work does not change timezone normalization or soft holds.
- Express shared `textInput`, `numericInput`, `wholeInput`, `moneyInput`, `malaysianMobile` validators run before trimming/coercing numbers. Malformed numeric strings, null/boolean/object values, nonfinite numbers, fractional integers and excess monetary precision are rejected. Money and integers also require safe numeric representation.
- Endpoint ranges remain authoritative. Optional omissions are preserved, but provided invalid values (including zero rental days) are not treated as omitted. Request/response shapes and authorization remain unchanged.

## Rule inventory

All editable text-input declarations were inspected, including controls emitted from address, policy/template and admin-rule loops. The per-field mapping follows this rule table. Optional means the corresponding UI context may omit/leave the field empty; required means required when rendered/applicable. Currency has no additional arbitrary maximum where the endpoint has none; its existing record-specific balance/claim checks still run in the service layer.

| Rule / label | Presence | Format | Length / exact digits | Numeric range |
| --- | --- | --- | --- | --- |
| `describeWhatHappened` — Describe what happened | Required when shown | text | 15–3000 | — |
| `review` — Review | Required when shown | text | 10–1500 | — |
| `details` — Details | Optional | text | 0–1000 | — |
| `writeAMessage` — Write a message | Optional | text | 0–2000 | — |
| `displayName` — Display name | Required when shown | text | 2–80 | — |
| `phoneNumber` — Phone number | Optional | phone | 1–24 | — |
| `reasonForLeaving` — Reason for leaving | Required when shown | text | 5–500 | — |
| `searchItemsVehiclesServices` — Search items, vehicles, services… | Optional | text | 0–100 | — |
| `searchPhysicalItems` — Search physical items | Optional | text | 0–100 | — |
| `searchConversations` — Search conversations | Optional | text | 0–100 | — |
| `searchRentalsAndServices` — Search rentals and services | Optional | text | 0–100 | — |
| `location` — Location | Optional | text | 0–100 | — |
| `minRm` — Min RM | Optional | money | 1–30 | 0–finite/safe representable |
| `maxRm` — Max RM | Optional | money | 1–30 | 0–finite/safe representable |
| `serviceVenue` — Service venue | Required when shown | text | 2–240 | — |
| `noteToOwnerOptional` — Note to Owner (optional) | Optional | text | 0–1000 | — |
| `cancellationReason` — Cancellation reason | Required when shown | text | 3–500 | — |
| `reasonForAdministratorReview` — Reason for administrator review | Required when shown | text | 5–500 | — |
| `title` — Title | Required when shown | text | 3–120 | — |
| `description` — Description | Optional | text | 0–3000 | — |
| `brandMaker` — Brand / maker | Optional | text | 0–100 | — |
| `productModel` — Product / model | Optional | text | 0–120 | — |
| `itemAgeYears` — Item age (years) | Required when shown | decimal | 1–30 | 0–100 |
| `typicalRentalDays` — Typical rental days | Required when shown | integer | 1–30 | 1–365 |
| `priceRm` — Price (RM) | Required when shown | money | 1–30 | 1–1000000 |
| `location2` — Location | Required when shown | text | 2–160 | — |
| `durationMinutes` — Duration (minutes) | Required when shown | integer | 1–30 | 15–10080 |
| `securityDepositRm` — Security deposit (RM) | Required when shown | money | 1–30 | 0–1000000 |
| `reasonOptional` — Reason (optional) | Optional | text | 0–120 | — |
| `minimumNoticeHours` — Minimum notice (hours) | Required when shown | integer | 1–30 | 0–8760 |
| `bufferHours` — Buffer (hours) | Required when shown | integer | 1–30 | 0–168 |
| `promotionLabel` — Promotion label | Required when shown | text | 2–80 | — |
| `discountPercentage` — Discount percentage | Required when shown | decimal | 1–30 | 5–80 |
| `bundleTitle` — Bundle title | Required when shown | text | 3–100 | — |
| `bundleDiscount` — Bundle discount (%) | Required when shown | decimal | 1–30 | 5–50 |
| `reason` — Reason | Required when shown | text | 3–500 | — |
| `referralCode` — Referral code | Required when shown | referral | 1–23 | — |
| `packageDetails` — Package details | Optional | text | 0–3000 | — |
| `duration` — Duration | Optional | integer | 1–30 | 15–10080 |
| `securityDepositRm2` — Security deposit (RM) | Optional | money | 1–30 | 0–1000000 |
| `dailyPriceRm` — Daily price (RM) | Optional | money | 1–30 | 1–1000000 |
| `reasonRequired` — Reason required | Required when shown | text | 5–500 | — |
| `describeTheIssue` — Describe the issue | Required when shown | text | 15–3000 | — |
| `claimAmountRm` — Claim amount (RM) | Required when shown | money | 1–30 | 0.01–finite/safe representable |
| `incidentDetails` — Incident details | Required when shown | text | 20–3000 | — |
| `ownerResponse` — Owner response | Required when shown | text | 5–2000 | — |
| `bundleName` — Bundle name | Required when shown | text | 3–100 | — |
| `venueOrServiceLocation` — Venue or service location | Required when shown | text | 2–240 | — |
| `eventRequirements` — Event requirements | Required when shown | text | 10–1000 | — |
| `brieflyExplainWhatYouWillUseTheItemFor` — Briefly explain what you will use the item for. | Optional | text | 0–1000 | — |
| `pickupDeliveryLocation` — Pickup/delivery location | Required when shown | text | 1–240 | — |
| `amountRequestedRm` — Amount requested (RM) | Required when shown | money | 1–30 | 0.01–finite/safe representable |
| `damageAndRepairDetails` — Damage and repair details | Required when shown | text | 20–3000 | — |
| `shortSummary` — Short summary | Required when shown | text | 5–160 | — |
| `whatHappened` — What happened? | Required when shown | text | 20–3000 | — |
| `addInformationOrAResponse` — Add information or a response | Required when shown | text | 5–2000 | — |
| `searchTitle` — Search \$title | Optional | text | 0–100 | — |
| `requiredReasonAuditNote` — Required reason / audit note | Required when shown | text | 5–500 | — |
| `prototypePlatformFee` — Prototype platform fee (%) | Required when shown | decimal | 1–30 | 0–20 |
| `successfulReferralPoints` — Successful referral points | Required when shown | integer | 1–30 | 0–10000 |
| `currentPassword` — Current password | Required when shown | password | 8–128 | — |
| `reviewedLicenceClassesEGDB2` — Reviewed licence classes (e.g. D, B2) | Required when shown | licenceClasses | 1–80 | — |
| `validUntilYyyyMmDd` — Valid until (YYYY-MM-DD) | Required when shown | date | 1–10 | — |
| `requiredReason` — Required reason | Required when shown | text | 5–500 | — |
| `rejectionReason` — Rejection reason | Required when shown | text | 5–500 | — |
| `amountRm` — Amount (RM) | Required when shown | money | 1–30 | 0.01–finite/safe representable |
| `requiredNote` — Required note | Required when shown | text | 5–2000 | — |
| `renterAmountRm` — Renter amount (RM) | Required when shown | money | 1–30 | 0–finite/safe representable |
| `ownerAmountRm` — Owner amount (RM) | Required when shown | money | 1–30 | 0–finite/safe representable |
| `decisionNotes` — Decision notes | Required when shown | text | 10–2000 | — |
| `approvedAmountRm` — Approved amount (RM) | Required when shown | money | 1–30 | 0–finite/safe representable |
| `decisionReason` — Decision reason | Required when shown | text | 5–1000 | — |
| `name` — Name | Required when shown | text | 3–120 | — |
| `requiredResolutionNote` — Required resolution note | Required when shown | text | 3–1000 | — |
| `moderationReason` — Moderation reason | Required when shown | text | 5–500 | — |
| `supportEmail` — Support email | Required when shown | email | 1–254 | — |
| `rewardOptionsPointsRm` — Reward options (points:RM) | Required when shown | rewards | 1–300 | — |
| `searchProfessionalServices` — Search professional services | Optional | text | 0–100 | — |
| `emailAddress` — Email Address | Required when shown | email | 1–254 | — |
| `sixDigitCode` — Six-digit code | Required when shown | digits | exactly 6 | — |
| `newPassword` — New Password | Required when shown | password | 8–128 | — |
| `confirmPassword` — Confirm Password | Required when shown | password | 8–128 | — |
| `email` — Email | Required when shown | email | 1–254 | — |
| `password` — Password | Required when shown | password | 8–128 | — |
| `fullName` — Full Name | Required when shown | text | 2–80 | — |
| `mobileNumber` — Mobile Number | Required when shown | phone | 1–24 | — |
| `fullName2` — Full name | Required when shown | text | 2–80 | — |
| `emailAddress2` — Email address | Required when shown | email | 1–254 | — |
| `primaryAddress` — Primary address | Optional | text | 0–240 | — |
| `howCanWeHelp` — How can we help? | Required when shown | text | 10–3000 | — |
| `malaysianAddress` — Malaysian address | Required when shown | text | 10–240 | — |
| `lastFourDigits` — Last four digits | Required when shown | digits | exactly 4 | — |

### Dynamic contracts

| Form fields | Presence | Format / length | Range or relationship |
| --- | --- | --- | --- |
| Address label | Required | Text, 1–40 | — |
| Address line | Required | Text, 1–120 | — |
| Address city/state | Required | Text, 1–80 | — |
| Malaysian postcode | Required | Five-digit string | Leading zeros retained |
| Report details | Optional except Other reason | Text, maximum 1000 | Other requires nonempty details |
| Admin booking/content policy | Required | Text, 10–3000 | — |
| Admin notification templates (bookingApproved, verificationUpdate, reportResolved) | Required | Text, 5–300 | — |
| Marketplace fee | Required | Decimal, maximum 30 input characters | 0–20% |
| High-value threshold | Required | Money, maximum 30 input characters | RM 0–1,000,000 |
| Report auto-hide threshold | Required | Whole number, maximum 30 input characters | 1–100 |
| OCR confidence threshold | Required | Whole number, maximum 30 input characters | 0–100 |
| AI manual-review threshold | Required | Decimal, maximum 30 input characters | 0–1 |
| Minimum verification age | Required | Whole number, maximum 30 input characters | 18–100 |
| Physical/service/referral points | Required | Whole number, maximum 30 input characters | 0–10,000 |
| Referral friend discount | Required | Money, maximum 30 input characters | RM 0–1000 |
| Structured reward options | Required | 1–10 unique points:RM pairs, maximum 300 characters | Points 1–100000; discount RM 0.01–10000 |
| Calendar/time selectors | Required where applicable | Real YYYY-MM-DD; HH:MM 00:00–23:59 | Unavailable/weekly/promotional intervals must end after start |
| Licence classes | Required for driving approval | Unique allowed A,A1,B,B1,B2,C,D,DA,E,E1,E2,F,G,H,I | Existing holder/validity confirmation and service policy unchanged |

### Screen-to-rule mapping

Paths below are relative to the Flutter `lib/` directory. Dynamic labels and shared renderers have their explicit contracts above/in their call sites rather than deriving formats from label text at runtime.

| Source | Editable field | Contract |
| --- | --- | --- |
| `features/account/account_management_pages.dart` | How can we help? | `howCanWeHelp` |
| `features/account/account_management_pages.dart` | Malaysian address | `malaysianAddress` |
| `features/account/account_management_pages.dart` | Last four digits | `lastFourDigits` |
| `features/account/account_pages.dart` | Full name | `fullName2` |
| `features/account/account_pages.dart` | Email address | `emailAddress2` |
| `features/account/account_pages.dart` | Phone number | `phoneNumber` |
| `features/account/account_pages.dart` | Primary address | `primaryAddress` |
| `modules/user/views/register_screen.dart` | Full Name | `fullName` |
| `modules/user/views/register_screen.dart` | Email Address | `emailAddress` |
| `modules/user/views/register_screen.dart` | Mobile Number | `mobileNumber` |
| `modules/user/views/register_screen.dart` | Password | `password` |
| `modules/user/views/login_screen.dart` | Email | `email` |
| `modules/user/views/login_screen.dart` | Password | `password` |
| `modules/user/views/forgot_password_screen.dart` | Email Address | `emailAddress` |
| `modules/user/views/forgot_password_screen.dart` | Six-digit code | `sixDigitCode` |
| `modules/user/views/forgot_password_screen.dart` | New Password | `newPassword` |
| `modules/user/views/forgot_password_screen.dart` | Confirm Password | `confirmPassword` |
| `features/renter/services/pages/service_search_results_page.dart` | Search professional services | `searchProfessionalServices` |
| `features/live/live_admin_app.dart` | Reviewed licence classes (e.g. D, B2) | `reviewedLicenceClassesEGDB2` |
| `features/live/live_admin_app.dart` | Valid until (YYYY-MM-DD) | `validUntilYyyyMmDd` |
| `features/live/live_admin_app.dart` | Required reason | `requiredReason` |
| `features/live/live_admin_app.dart` | Required reason | `requiredReason` |
| `features/live/live_admin_app.dart` | Rejection reason | `rejectionReason` |
| `features/live/live_admin_app.dart` | Amount (RM) | `amountRm` |
| `features/live/live_admin_app.dart` | Reason | `reason` |
| `features/live/live_admin_app.dart` | Required note | `requiredNote` |
| `features/live/live_admin_app.dart` | Renter amount (RM) | `renterAmountRm` |
| `features/live/live_admin_app.dart` | Owner amount (RM) | `ownerAmountRm` |
| `features/live/live_admin_app.dart` | Decision notes | `decisionNotes` |
| `features/live/live_admin_app.dart` | Approved amount (RM) | `approvedAmountRm` |
| `features/live/live_admin_app.dart` | Decision reason | `decisionReason` |
| `features/live/live_admin_app.dart` | Name | `name` |
| `features/live/live_admin_app.dart` | Required resolution note | `requiredResolutionNote` |
| `features/live/live_admin_app.dart` | Moderation reason | `moderationReason` |
| `features/live/live_admin_app.dart` | Support email | `supportEmail` |
| `features/live/live_admin_app.dart` | field.$1 | Address contracts below |
| `features/live/live_admin_app.dart` | Reward options (points:RM) | `rewardOptionsPointsRm` |
| `features/live/live_admin_app.dart` | controller | Admin rule contracts below |
| `features/admin/admin_app.dart` | Search $title | `searchTitle` |
| `features/admin/admin_app.dart` | Required reason / audit note | `requiredReasonAuditNote` |
| `features/admin/admin_app.dart` | Prototype platform fee (%) | `prototypePlatformFee` |
| `features/admin/admin_app.dart` | Successful referral points | `successfulReferralPoints` |
| `features/admin/admin_app.dart` | Current password | `currentPassword` |
| `features/live/live_dispute_page.dart` | Amount requested (RM) | `amountRequestedRm` |
| `features/live/live_dispute_page.dart` | Damage and repair details | `damageAndRepairDetails` |
| `features/live/live_dispute_page.dart` | Short summary | `shortSummary` |
| `features/live/live_dispute_page.dart` | What happened? | `whatHappened` |
| `features/live/live_dispute_page.dart` | Add information or a response | `addInformationOrAResponse` |
| `features/renter/booking/booking_flow.dart` | Briefly explain what you will use the item for. | Composed rule in source |
| `features/renter/booking/booking_flow.dart` | Pickup/delivery location | `pickupDeliveryLocation` |
| `features/renter/services/pages/service_booking_details_page.dart` | Venue or service location | `venueOrServiceLocation` |
| `features/renter/services/pages/service_booking_details_page.dart` | Event requirements | `eventRequirements` |
| `features/owner/owner_bundle_management_page.dart` | Bundle name | `bundleName` |
| `features/owner/owner_app.dart` | Title | `title` |
| `features/owner/owner_app.dart` | price | `priceRm` |
| `features/owner/owner_app.dart` | Location | `location2` |
| `features/owner/owner_app.dart` | Package details | `packageDetails` |
| `features/owner/owner_app.dart` | Duration | `duration` |
| `features/owner/owner_app.dart` | Security deposit (RM) | `securityDepositRm2` |
| `features/owner/owner_app.dart` | Daily price (RM) | `dailyPriceRm` |
| `features/owner/owner_app.dart` | Reason required | `reasonRequired` |
| `features/owner/owner_app.dart` | Describe the issue | `describeTheIssue` |
| `features/owner/owner_app.dart` | Claim amount (RM) | `claimAmountRm` |
| `features/owner/owner_app.dart` | Incident details | `incidentDetails` |
| `features/owner/owner_app.dart` | Owner response | `ownerResponse` |
| `features/live/live_loyalty_page.dart` | Referral code | `referralCode` |
| `features/live/live_owner_shell.dart` | Reason for administrator review | `reasonForAdministratorReview` |
| `features/live/live_owner_shell.dart` | Title | `title` |
| `features/live/live_owner_shell.dart` | Description | `description` |
| `features/live/live_owner_shell.dart` | brand | `brandMaker` |
| `features/live/live_owner_shell.dart` | productModel | `productModel` |
| `features/live/live_owner_shell.dart` | Item age (years) | `itemAgeYears` |
| `features/live/live_owner_shell.dart` | Typical rental days | `typicalRentalDays` |
| `features/live/live_owner_shell.dart` | price | `priceRm` |
| `features/live/live_owner_shell.dart` | Location | `location2` |
| `features/live/live_owner_shell.dart` | Duration (minutes) | `durationMinutes` |
| `features/live/live_owner_shell.dart` | Security deposit (RM) | `securityDepositRm` |
| `features/live/live_owner_shell.dart` | Reason (optional) | `reasonOptional` |
| `features/live/live_owner_shell.dart` | Minimum notice (hours) | `minimumNoticeHours` |
| `features/live/live_owner_shell.dart` | Buffer (hours) | `bufferHours` |
| `features/live/live_owner_shell.dart` | Promotion label | `promotionLabel` |
| `features/live/live_owner_shell.dart` | Discount percentage | `discountPercentage` |
| `features/live/live_owner_shell.dart` | Bundle title | `bundleTitle` |
| `features/live/live_owner_shell.dart` | Bundle discount (%) | `bundleDiscount` |
| `features/live/live_owner_shell.dart` | Reason | `reason` |
| `features/live/live_renter_shell.dart` | Search rentals and services | `searchRentalsAndServices` |
| `features/live/live_renter_shell.dart` | Location | `location` |
| `features/live/live_renter_shell.dart` | Min RM | `minRm` |
| `features/live/live_renter_shell.dart` | Max RM | `maxRm` |
| `features/live/live_renter_shell.dart` | details | Composed rule in source |
| `features/live/live_renter_shell.dart` | Service venue | `serviceVenue` |
| `features/live/live_renter_shell.dart` | Note to Owner (optional) | `noteToOwnerOptional` |
| `features/live/live_renter_shell.dart` | Cancellation reason | `cancellationReason` |
| `features/renter/renter_app.dart` | Search items, vehicles, services… | `searchItemsVehiclesServices` |
| `features/renter/renter_app.dart` | Search physical items | `searchPhysicalItems` |
| `features/renter/renter_app.dart` | Search conversations | `searchConversations` |
| `features/renter/renter_app.dart` | Write a message | `writeAMessage` |
| `features/renter/renter_app.dart` | Write a message | `writeAMessage` |
| `features/live/live_shared_pages.dart` | Details | `details` |
| `features/live/live_shared_pages.dart` | Write a message | `writeAMessage` |
| `features/live/live_shared_pages.dart` | Display name | `displayName` |
| `features/live/live_shared_pages.dart` | Phone number | `phoneNumber` |
| `features/live/live_shared_pages.dart` | field.$1 | Address contracts below |
| `features/live/live_shared_pages.dart` | Reason for leaving | `reasonForLeaving` |
| `features/live/live_review_page.dart` | Review | `review` |
| `features/renter/rentals/pages/raise_dispute_page.dart` | Describe what happened | `describeWhatHappened` |
| `features/renter/rentals/pages/rate_review_page.dart` | review | `review` |

## API coverage

Existing validators were extended in user, listing, catalog, booking, communication, dispute/claim, payment/refund, rental, review, loyalty and admin modules. These include authentication emails/passwords, string OTPs/postcodes, profile phones, amounts, integer pagination/ratings/points/hours/durations, AI pricing profile, ordered calendar and weekly intervals, percentages/probabilities, referral codes, licence classes and unique reward settings. Validation changes do not replace authorization, KYC eligibility, balances, expiry, evidence-upload requirements or other existing service-layer checks.

A JSON numeric token does not preserve its original source spelling after JSON parsing: the API cannot distinguish literal `100` from `1e2` once parsed as the same number. Exponent **strings** are rejected. Finite parsed numbers still undergo range, integer and money precision checks.

## Verification

- New Flutter unit/widget regression files: `test/input_validation_test.dart`, `test/input_validation_widget_test.dart`: **14 tests passed**.
- Full `flutter test --no-pub`: **174 passed, 2 opt-in MongoDB E2E tests skipped**.
- Application plus new tests analysis: `flutter analyze --no-pub lib test/input_validation_test.dart test/input_validation_widget_test.dart`: **no issues**.
- Full analyzer still reports two pre-existing undefined named parameters in `test/auth0_persistence_test.dart`: `latestLinkProvider` (line 41) and `mobileLinkPollInterval` (line 43). Auth0 code/tests were not changed to resolve these unrelated failures.
- `flutter build web --no-pub`: **passed**. Existing socket_io_common Wasm dry-run compatibility and Cupertino font warnings remain; standard JavaScript web build succeeds.
- New API validation-chain/request suite: `node --test test/input-validation.test.js`: **10 passed**. Production validators are mounted in an isolated Express request harness so malformed requests cannot reach its handler; no database writes or real authentication are needed.
- Full API suite with test-only process settings: **170 passed, 3 opt-in live catalog/pricing E2E tests skipped**, zero failures.
- Automated actual-screen interaction/error-layout checks: registration and claim dialogs at 360px; filters, listing/pricing and addresses at 390px; suspension dialogs at 1024px and 1440px. Invalid input remains present, dialogs remain open, and recording clients confirm no API call. Valid address persists `01000` as a string; pricing receives age 3.5 and whole duration without requiring daily price.
- Formatter tests cover paste/typing rejection, deletion, decimals/precision, selection, committed/composing values, leading zeros and boundaries. Validator tests cover emails, Malaysian phones, 8–128 passwords/matching confirmation, dates/times, Unicode, referral, licence classes and rewards. Registration additionally confirms overlong pasted passwords are not truncated.
- `git diff --check`: passed.

### Re-run safely

From `apps/renthub_flutter`:

```powershell
flutter test --no-pub
flutter analyze --no-pub lib test/input_validation_test.dart test/input_validation_widget_test.dart
flutter build web --no-pub
```

From `services/api`, use test-process overrides so a configured Auth0/cloud provider does not interfere with mock-auth integration fixtures. These assignments do not edit `.env`; open a fresh terminal afterward for normal development.

```powershell
$env:AUTH_MODE = 'mock'
$env:STORAGE_MODE = 'local'
$env:FCM_MODE = 'disabled'
$env:BLOCKCHAIN_MODE = 'disabled'
$env:EMAIL_MODE = 'disabled'
npm.cmd test
```

## Remaining limitations / handoff

- Real Android keyboards, device-specific IMEs and a live browser visual walkthrough were not exercised in this environment; composition and width behavior were tested through Flutter's test framework.
- Opt-in live MongoDB/provider E2E checks were not enabled and private services were not contacted.
- The existing registration contract still sends name/email/password/role; phone persistence remains the existing profile-update workflow. This change validates the registration contact field without expanding its wire payload.
- Legacy prototype actions remain mock actions; validation does not turn them into live features.
- Fix the two unrelated Auth0 test/analyzer parameter mismatches separately if a completely green repository-wide analyzer is required.
- Restart/rebuild Flutter and restart Express to load the changes. No migration, bulk cleanup, seed or new credential setup is needed.

Suggested commit: `feat(validation): enforce consistent RentHub form and API input contracts`
