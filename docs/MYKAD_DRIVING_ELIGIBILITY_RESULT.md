# MyKad identity KYC and separate vehicle driving eligibility

Updated: 6 October 2026

## Outcome and previous architecture

Previously MyKad, passport and driving licence used one document-submission UI,
one shared verification aggregate and document-type approvals for booking gates.
The preceding classification fix separated document headings from IC numbers,
but licence approvals still lacked a dedicated expiry/class/holder review state.

The implementation now separates these scopes:

```text
Primary AI identity KYC: Malaysian MyKad front + back
  protected uploads -> OpenCV / EasyOCR / rules / optional risk model
  -> stored masked AI evidence -> administrator final identity approval

Vehicle driving eligibility: user-provided licence / MyJPJ e-LMM images
  protected uploads -> OCR/rule assistance (no trained licence model required)
  -> compare with approved MyKad -> administrator reviews class and validity
  -> separate drivingEligibility approval

Vehicle request, approval, handover and extension:
  approved MyKad + approved driving eligibility + current/rental-date validity
  + required licence class, when specified
```

No public JPJ API, official JPJ QR validation, Malaysian-government
authentication or legal identity-proof claim is made. OCR/risk assistance is not
proof that a licence or MyKad is genuine. Production KYC uploads must not become
training data without explicit consent and research governance; no such training
or ingestion was added.

## Schema and API changes

`verification` remains the backwards-compatible identity aggregate; it was not
renamed or duplicated. Only MyKad/passport identity documents affect its status.
Licence submissions no longer change the selected identity document/evidence.
Passport remains an optional compatibility API document, not a primary new-user
screen or mandatory FYP document.

New private/self/admin user state:

```text
drivingEligibility:
  status: unverified | pending | approved | rejected | resubmission_required
  latestAttemptId, submittedAt
  licenceClasses[]
  expiresAt, verifiedAt, verifiedBy (existing authId review convention)
  reviewNotes
  identityMatch: matched | mismatch | unavailable
  identityMatchConfirmed, classReviewConfirmed
  legacyRecord (only when preserving a legacy approved licence snapshot)
```

The database preserves approval history; expiry is evaluated dynamically rather
than rewriting an approved attempt. Flutter renders invalid dates as Expired or
incomplete state as Resubmission required. An expiry date entered as YYYY-MM-DD
is valid through that Malaysian calendar day's end (UTC+08:00), not UTC midnight.

Existing protected `verification.history` is reused, with the driving document
type retained and `drivingReview` decision metadata on that attempt. There is no
second upload storage or duplicate attempt system. Approved driving renewals or
class updates may be submitted with confirmation: current eligibility becomes
pending, while the prior reviewed attempt remains readable.

New endpoints:

- `POST /api/v1/users/me/driving-eligibility`: own protected image references;
  stores pending/resubmission-required evidence, never automatic approval.
- `PATCH /api/v1/users/{userId}/driving-eligibility`: admin-only approve, reject
  or request resubmission. Approval requires approved MyKad, no known holder
  mismatch, reviewed classes, future valid-until date and both explicit review
  confirmations. Non-approval needs a reason.
- Existing `/users/me/verification` and `/users/{userId}/verification` accept
  driving document types for compatibility, applying the same separate state
  and approval restrictions.
- `/users/me/verification/requirements` preserves document-type requirement
  fields and adds `drivingEligibility.valid/code/reason` for Vehicles, with an
  optional `requiredLicenceClass` query.

End users cannot change eligibility state through profile edits. Public profiles
do not include protected evidence, fingerprints or driving-eligibility details.

## Holder-match assistance and privacy

An optional `KYC_IDENTITY_MATCH_SECRET` (private, high-entropy, at least 32
characters) enables keyed HMAC comparison of OCR IC numbers. Only a private
`identityMatchFingerprint` is stored; the raw IC number is not. The fingerprint
is excluded from normal MongoDB projections, API JSON and admin list responses.
Key identifiers allow a rotated/different key to degrade to unavailable rather
than falsely report a holder mismatch.

MyKad's fingerprint is captured from its OCR evidence; comparison is available
only against an approved MyKad account. Without a key, usable OCR, or a legacy
fingerprint, the result is unavailable. Administrators must compare the existing
protected MyKad/licence evidence and explicitly attest the holder match. This is
manual verification, not an automatic government check. Known mismatches block
approval and require rejection/resubmission, even if a checkbox is selected.

Existing raw-OCR removal and identity-number masking remain in place. No new
identity/OCR logs, real identity images or real identity numbers were added.
Tests contain labelled synthetic PII and generated file bytes only. No production
MongoDB records were modified and no git commit was created by this task.

## Vehicle policy and class checks

Vehicles always requires approved MyKad and independent driving eligibility;
editable/legacy platform category rules cannot turn these off. Other categories
keep their existing identity rules and do not receive driving-eligibility gates.

Listing `requiredLicenceClass` is optional and editable in the Owner vehicle
form. A supplied class must exactly occur in the administrator-reviewed class
array. There is deliberately no invented equivalence/inheritance rule (for
example D vs DA), automatic vehicle-to-class inference or JPJ lookup.

For legacy/unspecified listing classes, the administrator's explicit class and
validity review is the fallback. Owners should specify the appropriate class
for motor vehicles. This fallback is not a claim that every Malaysian licence
class permits every vehicle. Bicycles remain subject to the requested category-
wide Vehicle policy; adding non-driving exemptions would need a separate policy
decision, not an undocumented code bypass.

New bookings/rentals snapshot category and required class, so an Owner changing
a listing later cannot remove an existing vehicle rental's credential checks.
Legacy rentals without a snapshot resolve the existing listing. Missing legacy
listing data requires review rather than guessing the vehicle category.

Server errors explain missing MyKad, missing/rejected/pending eligibility,
expiry, missing review attestations or wrong class. Expiry must cover the rental
end date, and is rechecked at approval/handover and extension request/approval.
Returns and dispute access are not blocked by expired eligibility.

## Backwards compatibility and migration decision

No destructive bulk migration runs on startup. Old users and listings have safe
defaults for new fields. Existing passport records and all attempt history remain
readable; passport approval can retain its historical global identity badge but
cannot satisfy a vehicle rule specifically requiring MyKad.

Historical approved driving documents do not automatically satisfy the new
eligibility gate: old records lack reliably reviewed expiry, classes and match
attestations. Users submit fresh evidence for admin re-review. Before updating a
legacy approved current licence state, its review metadata and available safe
evidence/references are preserved in `drivingEligibility.legacyRecord`. Existing
attempts are not deleted. Flat legacy licence records receive the same snapshot
treatment; no incomplete legacy data is silently auto-approved.

## Mobile and admin UX

- Profile has distinct MyKad identity and vehicle-driving destinations.
- Verification displays both status sections, reviewed classes and Malaysian
  valid-until date; driving state never masquerades as full identity KYC.
- MyKad captures distinct front/back and reports per-side OCR evidence, empty
  sides and conflicting holder numbers. Weak/missing model evidence stays manual.
- Driving evidence supports protected licence images/MyJPJ screenshots and
  manual mobile capture. It does not invoke a licence-specific ML detector or
  require a licence training dataset.
- Vehicle booking errors offer navigation directly to MyKad or driving review.
- The admin queue labels driving evidence separately, supports filtering and
  prioritises pending MyKad when both flows are pending. Admins can open licence
  evidence, compare protected approved MyKad, see match/OCR warnings and enter
  reviewed classes/date with explicit confirmation before approval. List views
  avoid unnecessary full holder PII.
- Passport is absent from the new submission dropdown; available legacy passport
  status/history remains readable through existing data/UI compatibility.

## Changed files

- User/API: `user.model.js`, `user.service.js`, `user.validation.js`,
  `user.routes.js`, `user.controller.js`, `kycRequirements.js`, new
  `drivingEligibility.js` under `services/api/src/modules/user/`.
- Configuration: `services/api/src/config/env.js`, `services/api/.env.example`.
- Vehicle listings: `listing.model.js`, `listing.validation.js`,
  `listing.service.js` under `services/api/src/modules/listing/`.
- Rental enforcement/snapshots: `booking.model.js`, `booking.service.js`,
  `rental.model.js`, `rental.service.js` in their respective API modules.
- Contract: `packages/api_contracts/openapi.yaml`.
- AI: `services/ai/app/services/image_intelligence.py`,
  `services/ai/tests/test_document_classification.py`.
- Flutter: `live_shared_pages.dart`, `live_admin_app.dart`,
  `live_renthub_controller.dart`, `live_renter_shell.dart`, `live_owner_shell.dart`
  under `lib/features/live/`; `lib/shared/models/domain_models.dart`.
- Tests: API `test/user.test.js`, `test/booking_rental.test.js`; Flutter
  `test/live_kyc_scanner_test.dart`, new `test/live_driving_eligibility_test.dart`.
- Docs: this report and scope updates in `KYC_AI_RESULT.md` and
  `KYC_DRIVING_LICENCE_FIX_RESULT.md`.

## Verification and exact commands

Final successful checks:

| Check | Result |
|---|---|
| Full API regression | 135 passed, 3 optional live tests skipped, 0 failed |
| Final user/booking API checks | 45 passed; MyKad sides, holder match/mismatch, protected ownership, review decisions, legacy data, expiry/class gates, handover and extension |
| Full AI regression | 53 passed; 2 third-party deprecation warnings |
| Focused Flutter/KYC/account/listing/booking/admin contracts | 46 passed, including 360px/390px verification layout |
| Application-only Flutter analysis | No issues |
| Admin web build | Succeeded; existing optional Wasm/font warnings |
| Whole-project Flutter analysis | Two pre-existing Auth0 test-constructor errors, unchanged |
| Whitespace validation | `git diff --check` passed |

PowerShell commands executed (early debug runs were rerun after fixes):

```powershell
# services/ai
.\.venv\Scripts\python.exe -m pytest -q

# services/api (isolated temporary MongoDB; no edits to real .env)
$env:NODE_ENV='test'; $env:AUTH_MODE='mock'; $env:STORAGE_MODE='local'; $env:FCM_MODE='disabled'; $env:BLOCKCHAIN_MODE='disabled'; $env:EMAIL_MODE='disabled'; node --test
$env:NODE_ENV='test'; $env:AUTH_MODE='mock'; $env:STORAGE_MODE='local'; $env:FCM_MODE='disabled'; $env:BLOCKCHAIN_MODE='disabled'; $env:EMAIL_MODE='disabled'; node --test test/user.test.js test/booking_rental.test.js

# apps/renthub_flutter -- SDK entry point avoids the locked sandbox launcher
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe format lib/shared/models/domain_models.dart lib/features/live/live_renthub_controller.dart lib/features/live/live_shared_pages.dart lib/features/live/live_renter_shell.dart lib/features/live/live_owner_shell.dart lib/features/live/live_admin_app.dart
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe format test/live_kyc_scanner_test.dart test/live_driving_eligibility_test.dart
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe C:/Users/weith/develop/flutter/bin/cache/flutter_tools.snapshot analyze
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe C:/Users/weith/develop/flutter/bin/cache/flutter_tools.snapshot analyze lib --no-pub
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe C:/Users/weith/develop/flutter/bin/cache/flutter_tools.snapshot test test/live_kyc_scanner_test.dart test/live_driving_eligibility_test.dart test/live_account_contract_test.dart test/live_booking_payment_contract_test.dart test/live_owner_operations_contract_test.dart test/live_discovery_admin_contract_test.dart test/live_listing_contract_test.dart --no-pub
& C:/Users/weith/develop/flutter/bin/cache/dart-sdk/bin/dart.exe C:/Users/weith/develop/flutter/bin/cache/flutter_tools.snapshot build web --no-pub

# repository root
git diff --check
```

SDK-cache access and temporary test-database startup needed elevated sandbox
permissions. Full analysis errors are in unchanged
`test/auth0_persistence_test.dart` at constructor arguments `latestLinkProvider`
and `mobileLinkPollInterval`. Application code and focused tests pass; unrelated
Auth0 sources/tests were not modified. This is not a claim that the entire Flutter
test suite or whole-project analyzer is green.

## Remaining setup/limitations

1. Restart Express/FastAPI and rebuild/relaunch Flutter to use the new schema/UI.
2. Train/evaluate the primary MyKad KYC detector/risk artifacts from securely
   governed research data. `models/document_yolo.pt` and
   `models/document_risk_efficientnet.pt` are still absent. Missing MyKad models
   degrade safely; driving assistance reports risk model `not_applicable` and
   never fabricates a licence ML prediction/confidence/accuracy.
3. Optionally configure `KYC_IDENTITY_MATCH_SECRET` for new OCR-derived holder
   comparison. Existing MyKad without fingerprints uses explicit manual comparison.
4. Re-review historical licence approvals; specify vehicle classes and verify
   them from evidence. No existing production data was auto-migrated.
5. Real mobile camera/MyJPJ usability and live consented-document admin review
   remain device QA tasks. Automated OCR fixtures do not establish real-document
   accuracy or government-grade authentication.
6. Address the separate pre-existing Auth0 test-constructor mismatch before
   relying on whole-project Flutter analysis/full-test CI.

Suggested commit:

```text
feat(kyc): separate MyKad identity verification from vehicle driving eligibility

- retain protected identity evidence, passport compatibility and admin review
- add independent licence/MyJPJ eligibility with class, expiry and holder checks
- enforce vehicle credentials at request, approval, handover and extension
- preserve legacy licence records and require safe administrator re-review
- add distinct mobile/admin flows, API contracts and synthetic regressions
```
