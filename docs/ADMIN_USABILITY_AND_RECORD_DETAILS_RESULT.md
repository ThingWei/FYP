# Administrator usability, record details and pagination

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
