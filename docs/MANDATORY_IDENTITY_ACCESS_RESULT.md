# Mandatory marketplace identity approval

## Policy

RentHub's current Malaysian identity flow requires administrator-approved MyKad before a renter creates a booking request or an Owner submits/publishes a listing. Uploading evidence, a successful scan, OCR confidence, or a pending review is not identity approval. A driving licence alone does not establish identity approval.

| Action | Approved MyKad required? | Enforcement |
| --- | --- | --- |
| Browse listings, message, view verification status | No | Existing access rules remain |
| Create/edit an Owner draft | No | Existing active-account and Owner-role rules remain |
| Create a booking request | Yes | Flutter preflight + Express authoritative check |
| Submit an Owner listing for review | Yes | Flutter preflight + Express authoritative check |
| Administrator publishes a listing | Yes, for the current Owner | Express rechecks Owner account and MyKad |
| Submit/review identity evidence | No | Existing KYC workflow remains |

The baseline applies to Devices, Vehicles, Equipment, Services, Clothing and Books, regardless of price. Unknown future categories retain the baseline in the requirement resolver. Legacy empty category rules, high-value-only flags and disabled high-value settings cannot switch MyKad off. Applicable additional document requirements remain additive.

Existing vehicle-renter driving-eligibility rules remain unchanged: identity approval plus reviewed licence classes and expiry covering the rental. Owner publication requires MyKad, not the Owner's driving licence.

## Implementation

- `services/api/src/modules/user/kycRequirements.js`: shared MyKad approval guard and mandatory baseline. Per-document status takes precedence over legacy aggregate status. Legacy approved MyKad records without a per-document entry remain compatible; passport/licence-only approval does not qualify.
- Booking creation rejects unapproved identity before booking, payment, conversation or notification creation. Direct API calls cannot bypass Flutter.
- Listing create/edit remains a draft operation. Submission checks identity before AI item inspection or moderation-state changes. Publication rechecks the current Owner and requires an active account; rejection remains possible without approval.
- Flutter refreshes `/users/me` before protected actions and presents status-specific guidance with a route to verification. A failed refresh blocks submission with a retry message. Returning from verification refreshes status again; pending remains blocked.
- Owner forms expose **Save Draft** separately. Physical drafts can be saved without three images; submission still requires the existing images. Saved drafts survive submission errors, and an in-form retry reuses the saved listing ID instead of creating a duplicate.
- Administrator settings show MyKad as mandatory and describe high-value settings as additional-document rules.
- Identity approval is **Approve → Confirm**, with no Basic/Enhanced selector. Flutter sends the decision and attempt ID without a tier; profile and verification pages no longer display tiers. The deprecated database field/model enum remains compatible with old records, but new identity reviews normalize it to `basic`/`none` internally, ignore older clients' tier input, and do not include a tier in new review audit metadata. It is not an access level. No destructive database migration is required. Driving-eligibility confirmations, class review and expiry checks remain unchanged.
- API readiness advertises `mandatory-identity-access-v1`; the launcher will not silently reuse an older API missing this enforcement capability.

No new dependencies, credentials, model training or production database changes are included.

## Existing records and limits

This is prospective enforcement, not a database migration. Existing active listings are not automatically unpublished; Owners must pass the new gate on submission/publication. Existing rentals are not automatically cancelled, and return/support/dispute flows remain available. Booking creation checks the renter's current identity; it does not retroactively audit the identity of Owners of legacy active listings.

AI capture validation and synthetic tamper-risk scores assist review; they neither prove government identity authenticity nor grant marketplace approval. No KYC bypass or automatic approval was introduced.

## Validation (2026-10-07)

- API suite: 153 passed, 3 skipped. Positive payment, communication and booking-availability fixtures explicitly approve synthetic test accounts in isolated databases.
- New API tests cover all six categories and unverified, pending, rejected, resubmission-required and expired statuses; approved success paths; stale aggregate status; legacy settings; drafts; direct submission/publication denial; and absence of booking/payment/thread/notification writes on denied requests.
- Flutter suite: 146 passed, 2 existing skips. Six identity-access regressions cover approval semantics, stale profile refresh, unavailable checks, draft persistence and the actual unverified-Owner **Save Draft** action without images. Additional regressions confirm administrator approval without a tier selector/payload and hiding legacy Enhanced labels from verification status.
- Tier-removal follow-up: 44 API user/access tests passed, including status-only approval, normalizing a legacy Enhanced record on review, ignoring an old client's tier selection, and retaining vehicle driving safeguards.
- Analysis of all changed Dart files: no issues.
- Repository-wide `flutter analyze --no-pub`: still reports two existing undefined named parameters (`latestLinkProvider`, `mobileLinkPollInterval`) in `test/auth0_persistence_test.dart`. These unrelated Auth0 tests were not modified.
- `flutter build web --no-pub`: successful. Existing Socket.IO WebAssembly dry-run and missing Cupertino font warnings remain; the standard web build completes.
- Standalone PowerShell launcher helper tests: passed, including rejecting API readiness without the new mandatory-identity capability. No running user services were stopped or restarted by these tests.
- `git diff --check`: passed.

No live-device or real-document approval end-to-end test was performed. Automated test approvals are fixtures only, never changes to the development/production MongoDB database.

## Apply and check

Restart the API and rebuild/restart Flutter (or stop the old launcher session and run `apps/renthub_flutter/run-renthub.ps1` again). No AI-service restart or dataset retraining is required for this business-rule change.

1. With an unverified account, browse/message and save an Owner draft.
2. Attempt a booking or **Save & Submit for Review**: expect verification guidance and no submission.
3. Submit MyKad evidence: pending must remain blocked.
4. An administrator reviews the evidence through the existing KYC portal and approves it only when appropriate.
5. Retry the booking/listing submission: freshly loaded approval permits the action, subject to the existing availability, agreement, payment, item-image and vehicle-driving requirements.
6. A legacy pending-review listing whose Owner is unapproved must not be publishable by the administrator.

Suggested commit message: `feat(kyc): require approved MyKad for bookings and listing publication`
