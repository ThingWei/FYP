# RentHub Scope Alignment Audit Instructions

**Project:** RentHub FYP  
**Repository:** `ThingWei/FYP`  
**Purpose:** This file tells Codex how to audit the current repository against the approved RentHub project scope before continuing implementation.

---

## 1. First rule: audit before changing code

Do **not** begin by adding missing screens or features.

First inspect the current repository and determine what is already implemented, what is only a placeholder, what is partially implemented, and what conflicts with the approved scope.

For the first audit pass:

- Do not restructure the repository.
- Do not delete existing code.
- Do not rename modules.
- Do not add new dependencies.
- Do not replace working implementations.
- Do not silently resolve scope conflicts.
- Do not treat placeholder AI logic as a completed AI/ML implementation.
- Do not claim that a UI screen means the backend behavior is complete.
- Do not claim that a backend endpoint means the full user flow is complete.

Create the audit result in:

`docs/SCOPE_ALIGNMENT_AUDIT_RESULT.md`

Only begin implementation after the audit is complete and any important conflicts are identified.

---

## 2. Source-of-truth priority

When determining whether RentHub is on track, use this order:

1. The user's newest explicit instruction.
2. The scope checklist in this file.
3. The current repository and its working implementation.
4. `RentHub_Complete_Handover.md`, when available.
5. `AGENTS.md`.
6. Older implementation/result documents.

If two sources conflict, do **not** silently pick one when the difference changes the business flow or project scope. Record the conflict in the audit result.

---

## 3. Current repository baseline

The repository is expected to preserve this architecture:

```text
Flutter mobile / Flutter Web
        |
        v
Node.js + Express REST API / Socket.IO
        |
        +--> MongoDB through Mongoose
        +--> FastAPI AI/ML microservice
        +--> Firebase adapters
        +--> Maps/geospatial adapters
        +--> Local Ganache blockchain through Ethers.js
```

Important architecture rules:

- Flutter must never connect directly to MongoDB.
- Flutter must never call Ganache directly.
- Flutter should access AI/ML functionality through the Node.js API / FastAPI boundary.
- MongoDB connection details must remain server-side.
- Real secrets must never be committed.
- Local mock mode may remain available for demonstrations.
- Live mode may use the Express API and MongoDB.
- Local MongoDB and MongoDB Atlas are both acceptable if they are configured through `MONGODB_URI`.
- MongoDB Atlas is a deployment option, not a separate database architecture.
- Payments are still simulated.
- Blockchain is local-development blockchain only. Do not present local Ganache ETH as real money.

The repository currently contains both `lib/features/...` and `lib/modules/...` style Flutter code. Determine which code paths are actually active before editing. Do not assume both implementations need to be maintained equally.

---

## 4. Mandatory top-level functional structure

Regardless of how many role-specific features exist, the FYP must remain organised under exactly these **10 functional modules**:

1. User Management
2. Listing Management
3. Booking Management
4. Payment Management
5. Rental Management
6. Communication Management
7. Review Management
8. Dispute Management
9. Loyalty and Referral Management
10. Admin Management

Role-specific functions below are **sub-features** of these modules. Do not create new top-level business modules simply because the scope lists many owner/renter/admin feature groups.

Recommendation remains a capability within listing/discovery behavior, not a standalone eleventh business module.

---

# 5. Scope checklist for Codex

For every requirement below, inspect UI, controller/state, repository, API, persistence, validation, tests, and integrations where applicable.

Use one status:

- `ALIGNED` - implemented and consistent with scope
- `PARTIAL` - some layers or behavior exist but the complete flow is not implemented
- `PLACEHOLDER` - interface/contract exists but real logic/model/integration is not implemented
- `MISSING` - no meaningful implementation found
- `CONFLICT` - current implementation contradicts an approved scope decision
- `DEFERRED` - intentionally postponed to a later FYP phase
- `OUTSIDE_CURRENT_PHASE` - final-system scope but not required for the current prototype phase

---

## 5.1 User Management

Check:

- Email registration and login
- Personal profile
- Profile photo, phone number, address and bio
- Renter/Owner role switching for dual-role accounts
- Trust score display
- Verified badge status
- Password/security settings
- Active login session management if included
- Account deactivation
- Admin user management
- Suspend, ban and reactivate behavior
- Trust score / verification-tier administration

### Conflict to report

The newest submitted scope mentions **Google OAuth**, while the previous final handover removed social login as a core requirement.

Do not implement or remove Google OAuth during the audit. Mark it `CONFLICT` and request confirmation unless the user has since explicitly confirmed that Google OAuth is back in scope.

---

## 5.2 KYC and Document Verification

Target pipeline:

```text
Flutter Camera
→ document capture / alignment
→ YOLOv8
→ OpenCV preprocessing
→ EasyOCR
→ spaCy + Regex field processing
→ EfficientNet-B0 forgery/risk analysis
→ FastAPI
→ Node.js API
→ MongoDB KYC/verification record
```

Check the intended capability for:

- Live camera document scanning
- Document presence detection
- Alignment guidance
- Auto-capture when acceptable
- Perspective correction
- Deskewing
- sharpening / image-quality processing
- OCR text extraction
- field identification
- IC/date/structured-field validation
- profile mismatch checks
- forgery/risk classification
- manual-review outcome
- resubmission
- verification history
- confidence/flag logging
- verified profile status

Possible outcomes should remain conceptually:

- Verified
- Pending manual review
- Rejected

### Important honesty rule

Do not claim that KYC proves a person's legal identity.

Do not mark the feature as fully implemented merely because a deterministic FastAPI adapter returns a confidence score.

The current intended FYP approach is document/image verification and risk assessment.

### OCR consistency

The previous technical decision standardised on **EasyOCR**. The submitted scope says `pytesseract / EasyOCR`.

Report this as a technology wording inconsistency. Do not introduce both OCR libraries without a clear reason.

### Security-feature detection

Security checks such as hologram, stamp, watermark or MRZ must be **document-type specific**. Do not claim a feature exists on every supported document type.

If there is no trained/evaluated implementation, classify these checks as `PLACEHOLDER`, `DEFERRED` or `MISSING`, not `ALIGNED`.

---

## 5.3 KYC requirement by rental category

Audit whether category/risk gates can represent:

- High-value devices: IC
- Vehicles: IC + Driving Licence
- High-value equipment: IC
- Services: IC
- Clothes and books: optional

Do not hard-code this logic independently in many screens. Prefer one policy source shared by booking/KYC validation.

If the current implementation uses a simpler protected/high-value rule, report the difference instead of silently rewriting it.

---

## 5.4 Listing Management

Check owner functionality for:

- Create physical-item listing
- Create service listing
- Edit listing
- Pause listing
- Delete listing with confirmation
- Duplicate listing as template
- 3 to 10 listing-photo concept where applicable
- Availability
- listing condition/specifications
- pickup/location data for physical items
- moderation state
- performance metrics
- promotional discounts
- bundle listings
- custom/predefined booking policy configuration
- item-legitimacy result
- price recommendation

Check renter discovery for:

- Browse categories
- keyword search
- filters
- details
- owner profile
- trust score
- verified badge
- reporting suspicious listing
- distance/proximity filtering
- location/map concept
- recommendations
- wishlist
- comparison

---

## 5.5 Item Legitimacy Verification

Target concept:

```text
minimum 3 uploaded photos
→ YOLOv8 item/category detection
→ EfficientNet-B0 image legitimacy/risk classification
→ OpenCV duplicate/reuse checks
→ category / condition consistency checks
→ Approved / Warning / Rejected
→ admin moderation where required
```

Check:

- physical-item presence
- category cross-check
- duplicate/reused photo detection
- warning/manual moderation path
- result history
- resubmission/reupload behavior

### Important honesty rule

Do not claim that EfficientNet can guarantee that an item is genuine.

Claims such as:

- AI-generated image detection
- stock image detection
- screenshot detection
- heavily edited image detection
- condition mismatch detection

must only be marked `ALIGNED` when a real trained/evaluated implementation exists.

Otherwise call them prototype **risk indicators** and classify the implementation accurately.

---

## 5.6 Recommendation

Target recommendation design:

- Collaborative filtering with Surprise SVD
- Content-based filtering with Scikit-learn cosine similarity
- Hybrid weighting: `0.6 content + 0.4 collaborative`
- simulated datasets are acceptable for FYP training/evaluation

Renter-facing scope includes:

- Recommended For You
- Trending Near You
- Recently Viewed
- You Might Also Need
- proximity weighting
- availability-aware ranking

Audit whether the repo currently has:

1. UI only
2. deterministic placeholder recommendation adapter
3. actual feature generation
4. actual SVD model
5. actual cosine-similarity model
6. hybrid-score combination
7. training/evaluation dataset and metrics

Do not classify placeholder ranking strings as the completed smart-recommendation core technology.

---

## 5.7 ML Rental Price Recommendation

Final algorithm:

- XGBoost Regression

Required seven input groups:

1. Item category, subcategory, condition, age, brand/specifications
2. Similar active listing prices in the same category/location
3. Historical completed-rental prices
4. Local supply/demand ratio
5. Seasonal demand and day-of-week trends
6. Rental duration
7. Owner trust score and average rating

Check:

- price input schema
- price recommendation endpoint
- XGBoost model/training
- simulated historical dataset
- price range
- explanation/justification
- similar-listing comparison
- owner accepts or overrides suggestion

A deterministic formula that preserves the API contract must be classified `PLACEHOLDER`, not full ML completion.

---

## 5.8 Booking Management

Physical-item flow must stay separate from service booking.

Audit physical booking for:

- dates
- inclusive rental duration
- rental purpose
- fulfilment/pickup method
- availability
- damage waiver
- deposit
- price breakdown
- agreement acknowledgement
- payment simulation
- submission
- owner approval/rejection
- cancellation
- owner/renter state consistency
- duplicate-submission protection

Authoritative example data used in the project includes:

- Sony Alpha a7S III
- Owner: Sarah J.
- Renter: Alex Tan
- RM 85/day
- 20 Sep 2026 to 22 Sep 2026
- 3 days
- subtotal RM 255
- damage waiver RM 15
- refundable deposit RM 300
- total RM 570
- listing `RH-LST-2026-02419`
- agreement `RH-AGR-2026-09142`
- booking `RH-BKG-2026-09142`

Keep repeated mock/seed references consistent.

### Lifecycle conflict to report

The older handover said the pending booking should be created only after successful simulated authorization.

The current repository integration result records a newer live flow where a booking is created first and then payment authorization occurs, protected with an idempotency key.

Do not silently change this ordering during the audit.

Report:

- current exact behavior
- why it is safe or unsafe
- whether it still satisfies the user's current scope
- which behavior should be treated as final before further work

---

## 5.9 Service Booking

Service lifecycle must remain separate from physical rental.

Check:

- service search
- service details
- package selection
- service date
- service time
- duration
- venue/service location
- booking request
- simulated payment if retained
- submitted state
- owner/provider approval
- in-progress status
- completion confirmation
- review

Service screens must not use physical-rental concepts such as:

- item condition
- refundable item deposit
- pickup
- delivery
- handover
- physical return
- rental extension
- smart-contract item-return behavior

---

## 5.10 Payment Management

Payments remain simulated.

Check:

- server-calculated totals
- payment state
- payment history
- deposits
- cancellation refund preview
- simulated refunds
- penalties where applicable
- no client-authoritative amount
- idempotency / duplicate submission protection

Do not introduce a real payment gateway unless the user explicitly changes scope.

Do not present simulated transactions as real financial transfers.

---

## 5.11 Rental Management

Check:

- Pending / Approved / Active / Completed / Overdue / Cancelled / Disputed states
- active rental details
- handover
- countdown/timeline
- return initiation
- return evidence
- owner return inspection
- deposit outcome
- extension request
- extension availability
- extension recalculation
- owner approval/rejection
- condition history
- maintenance records
- under-maintenance availability blocking

### Overdue alert

This feature appeared in earlier scope but was unresolved in the final handover.

Do not silently add/remove it. Report its current implementation and mark the decision for confirmation if required.

---

## 5.12 Return and Condition

Check renter return:

- minimum photo/evidence concept
- written description
- pending owner confirmation
- return location concept
- final cost / penalty summary

Check owner return:

- compare return evidence
- good condition
- minor damage
- major damage
- dispute creation
- condition log
- maintenance log

No UI or backend should imply a real bank/deposit transfer in this FYP prototype.

---

## 5.13 Communication

Check:

- booking-linked conversation
- pre-booking enquiry if retained
- renter/owner chat
- real-time Socket.IO messaging
- image-message concept
- timestamps
- sent/delivered/read states
- conversation history
- unified inbox
- notifications
- push-notification adapter
- message reporting
- dispute evidence access
- admin access controls
- location pin sharing if this remains in scope

Admin must not have unrestricted casual access to private conversations. Access should be tied to moderation/dispute needs.

---

## 5.14 Review Management

Check:

- renter submits review after completion
- 1-5 star rating
- condition / communication / value aspects
- written review
- edit within 24 hours
- renter views reviews before booking
- owner reputation summary
- suspicious review flag
- admin moderation

Do not reintroduce NLP sentiment analysis as a core technology unless explicitly approved.

Use review/rating trend terminology rather than claiming sentiment analysis when no NLP model exists.

---

## 5.15 Dispute Management

Check:

- renter raises dispute
- owner raises dispute
- evidence
- photos
- messages
- agreement linkage
- status
- admin review
- admin communication
- release-to-renter outcome
- split outcome
- release-to-owner outcome
- reason/decision notes
- audit log
- blockchain resolution reference where applicable

Do not claim that the blockchain itself independently judges disputes. The admin makes the platform decision and the contract records/executes the resulting local-prototype action.

---

## 5.16 Insurance / Damage Waiver

Check:

- renter waiver plan selection
- coverage summary
- active waiver status
- agreement linkage
- owner claim submission
- evidence
- claim status
- admin approve/reject
- claim history

Treat insurance/payment outcomes as prototype/simulated unless a real provider is explicitly introduced later.

---

## 5.17 Loyalty and Referral

Check:

- points earned on successful completion
- balance
- history
- redemption
- reward tiers
- expiry concept
- referral code
- referral sharing
- reward after first completed rental
- referral history
- admin programme configuration

Keep this within the single top-level `Loyalty and Referral Management` module.

---

## 5.18 Bundle behavior

Check both listing bundles and renter bundle booking behavior.

### Important complexity question

The submitted scope allows bundling items from **the same or different owners** in one booking session.

Cross-owner bundles complicate:

- approval
- payment allocation
- deposits
- smart contracts
- different rental statuses
- cancellation
- return
- disputes

Do not introduce a new cross-owner transaction architecture during the audit.

Report whether current code supports:

- same-owner bundle
- different-owner bundle
- UI-only bundle
- no bundle booking lifecycle

Flag this for confirmation if current behavior differs from the stated scope.

---

## 5.19 Admin Management

All admin sub-features remain under the single top-level Admin Management module.

Audit:

### User and trust
- user directory
- search/filter
- detail
- suspend
- ban
- reactivate
- warnings
- trust score
- verification tier
- audit justification

### Verification
- verification queue
- AI analysis result
- approve/reject/resubmit
- history
- confidence threshold concept
- statistics

### Listing moderation
- pending queue
- approve
- reject with reason
- remove
- report review
- reinstate

### Rentals / transactions
- rental visibility
- filtering
- overdue visibility
- status override with reason
- transaction ledger
- simulated refund/penalty actions
- audit logging

### Claims / disputes
- claim review
- dispute evidence
- outcome
- suspicious claim pattern indicators where applicable

### Messaging oversight
- reported messages
- surrounding context
- warnings
- moderation
- restricted access
- flagged content

### Analytics
- users
- listings
- rentals
- categories
- booking conversion
- revenue-like simulated platform metrics
- recommendation metrics
- pricing metrics
- verification metrics

### Platform health
- API/service status
- error status
- service health
- incidents if implemented

### Loyalty/referral administration
- earning rules
- redemption rules
- referral rewards
- statistics

### Platform settings
- categories/subcategories
- rental policies
- damage waiver configuration
- homepage configuration
- notification templates
- verification thresholds
- terms/privacy content

### Reports
- rental activity
- transaction summary
- verification
- ML model performance
- disputes
- loyalty/referral

### Scope-drift caution

Earlier final use-case work deliberately simplified Admin Management.

The newly submitted scope contains many advanced admin functions, including:

- trust-score weight simulation
- prohibited keyword configuration
- real-time health dashboards
- scheduled announcements
- scheduled email reports
- broad category/policy configuration

Do not silently expand the implementation merely because these appear in the scope document.

Audit them and mark each as `ALIGNED`, `PARTIAL`, `MISSING`, `DEFERRED`, or `CONFLICT`.

Any feature that materially exceeds the previously agreed final use cases must be listed under **Scope Decisions Requiring Confirmation**.

---

## 5.20 Guide and FAQ

The submitted renter scope includes:

- first-login guide
- category-specific rental tips
- FAQ
- FAQ search
- policy/terms summary

This was not prominent in the previous final module/use-case handover.

Audit current implementation, but do not create a new top-level module.

Possible mappings include User Management or Communication Management, subject to user confirmation.

---

# 6. Technical stack alignment checklist

Codex must verify the repository against this intended stack.

| Area | Intended technology |
|---|---|
| Client | Flutter / Dart |
| Admin client | Flutter Web |
| Backend | Node.js + Express.js |
| Database | MongoDB / Mongoose |
| Real-time messaging | Socket.IO |
| Authentication | Auth0 + JWT in intended integrated architecture |
| API security | HTTPS in deployed environment |
| AI microservice | Python + FastAPI |
| Document/object detection | YOLOv8 |
| CV processing | OpenCV |
| OCR | EasyOCR |
| Text field processing | spaCy + Regex |
| CNN | EfficientNet-B0 |
| Recommendation | Surprise SVD + Scikit-learn cosine similarity |
| Hybrid weighting | 0.6 content + 0.4 collaborative |
| Price model | XGBoost Regression |
| Blockchain | Solidity + Hardhat + local Ganache + Ethers.js |
| Push notifications | Firebase Cloud Messaging |
| File storage | Supabase Storage |
| Location | OpenStreetMap / Nominatim |
| Geospatial | GeoJSON + MongoDB geospatial queries + Geolib/Turf.js |

For each technology, report whether it is:

- installed/configured
- adapter/contract only
- genuinely integrated
- trained/implemented
- tested
- not yet started

---

# 7. MongoDB and MongoDB Atlas check

The API should use Mongoose and a `MONGODB_URI` environment variable.

Codex must verify:

- no MongoDB credentials are hard-coded
- `.env` is ignored
- `.env.example` contains only placeholders/local examples
- local MongoDB remains usable for development/tests where appropriate
- an Atlas `mongodb+srv://...` URI can be supplied through `MONGODB_URI` without code changes
- indexes required by the project are defined
- GeoJSON/2dsphere indexing is present before claiming production location search
- relationships between users, listings, bookings, rentals, payments, messages, reviews, disputes and verification records remain consistent
- seed data does not create contradictory references

Do **not** connect Flutter directly to MongoDB Atlas.

Correct:

```text
Flutter → Express API → MongoDB Atlas
```

Incorrect:

```text
Flutter → MongoDB Atlas
```

---

# 8. AI/ML completion rule

This is critical.

The repository may intentionally contain deterministic adapters to preserve API contracts while the real models are not trained.

Codex must clearly distinguish:

```text
API contract exists
```

from:

```text
real ML/CV model is implemented, trained and evaluated
```

A placeholder adapter is useful architecture progress but is **not** completion of the FYP's core AI technology.

For every AI/ML capability, the audit should eventually expect evidence of:

- dataset
- preprocessing
- training script/notebook
- model artifact
- inference adapter
- API endpoint
- evaluation metric
- representative tests
- failure/low-confidence behavior

---

# 9. Blockchain completion rule

The blockchain target is local only.

Audit:

- Solidity contract
- Hardhat configuration
- local Ganache deployment
- tests
- Ethers.js backend adapter
- MongoDB reference/hash linkage
- renter/owner agreement state
- dispute-resolution reference
- cancellation / penalty / deposit logic

Do not claim:

- Ethereum mainnet
- Polygon
- MetaMask
- real cryptocurrency transfer
- real financial escrow

A local Ganache contract may demonstrate escrow-like state transitions using test ETH, but documentation/UI must label it as a prototype/local smart-contract behavior.

---

# 10. UI and lifecycle consistency

Check that repeated entities maintain the same:

- name
- owner
- renter
- listing ID
- booking ID
- agreement ID
- price
- deposit
- status
- rating
- location

Check mobile navigation:

### Renter

`Home | Explore | Bookings | Messages | Profile`

### Owner

Latest agreed handover:

`Dashboard | Listings | Bookings | Messages | Profile`

The existing `AGENTS.md` may still use `Requests` instead of `Bookings`.

Audit the actual app and flag this wording difference. Do not rename navigation during the audit.

### Admin

Separate responsive desktop/web interface.

---

# 11. Quality and validation requirements

After the audit, but before declaring any implementation phase complete, run all applicable checks.

## Flutter

```bash
cd apps/renthub_flutter
flutter pub get
dart format .
flutter analyze
flutter test
flutter build web
```

Also build/test the separate admin entry point where appropriate.

## Node API

```bash
cd services/api
npm install
npm test
```

Use the repository's existing scripts where exact command names differ.

## FastAPI

Run the existing Python tests, typically:

```bash
cd services/ai
pytest
```

## Blockchain

```bash
cd blockchain
npm install
npx hardhat test
```

Do not claim completion while newly introduced:

- analyzer errors
- failed tests
- broken routes
- runtime exceptions
- dead primary buttons
- visible overflow
- inconsistent persistent records

remain.

---

# 12. Required audit result format

Create `docs/SCOPE_ALIGNMENT_AUDIT_RESULT.md` with:

## A. Executive summary

State:

- whether the project is generally on track
- the strongest completed areas
- the largest missing areas
- any serious scope conflicts
- recommended next implementation phase

## B. Coverage table

Use:

| ID | Requirement | Target module | Evidence / files | Status | Gap / note | Priority |
|---|---|---|---|---|---|---|

Priority:

- `P0` - required core flow / architecture blocker
- `P1` - important FYP scope
- `P2` - useful secondary scope
- `P3` - polish / optional / advanced admin capability

## C. Technology readiness

For every major technology, separate:

- configured
- integrated
- real implementation
- tested
- evaluated

## D. End-to-end lifecycle readiness

Audit at minimum:

1. Renter registration/login/KYC
2. Renter discovery → physical booking → payment → pending request
3. Owner approval/rejection
4. Agreement/signing
5. Handover → active rental
6. Extension
7. Return → owner inspection
8. Deposit outcome / dispute
9. Review
10. Service-booking lifecycle
11. Messaging
12. Admin moderation
13. Loyalty/referral

## E. Scope decisions requiring confirmation

List every unresolved conflict without making the decision on the user's behalf.

At minimum review:

- Google OAuth
- `Bookings` vs `Requests` owner navigation label
- booking creation vs payment-authorization ordering
- overdue alert
- cross-owner bundles
- advanced admin scope beyond the simplified final use cases
- guide/FAQ placement
- scheduled email reports
- OCR wording (`pytesseract / EasyOCR` vs EasyOCR)
- any feature that older handover explicitly removed but this scope reintroduces

## F. Next recommended implementation order

Recommend the next work based on actual gaps, not based on what is easiest to generate.

Do not start the next phase automatically unless the user asks.

---

# 13. Current expected direction

The project should continue toward a complete FYP system without pretending unfinished research components are complete.

The intended progression is:

```text
stable architecture
→ correct data model and lifecycle
→ backend/UI integration
→ persistent MongoDB flows
→ real AI/ML model development and evaluation
→ local blockchain integration
→ maps/storage/push/auth integrations where required
→ admin completion
→ testing
→ report/demo consistency
```

Preserve what already works.

Do not restart RentHub.

Do not inflate the project by inventing features outside the submitted scope.

Do not reduce the core AI/ML contribution to hard-coded placeholder values and then call it complete.

The audit should make it clear what RentHub can **demonstrate now**, what is **architecturally prepared**, and what still needs **real implementation before final FYP submission**.
