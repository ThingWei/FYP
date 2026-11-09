# Administrator usability, record details and pagination

9 November follow-up: [monthly demo payout bars and booking-status pie charts](BOOKING_EXPIRY_LOCATIONS_AND_INSIGHTS_RESULT.md), including current verification results and simulation limits.

Updated: 28 October 2026 (Malaysia).

## Implemented

- Retained the ten administrator navigation destinations and existing permissions.
- Added a shared desktop table and narrow-screen cards. Tables occupy the available content width within a centered 1,480-pixel container. Status badges, consistent rows and a readable pagination footer replace the narrow left-aligned layout.
- Added primary-label and **View details** actions, with a scrollable centered dialog or full-screen dialog on narrow screens. Opening details is read-only. Existing approval, rejection, suspension, refund, report and dispute actions retain their server checks and confirmations.
- Added server pagination, search and applicable status filters. Each collection remembers its own search, filters, page and page size. The UI defaults to 20 rows, with 10/20/50 choices. Filters run before counts and pagination; sorting is stable by creation time and identifier.
- Added page-generation/account guards, retained successful results during refresh errors, and nearest-valid-page recovery. Section failures do not prevent opening other sections.
- Replaced the initial multi-collection load with dashboard totals and lazy section loading. List responses use small summary projections; full details load on demand. Related account names are fetched in one batch per page instead of one query per row. Closing a read-only dialog does not reload its table.
- Added database-derived dashboard totals, rather than totals calculated from a loaded page.

## Record coverage

| Record | List and detail support |
| --- | --- |
| Users | Name, contact details, roles, account and verification status; current account names distinguished from recorded participant snapshots |
| Verification | All submitted/reviewed MyKad/licence records, current-status/document filters, protected document viewers, decisions and history |
| Listings | Product/service details, photos, price and moderation actions |
| Bookings | Recorded participants, calendar/service dates, saved charges, payment status, notes and agreement access |
| Rentals | Booking snapshot names, handover/return records, extension history and agreement access |
| Transactions | MYR amounts, payment method, recorded reason, status and explicit demonstration-payment label; existing refund guards |
| Disputes | Participants, reason, evidence/replies, decisions and held-fund allocations; existing case/settlement actions |
| Claims | Requested/approved amounts, evidence, decision, funding status and reason |
| Safety reports | User/listing/review target, reporter, reason, details and recorded resolution |
| Message reports | Reported message text, reason, reporter and resolution |
| Reviews | Participants, listing, rating dimensions, review text and moderation reason |
| Audit logs | Friendly activity descriptions, supporting references and allowlisted business metadata |
| Generated reports | Type, reporting period, file information, row count and download |
| Report schedules | Frequency, period, enabled state, next/last run and confirmed controls |
| Referrals | Account names, code, status, dates and recorded reward |
| Reward history | Account, points, balance, description and saved reward details |
| Rental-price references | Product, advertised amount/period, source, checked date, status, package notes and source link |

Missing or deleted historical data remains explicitly unavailable; no replacement names, transaction history or decisions are fabricated. Optional contact fields use “Not provided”. Names taken from current account records are labelled as current, rather than historical snapshots.

## Users ↔ Listings switching correction

The shared table State previously survived a change of record type. It retained the Users page state while building a Listings table, so fields such as `title` were missing and appeared as “Not available”. The cached state could also remain marked as loading when an in-flight request's widget was disposed.

The final correction:

1. Gives live tables a record-type key and explicitly rebinds reusable tables in `didUpdateWidget`.
2. Keeps each type's cached page separate; switching does not reinterpret one type's rows as another.
3. Invalidates old request generations and cancels pending search timers when leaving/rebinding a table.
4. Releases interrupted loading flags without deleting successful cached rows.
5. Records the successful data revision so cached pages refresh after relevant administrator actions.
6. Captures the requested type/account and ignores late responses after navigation or account changes.

Regression tests pass for repeated switches with type-specific response fields and switching away during a delayed Users request.

## Verification browsing and detail redesign

Verification previously applied a pending-only database filter. There were no pending submissions, which hid the reviewed records. It now defaults to all submitted records; status and document filters apply before pagination/counting. Eight existing verification records are retrievable. Historical attempts remain available without making an old pending/rejected attempt override a later decision, and an explicitly reset current status is not falsely shown as approved. Unsubmitted accounts are excluded. Only current pending attempts offer review actions; approval checks remain authoritative on the API.

The shared detail window now uses:

- A white background with no tinted dialog surface, a compact coloured status badge and clear title.
- Grouped information cards with two columns on desktop and one column on mobile.
- Separate account details, verification status, amounts, schedule and decisions, as applicable.
- Larger protected document previews in an expandable section, loaded only when opened from Users; verification reviews open the document section immediately.
- Expandable history and supporting record information, keeping database references out of the primary content.
- A content-sized desktop dialog with a bounded scroll area and consistent footer; a full-screen mobile layout.
- No pagination controls underneath a single history entry. Long histories and CSV error lists retain pagination.

Readability, keyboard access, switching, protected-image lazy loading, approved-record browsing and pending-only filters are covered by widget/API regressions. Private screenshots supplied in the conversation were not added as fixtures or training data.

## Settings and plain language

- Centered settings within a 1,120-pixel readable layout, using grouped white cards and clear labels.
- Removed Passport from active administrator document choices, settings writes and new verification/capture submissions. Existing Passport history remains readable; stored approvals are not revoked or migrated.
- Requirements display MyKad for marketplace access and driving-licence approval for vehicle renters. These mandatory rules are shown as requirements rather than editable optional checkboxes.
- Reward editing now has individual **Points needed** and **Discount (RM)** fields, Add/Remove controls, unique-point validation and the existing API bounds. Administrators no longer enter `500:5, 1000:10` syntax.
- Manual-review thresholds display as a percentage and convert back to the existing 0–1 API value when saved. Password/authentication behaviour is unchanged.
- Event times display in Malaysia time, e.g. **28 Oct 2026, 2:30 pm**. Physical rental calendar dates retain their original day, e.g. **28 Oct 2026**. Invalid/missing dates are not guessed.
- Known statuses, report reasons and audit actions use readable labels. Unknown audit actions have a safe general description instead of raw metadata dumps.

## System status and rental-price references

System status shows data storage, photos/documents, AI assistance, rental records and scheduled tasks. The configuration-only sign-in and notification cards are removed. The overall display reflects these operational checks, including partial failures, disabled services and the demonstration rental-record network. Refresh is read-only; running scheduled tasks is a separate confirmed operation.

Rental-price references now starts with the paginated saved-price table. Source controls are **Update now**, **Turn on** and **Turn off**. Technical category-evidence/completeness panels are removed from this UI; development tools and source policies remain unchanged. CSV tools are under **Import prices from a file**, with paginated rows/errors, whole-file validation and explicit import confirmation. Advertised prices remain clearly distinct from completed RentHub rentals.

## API interfaces and privacy

- `GET /api/v1/admin/dashboard-summary`
- `GET /api/v1/admin/records/:type?page=1&limit=20&search=...&status=...`
- `GET /api/v1/admin/records/:type/:id`
- Existing generated-report/schedule list endpoints also accept optional pagination; callers omitting pagination keep their existing response behaviour.
- Existing pricing-reference list supports a validated page size; paths and payload shapes are retained.

All new routes require an authenticated administrator. An explicit 17-type model registry and approved field projections prevent arbitrary collection access. User records resolve their database identifier or account identifier; other records support their valid public/database references. Credentials, identity fingerprints, raw IC/OCR text, report-file contents and internal diagnostics are excluded. Protected images continue to require the existing upload access checks. Rental display names come from saved booking snapshots rather than silently substituting today's profile.

The API and launcher advertise/check `admin-record-details-v1`, preventing reuse of a stale API lacking these endpoints.

## Read-only database verification

A bounded read-only inspection opened all existing records in the supported collections. No database mutations, source enablement, model deployment or historical cleanup was performed.

| Type | Records opened | Failures |
| --- | ---: | ---: |
| Users | 16 | 0 |
| Verification records (including reviewed) | 8 | 0 |
| Listings | 27 | 0 |
| Bookings | 25 | 0 |
| Rentals | 9 | 0 |
| Transactions | 25 | 0 |
| Disputes | 3 | 0 |
| Claims | 2 | 0 |
| Safety reports | 1 | 0 |
| Message reports | 1 | 0 |
| Reviews | 2 | 0 |
| Audit logs | 128 | 0 |
| Generated reports | 2 | 0 |
| Schedules | 1 | 0 |
| Referrals | 4 | 0 |
| Reward history | 3 | 0 |
| Price references | 335 | 0 |
| **Total record lookups** | **592** | **0** |

Verification currently has zero pending requests: the records include three approved, four rejected and one requiring resubmission. The eight reviewed/history records were hidden by the old pending-only view; no submissions were fabricated. All 16 stored users had display names. The reported disappearance was a table lifecycle/display issue, not missing user records. These are counts at inspection time, not permanently fixed platform totals.

## Verification status

Completed verification of the current implementation:

- API: **591 passed, 3 skipped** (594 total).
- AI: **606 passed**, four existing dependency warnings.
- Flutter: **531 passed, 3 skipped**; the optional capture-enabled run also passed.
- Flutter analysis: **no issues**.
- Launcher regression/integration test: **passed**.
- Administrator web, main web and Android debug builds: **passed**.
- JavaScript syntax checks, OpenAPI YAML parse and `git diff --check`: **passed**.
- Widget layouts: **360/390/1024/1440 pixels**, including larger text, section switching, record dialogs and verification filters. Desktop/mobile screenshots were inspected.

The earlier automatic-review usage-limit interruption was resolved. Final tests and builds were subsequently executed successfully, including the Users/Listings lifecycle correction and the verification/detail redesign.

To repeat the Flutter checks:

```powershell
cd C:\Users\weith\FYP\apps\renthub_flutter
flutter analyze
flutter test
flutter build web -t lib/main_admin.dart --output build/admin_web
flutter build web
flutter build apk --debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File test/run_renthub_launcher_test.ps1 -Integration
```

Run the API suite using the repository's isolated test environment/MongoMemoryServer configuration. Do not point integration tests at the live development database.

Remaining manual checks: restart/hot-restart the running Windows app, switch Users → Listings → Users repeatedly, open real detail records, verify keyboard focus and the protected photo/agreement viewers, then repeat at narrow width. Standard web builds still emit the existing Socket.IO WebAssembly dry-run and Cupertino-font warnings; JavaScript web builds succeed. Android builds also emit existing plugin Kotlin Gradle migration warnings and produce the debug APK successfully. No unrelated Auth0 analyzer failure was observed in the successful analysis run.

The deployed pricing artifact SHA-256 remains `2b9b23ac8069a3fee776181131f65d1ebc82aa135a88ca918abedcae5059a976`.

## Commit message

```text
feat(admin): add readable record details, pagination and simpler settings

- add safe admin record lookups and database dashboard totals
- center responsive tables and keep pages, filters and failures independent
- prevent Users/Listings state reuse and ignore late section responses
- show reviewed verification records with current-status filters
- redesign detail dialogs with grouped cards and lazy protected previews
- format Malaysia dates and simplify status, verification and pricing copy
- replace coded reward inputs and remove active Passport options
- add detail, privacy, pagination, navigation and launcher regressions
```

## 9 Nov 2026: licence-review status and dashboard chart

The driving-licence approval dialog previously read `verification.documents`, but the admin detail projection intentionally removes that private collection. An approved MyKad therefore appeared as unverified in the popup. The API now derives an additive `mykadIdentityStatus` before projecting the record, using the same current-approval policy as driving eligibility. Flutter displays **MyKad identity: Verified** for an approved MyKad, readable current states otherwise, and **Not available** when an older response cannot establish the state.

Current MyKad document records take precedence over the legacy top-level record. Licence/passport approval or historical approved attempts cannot establish current MyKad approval. Protected document contents, fingerprints and raw identity numbers remain excluded. No approval, account or history was changed. The dialog now has a bounded desktop width, better field spacing and shorter review guidance; licence classes, expiry and administrator confirmations remain required under the existing server rules.

The dashboard includes **Bookings at a glance**, an accessible horizontal bar chart using grouped database counts from the existing admin-only `/api/v1/admin/dashboard-summary`. It separates Awaiting payment, Awaiting Owner approval, Approved, In progress, Completed, In dispute, Cancelled, Rejected and Expired. Unknown legacy states appear under Other records. The total and bars use the same aggregation, independent of table pagination. It includes physical/service and demonstration records and says so; it does not claim organic marketplace activity, revenue growth or completed payments. Empty and unavailable data have distinct messages, with existing dashboard refresh available.

Regression coverage includes current/legacy MyKad approval, rejected/reset status, passport/history-only records, safe projection, unpaid versus paid pending requests, all booking states, counts beyond the first page and empty data. Widget tests cover the real approval popup, cancellation without mutation, invalid chart responses, accessibility labels and 360/390/1024/1440 widths at 150% text size.

Verification for this update:

- Full isolated API suite: **682 passed, 3 skipped**.
- Full Flutter suite: **671 passed, 3 skipped**. Focused admin tests: **46 passed**.
- Final Flutter analysis: **no issues**. The first analysis flagged an unnecessary cast in the new chart; it was removed and analysis rerun successfully.
- Main web, administrator web and Android debug APK: **passed**. Existing Socket.IO WebAssembly/Cupertino-font and Android Kotlin migration warnings remain.
- Three private visual-preview checks passed. Inspected the rendered 360/1440-pixel chart and desktop licence popup using test fixtures. Both counts and labels are readable; the approval popup is centred and constrained. These are rendered widget previews, not live Android walkthrough results.
- JavaScript syntax checks and `git diff --check`: **passed**. Deployed model/metrics checksums: **unchanged**.
- Full suite logs: `.data/testing/20261109-135938-0c98d1be/`. Final analysis and visual logs: `apps/renthub_flutter/.data/admin-final-analysis.log` and `admin-visual-check.log`. The isolated run retains its original analysis warning result; the final analysis log records the successful follow-up.

The skipped checks are existing opt-in/live phases. No live-account approval, live identity upload or phone walkthrough was performed. Restart the API and hot-restart/reopen the admin app, then refresh Verification/Dashboard to load the additive fields. Older APIs show an unavailable chart instead of invented zero counts.

Suggested commit for this update:

```text
fix(admin): correct MyKad review status and add booking overview chart

- derive safe current MyKad status using driving-approval rules
- keep historical attempts and private identity data out of approval labels
- constrain licence dialogs and simplify review guidance
- aggregate booking states independently of paginated records
- separate unpaid requests from those awaiting Owner approval
- add responsive accessible chart, regression tests and verification notes
```

### Licence expiry prefill

The user-side licence check already stores the extracted date in the selected submission's `aiEvidence.drivingAssistance.validUntil`. The safe admin projection was dropping that assistance object, leaving the existing prefill empty. Admin user/verification detail responses now include only the structured expiry date and recognized licence classes for driving-licence evidence. Protected OCR text, names, identity numbers, fingerprints and unrelated extraction fields remain excluded.

The approval form prefills **Valid until** and the detected licence classes from the pending attempt. It explains **Read from the photo. Check and correct if needed.** Administrators can correct either field. The existing identity-match and licence-review confirmations and server expiry/class checks still apply; reading a date never approves a licence automatically. Older rejected attempts do not supply the current attempt's date.

Strict calendar dates retain their exact `YYYY-MM-DD` value without timezone conversion. Missing or invalid dates stay blank and require manual review. Legacy normalized extraction fields are supported, but free-text dates are not guessed. This change does not reread documents, change historical approvals or write extracted values into accounts during viewing.

Focused verification: **58 API tests** and **54 Flutter tests passed**, including actual submission-to-admin extraction, private-field exclusion, valid/invalid leap dates, editable prefill, missing-date validation, selected-attempt isolation and confirmation payloads.

Full isolated run `.data/testing/20261109-140736-644b7460/`: **684 API tests passed, 3 skipped; 673 Flutter tests passed, 3 skipped; analysis clean; main web, administrator web and Android debug builds passed**. Deployed model/metrics checksums remain unchanged. The existing opt-in test skips and web/Kotlin build warnings remain. Two private popup render checks also passed at 360/1440 pixels with 130% text, and their prefilled fields and separated actions were visually inspected. No live approval or device test was performed.

Commit message:

```text
fix(admin): prefill licence expiry from saved extraction

- expose only normalized licence expiry and recognized classes in admin details
- prefill editable review fields from the selected pending attempt
- preserve required review confirmations and protected identity data
- test missing dates, calendar validity, corrections and extraction end to end
```
