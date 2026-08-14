# Stitch UI and Flutter Comparison

## Scope and status

- Stitch project: `2362719991600770029`
- Stitch URL supplied: `https://stitch.withgoogle.com/projects/2362719991600770029`
- Local Flutter app: `apps/renthub_flutter`
- Inspection date: 14 August 2026 (Asia/Kuala_Lumpur)
- Mutation status: the Stitch project was not modified. Flutter UI Implementation Batches 1 and 2 were completed and are recorded below.

## Stitch retrieval result

The retry succeeded on 14 August 2026. `list_projects` was called first and returned project `2362719991600770029` (`Multi-Category Rental Marketplace`). `get_project` then returned 55 canonical screen resources. The Stitch `list_screens` RPC returned `Request contains an invalid argument`, so each canonical screen ID from the project was resolved with `get_screen`; all 55 screens were retrieved. Two transient per-screen errors succeeded on retry. No browser fallback was used.

Project metadata: public, `TEXT_TO_UI_PRO`, updated `2026-08-14T12:02:00.936512Z`, with a primarily mobile project canvas. The inventory contains 48 mobile screens, six desktop screens, and one device-agnostic logo asset.

## Verified local Flutter inventory

### Shared authentication and account UI

| Local UI | Location | Status | Notes |
|---|---|---|---|
| Login | `lib/modules/user/views/login_screen.dart` | Implemented (Batch 1) | Stitch-aligned card, validation, loading/error handling, password visibility, simulated Auth0 action, and working registration/reset navigation. Existing mock login logic is preserved. |
| Registration | `lib/modules/user/views/register_screen.dart` | Implemented (Batch 1) | Three-step details/security/role-and-terms flow, validation, loading/error handling, success state, and existing `AuthController.register` integration. |
| Admin login | `lib/features/admin/admin_app.dart` | Exists | Separate web entry point with validation and mock credentials. |
| Role switching | `lib/app/app.dart`, `lib/features/account/role_selection_screen.dart` | Implemented (Batch 1) | Dedicated Stitch-aligned role selection is available only to eligible dual-role users and preserves controller role state. |
| Profile | `lib/features/account/account_pages.dart` (`ProfilePage`) | Implemented (Batch 1) | Shared renter/owner profile includes personal info, verification, address/payment mock actions, trust score, role switch, help/security actions, and confirmed controller-driven sign-out. |
| Notifications | `lib/features/account/account_pages.dart` (`NotificationsPage`) | Implemented (Batch 1) | Shared renter/owner entry points, category filters, grouped read/unread cards, mark-all-read, tap feedback, dismissal with undo, loading and empty/error presentations. |
| Splash and onboarding | — | Missing | No routed implementation found. |
| Forgot-password form | `lib/modules/user/views/forgot_password_screen.dart` | Implemented (Batch 1) | Local four-state email/code/new-password/success flow with loading, validation, retry guidance and no external integration. |

### Renter UI

| Local UI | Status | Notes |
|---|---|---|
| Five-destination renter shell | Exists | Home, Explore, Bookings, Messages, and Profile use an `IndexedStack` and Material navigation bar. |
| Home/discovery | Implemented (Batch 2 physical-item journey) | Stitch-aligned location/search/categories/recommendations/service teaser and routed item discovery are complete for the approved journey. Wishlist persistence and nearby/promoted expansion remain deferred. |
| Explore/search results | Implemented (Batch 2 physical-item journey) | Query, category/type, location, price, availability, and verified-Owner filters work and survive details back navigation with scroll position. Dedicated service results remain deferred. |
| Listing details | Implemented (Batch 2 physical-item journey) | Physical-item imagery placeholder, price, location, rating, verified Owner/trust, condition, equipment, policy, fulfilment, deposit, and booking route are complete. Service-specific detail work remains deferred. |
| Wishlist | Missing | No dedicated screen or persisted mock state. |
| Listing comparison | Missing | No screen or comparison selection flow found. |
| Booking and checkout | Implemented (Batch 2 physical-item journey) | Dedicated date/availability/fulfilment/location/quantity and pricing selection, agreement acceptance, local simulated authorization, exactly-once Pending creation, and submitted state are routed end to end. |
| Booking history | Implemented (Batch 2 approved scope) | Pending, Active, Completed, and Cancelled tabs work; the latest created request appears first under Pending. Dedicated booking detail/post-booking flows remain deferred. |
| Physical rental tracking, extension, return evidence | Incomplete | Some actions are represented from booking cards, but dedicated end-to-end screens and condition evidence workflow are absent. |
| Service completion | Incomplete | Conditional service presentation exists, but a dedicated completion-confirmation flow is absent. |
| Messages and chat | Partial | Conversation list and chat page exist; composing/sending is mostly presentation-level. |
| Review submission | Missing from routed renter flow | A separate legacy `modules/review/views/review_view.dart` exists, but no routed renter flow was found. |
| Dispute submission | Incomplete/unwired | “Report an issue” is visible; a separate legacy dispute view exists, but the routed evidence form is not complete. |
| Insurance claim | Missing | No routed claim-status flow found. |
| Loyalty and referral | Incomplete/unwired | A legacy loyalty view exists; no integrated renter navigation or referral screen was found. |
| Block Owner/report listing | Partial | Confirmation is shown, but state and follow-up screens are not implemented. |

### Owner UI

| Local UI | Status | Notes |
|---|---|---|
| Five-destination owner shell | Exists | Dashboard, Listings, Requests, Messages, and Profile are present. Messages and Profile reuse shared renter-file pages. |
| Dashboard | Partial | Metrics, action-needed cards, and recent earnings exist; action cards do not all lead to detailed workflows. |
| Listing list/statuses | Partial | Listing list exists, but full active/draft/pending-review/inactive filtering and state management need expansion. |
| Create physical item/service | Partial | Type choice and conditional form fields exist, with image placeholders, item verification, availability, promotion, and save feedback. Editing existing records and richer validation/state persistence are incomplete. |
| Bundle management | Missing | No integrated bundle workflow found. |
| Booking requests | Partial | Request list and approve/reject confirmations update local UI. Dedicated request details and required rejection reason are incomplete. |
| Active rental/service management | Missing/incomplete | No complete routed order-management surface for handover, return, extension decision, or service completion. |
| Earnings and transactions | Incomplete | Dashboard shows a recent earning, but no transaction-history screen exists. |
| Renter profile and review | Missing/incomplete | Request cards show verification/trust text; no full renter profile or owner review-submission flow. |
| Dispute response and evidence | Missing | No integrated owner response workflow found. |
| Insurance claim submission | Missing | No integrated owner claim form found. |
| Owner notifications | Incomplete | Notification UI exists in the renter feature file but is not clearly exposed from the owner shell. |

### Administrator web UI

| Local UI | Status | Notes |
|---|---|---|
| Responsive admin shell | Exists | Ten requested destinations are present; sidebar appears at 900 px and a drawer is used below that width. |
| Dashboard | Partial | Four metrics and pending-work summaries exist. Trends and recent-action details are limited. |
| Verification | Incomplete | Generic data table and approve/reject actions exist; document viewer, OCR placeholders, details, and resubmission flow are absent. |
| Users | Incomplete | Generic table/search/actions exist; account details, filters, required reason, suspension, and banning workflows are not fully implemented. |
| Listings/moderation | Incomplete | Generic records and actions exist; listing details and physical-item verification review are absent. |
| Bookings and transactions | Incomplete | Generic monitoring table only; transaction/refund details are absent. |
| Disputes and claims | Incomplete | Generic records only; participant, evidence, conversation, resolution, and insurance-claim review screens are absent. |
| Reports | Incomplete | Generic table only; report-type-specific details and moderation workflows are absent. |
| Reviews | Incomplete | Generic table only; review content and moderation detail are absent. |
| Platform settings | Incomplete | Generic table is used instead of editable settings forms. |
| Audit logs | Partial | Read-only rows are shown, but filtering, event detail, and strong append-only presentation are limited. |

## Legacy or parallel local UI

The repository contains older module-level screens for listings, bookings, payments, disputes, reviews, loyalty, rentals, inbox, and an older admin dashboard. The active application primarily routes through `features/renter/renter_app.dart`, `features/owner/owner_app.dart`, and `features/admin/admin_app.dart`. A source file existing under `modules/` should therefore not be treated as a completed user-facing screen unless it is integrated into the active shells.

## Stitch-to-Flutter comparison status

Status meanings: **represented** means an equivalent routed local UI exists; **partial** means the concept is present but the Stitch-specific screen or flow is not complete; **missing** means no routed equivalent was found. Role is inferred from the title and product flow because Stitch does not expose a role field per screen.

| Stitch screen | Screen ID | Device | Inferred role | Flutter mapping | Status / delta |
|---|---|---|---|---|---|
| RentHub Main Logo | `6a496e60021a4ec9b0090429901516cc` | Agnostic | Shared | Text logo/theme | Represented; local uses the required text-based logo rather than this image asset. |
| Login | `7c58ffe68b8a4fcdbcb477c7a3b50e2f` | Mobile | Shared | `login_screen.dart` | Implemented in Batch 1 with working registration/reset routes and preserved mock authentication. |
| Create Account | `5404184524d146ce9710a1057a284887` | Mobile | Shared | `register_screen.dart` | Implemented in Batch 1 as a validated three-step native Flutter flow. |
| Forgot Password & Reset | `aec18e52f24a47429524323a71626503` | Mobile | Shared | `forgot_password_screen.dart` | Implemented in Batch 1 with email, code, password and success states. |
| Choose Your Role | `5d96cd5a932a43488f8a6ab9413cfa65` | Mobile | Shared | `role_selection_screen.dart` | Implemented in Batch 1 for eligible dual-role users and registration reuse. |
| Notifications | `1e08ec672d5b4e1d96db269700749736` | Mobile | Shared | `account_pages.dart` (`NotificationsPage`) | Implemented in Batch 1 with filters, read state, removal/undo, loading and empty/error states, and both-role entry. |
| Profile & Settings | `31ee7cf6f6da4d72a7a419781cce6b6c` | Mobile | Shared | `account_pages.dart` (`ProfilePage`) | Implemented in Batch 1 with shared renter/owner content, mock management actions, verification route and confirmed logout. |
| KYC Verification Gate | `f56ec35b312d4963b03aab6cbae7bca` | Mobile | Shared | `verification_gate_screen.dart` | Implemented in Batch 1 as an explicit local mock gate with loading, success and defer paths. |
| RentHub Home | `b8415964ef6b47c7af179b73751f17dd` | Mobile | Renter | Renter `RenterHome` | Implemented in Batch 2 for the approved physical-item journey; wishlist persistence and broader discovery sections remain deferred. |
| Search Results | `6b11258ef8b8401b991a3a6770b344fe` | Mobile | Renter | Renter `ExplorePage` | Implemented in Batch 2 with functional physical-item filters plus query/filter/scroll retention. |
| Services Search Results | `7eb567a7efee4b64910319637613fa55` | Mobile | Renter | Renter Explore | Partial; no dedicated service-results state. |
| Item Details | `1e621b4492184f30b453262fe903a62f` | Mobile | Renter | `ListingDetailsPage` | Implemented in Batch 2 for physical items with the shared booking-draft entry. |
| Service Details | `5887fbdeefdd4993b70ee1d941adbbb5` | Mobile | Renter | Listing details | Partial; conditional service copy exists, dedicated service detail fidelity incomplete. |
| Wishlist | `774127c707b848f1a5ba29581a60ca0f` | Mobile | Renter | Snackbar action only | Missing. |
| Compare Items | `bb3955fdaefc4fe7971aeb01986e9e67` | Mobile | Renter | No routed equivalent | Missing. |
| Rental Agreement Review | `0d4d14f752c543c1933ef94f7a78efc7` | Mobile | Renter | `AgreementReviewPage` | Implemented in Batch 2 with exact draft summary, acceptance gating, and state-preserving Back. |
| Simulated Payment | `c24c80dc4aa446c0a1ca8b919be2d9a7` | Mobile | Renter | `SimulatedPaymentPage` | Implemented in Batch 2 as explicitly prototype-only local authorization with retry and duplicate-submission guards. |
| Booking Request Submitted | `f373c9b4e78d442495d561e449102561` | Mobile | Renter | `BookingRequestSubmittedPage` | Implemented in Batch 2 as a distinct Pending-owner-approval result with no captured payment. |
| Service Request Submitted | `26b217a810ee493bbf85cda7d83ea8f5` | Mobile | Renter | Checkout success | Partial; no service-specific submitted screen. |
| My Bookings | `42e8f4e0ceba4d74a1689a57bf87c60c` | Mobile | Renter | `BookingsPage` | Implemented in Batch 2 with Pending/Active/Completed/Cancelled tabs and latest Pending request first. |
| Pending Booking Details | `75b57405bfce4554a67a757de1ed5463` | Mobile | Renter | Booking cards | Partial; dedicated detail view missing. |
| Physical Item Booking Details | `237d562602b24265816651a0c8c914c0` | Mobile | Renter | `BookingDetailsPage` | Implemented in Batch 2 with date range, availability, fulfilment/location, quantity policy, deposit, subtotal, total, and ready-state validation. |
| Service Booking Details | `a06cde3abdb14acbb34dca9354ad35ea` | Mobile | Renter | Booking cards/actions | Partial; dedicated service detail missing. |
| Cancel Booking | `15d465dc571547dfb6368215369ee353` | Mobile | Renter | Confirmation action | Partial; no dedicated cancellation/reason screen. |
| Active Rental Details | `44b012a60b164da5a42a7a54b87d9861` | Mobile | Renter | Booking actions | Partial; tracking detail is incomplete. |
| Request Extension | `37a71b3f1f5d4f1daafda88cb238114f` | Mobile | Renter | Booking action | Partial; no complete request form/status flow. |
| Renter Return Submission | `951ffde1eacd45c981ab4685328b89ca` | Mobile | Renter | No complete routed equivalent | Missing; condition evidence workflow required. |
| Service Booking Status | `de4a65ade43b46c781023c06206fa2ed` | Mobile | Renter | Conditional booking presentation | Partial; dedicated completion/status flow missing. |
| Rate & Review | `498865a3652b4ee58336e1fe15fa2f2f` | Mobile | Renter | Legacy review view | Missing from active routed flow. |
| Raise a Dispute | `9331d75ff9e1413daeee4224eefb7934` | Mobile | Renter | Legacy dispute view/report action | Partial/unwired; evidence form incomplete. |
| Dispute Tracking | `0d4778f2aad946d8863841b4536cc97f` | Mobile | Renter | No routed equivalent | Missing. |
| Messages Inbox | `da08943ad1db43f6b6fd9c1fbd13888b` | Mobile | Shared mobile | Conversation list | Represented. |
| Conversation Details | `1289f9d7020848699a4be676565b9946` | Mobile | Shared mobile | Chat page | Partial; sending remains presentation-level. |
| Owner Dashboard | `07e2b0b748b34b2b8ca7b3fc0e01dbd4` | Mobile | Owner | Owner Dashboard | Represented; some action cards lack detail routes. |
| Owner Listings Hub | `2bdad7198a5847a9a73f70ac5d0b9b9d` | Mobile | Owner | Listings tab | Partial; full status filtering/state incomplete. |
| Create Listing | `0442288955f94e75a4bf3c6c26b0feab` | Mobile | Owner | Create listing flow | Partial; equivalent form exists but persistence/editing incomplete. |
| Create Listing: Pricing & Availability | `eb572ead8ad34232b361e872b83b5227` | Mobile | Owner | Create listing form | Partial; represented within one flow rather than a dedicated step. |
| Create Listing: Review & Publish | `18c06f2f06b14d2f9c94495f282a628e` | Mobile | Owner | Save feedback | Missing as a dedicated review/publish step. |
| Create Service: Step 1 | `5a806f7694774996a6303798f5d042cd` | Mobile | Owner | Conditional create listing form | Partial; service fields exist but not this staged flow. |
| Create Service: Step 2 | `fcdadb1fe1ac4eafb6b31a7aeb41b741` | Mobile | Owner | Conditional create listing form | Partial; package/publish fidelity incomplete. |
| Manage Listing | `a0e82f5cfaef45adb40f67b9963afafb` | Mobile | Owner | Listing list/create flow | Missing as an edit/manage detail screen. |
| Booking Requests | `f5f552f8a8ba4066abc58197fde3a5d9` | Mobile | Owner | Requests tab | Represented. |
| Booking Request Details | `ae78667d5331404bb6255234f2afd256` | Mobile | Owner | Request cards/actions | Partial; detail page and required rejection reason incomplete. |
| Provider Service Requests | `bd4bc2aa841645e5a49b6d31336a2d01` | Mobile | Owner | Requests tab | Partial; no dedicated service-request list. |
| Active Rentals | `bb69f2b4f24d468aac98148b2f49fdba` | Mobile | Owner | Dashboard/request summaries | Missing as an active-order management screen. |
| Pickup & Handover Confirmation | `9fac3fb78cb14d9e94511689938a00b6` | Mobile | Owner | No routed equivalent | Missing. |
| Return Inspection | `cb044d6759a6436d8b5624e0d8703d5a` | Mobile | Owner | No routed equivalent | Missing. |
| Service Request Details & Completion | `0ac63bf4f65b4d378549f210818b13db` | Mobile | Owner | No complete routed equivalent | Missing. |
| Earnings & History | `5ec6ec69b229448092cb9a07bc9997e6` | Mobile | Owner | Dashboard recent earning | Partial; transaction history screen missing. |
| Admin Login | `9fe434782b394e248d0f3f12cf7e9d04` | Desktop | Admin | `AdminApp` login | Represented. |
| Admin Dashboard | `d0ca3eb0502f4a298bbd008b7d53a4cf` | Desktop | Admin | Admin Dashboard | Partial; metrics exist, trends/recent actions limited. |
| Admin: User Management | `a9945c62cb1a4cd896dbef9c1eaae137` | Desktop | Admin | Users destination | Partial; details, filters and reasoned suspension/ban incomplete. |
| Moderation Queue | `151d0acca26b4463af80e8c32155fcbe` | Desktop | Admin | Verification/listing/report tables | Partial; task-specific queue/details missing. |
| Dispute Case Details | `558ea52994454e98870b2ddbe1242ac0` | Desktop | Admin | Disputes generic table | Missing as a participant/evidence/conversation resolution view. |
| Admin: Reports & Finance | `b1af2851ca754babb7c6f4a4cb6b83d1` | Desktop | Admin | Reports + bookings/transactions destinations | Partial; monitoring tables exist, finance/refund/report details missing. |

### Coverage summary

| Classification | Count |
|---|---:|
| Represented / implemented | 20 |
| Partially represented / incomplete | 23 |
| Missing from the active Flutter flow | 12 |
| **Total Stitch screens** | **55** |

Stitch does not contain dedicated screens for every required local/product concept. Notable local or required concepts without a one-to-one Stitch screen include splash/onboarding, Explore as a persistent navigation destination, owner/renter profile drill-down, loyalty/referral, insurance-claim submission/status, bundle management, editable platform settings, review moderation detail, audit-log detail, and several admin destinations represented only through broader Stitch admin screens.

## Recommended implementation order

Batch 1 completed the seven Stitch-backed shared account screens: login, registration, password reset, role selection, KYC gate, profile/settings, and notifications. Batch 2 completed the eight-screen physical-item discovery-to-Pending-request journey, including the dedicated booking-details selection surface and prototype-only simulated authorization. Splash/onboarding, wishlist/comparison, services, and post-booking flows remain outside those approved batches.

1. **Extend the completed renter discovery-to-request foundation.** Batch 2 now covers physical-item search, availability/date selection, booking summary, agreement, simulated authorization, and Pending request creation. Add wishlist, listing comparison, and the excluded service-booking variant in a later approved batch.
2. **Finish physical-item and service post-booking branches.** Add physical tracking, extension, handover/return and condition evidence separately from service completion.
3. **Complete owner supply and request workflows.** Persist create/edit listing state, add request details and rejection reasons, then active-order, earnings, review, dispute, and claim flows.
4. **Replace generic admin tables with task-specific detail screens.** Prioritise identity verification, listing moderation, user suspension, and dispute resolution, including confirmation, required reasons, evidence, and visible state updates.
5. **Integrate remaining communications and trust flows.** Connect reviews, disputes, claims, loyalty, referrals, and deeper settings/help pages to active navigation.
6. **Expand representative state and responsive QA.** Continue mobile checks at 360/390 logical pixels and admin checks at 1024/1440 widths before treating all UI coverage as complete.

## Mapping caveats

- The mapping is semantic, not a claim of pixel parity; screenshots and generated HTML were not imported into Flutter.
- Stitch dimensions use 2x design pixels: typically 780 px wide for a 390 logical-pixel mobile target and 2560 px wide for a 1280 logical-pixel desktop target.
- Several Stitch screens divide one journey into separate pages while Flutter combines it into a stepper, card action, or snackbar. Those are marked partial unless the routed experience is substantively equivalent.
- Batches 1 and 2 used their named Stitch screens as authoritative visual references while preserving native Flutter implementation and existing application logic. Later batches should confirm authority where overlapping Stitch screens remain.
