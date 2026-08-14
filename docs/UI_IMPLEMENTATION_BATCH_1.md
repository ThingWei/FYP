# Priority UI Implementation Batch 1

## Approval status and scope

**Status:** Proposed for approval; no Flutter implementation has started.

Batch 1 contains seven closely related shared mobile account screens. It follows the first revised priority in `STITCH_UI_COMPARISON.md`: complete authentication/account foundations before marketplace flows. These screens establish the common theme, form, feedback, app-bar, card, and navigation patterns used by both renter and owner experiences.

Stitch project: `2362719991600770029` (`Multi-Category Rental Marketplace`). Every selected screen was retrieved directly with Stitch MCP `get_screen` on 14 August 2026 because `list_screens` currently returns `Request contains an invalid argument`. The screenshots and generated markup were inspected as design references only. Stitch was not modified, and Stitch HTML/CSS will not be copied into Flutter.

## Selected screens

| Priority | Stitch screen | Stitch screen ID | Size returned by Stitch | Current Flutter coverage |
|---:|---|---|---|---|
| 1 | Login | `7c58ffe68b8a4fcdbcb477c7a3b50e2f` | Mobile, 780 x 1768 | Routed but visually incomplete; registration and reset actions are dead ends. |
| 2 | Create Account | `5404184524d146ce9710a1057a284887` | Mobile, 780 x 1768 | Placeholder exists but is unwired and has no form. |
| 3 | Forgot Password & Reset | `aec18e52f24a47429524323a71626503` | Mobile, 780 x 1768 | Missing; login only shows a snackbar. |
| 4 | Choose Your Role | `5d96cd5a932a43488f8a6ab9413cfa65` | Mobile, 780 x 1768 | Role state exists, but there is no matching routed selection screen. |
| 5 | KYC Verification Gate | `f56ec35b312d4963b03a3ab6cbae7bca` | Mobile, 780 x 2090 | Missing. |
| 6 | Profile & Settings | `31ee7cf6f6da4d72a7a419781cce6b6c` | Mobile, 780 x 2746 | Basic shared profile exists; most actions are snackbar placeholders. |
| 7 | Notifications | `1e08ec672d5b4e1d96db269700749736` | Mobile, 1080 x 1768 | Partial; renter entry, dismissal, and clear-all exist, but content/filtering and owner entry are incomplete. |

The Stitch artwork uses 2x design pixels for most screens, corresponding to the 390 logical-pixel mobile target. Notifications has a wider exported canvas, so its layout should be interpreted responsively rather than copied at a fixed width.

## Visual and interaction findings

### 1. Login — `7c58ffe68b8a4fcdbcb477c7a3b50e2f`

- Centered authentication card on the neutral `#F8FAFC` surface, constrained to a comfortable mobile width.
- RentHub text mark at the top, short welcome copy, labelled email and password fields, leading icons, password visibility control, and inline “Forgot Password?” link.
- Full-width primary **Log In** button, divider with “or”, pale-blue secondary **Continue with Auth0** button, and a Create Account text link.
- Required states: pristine, focused field, invalid email/password with visible field error, password obscured/revealed, submitting/disabled button, repository error, and successful authentication.
- Navigation: Forgot Password -> reset flow; Create Account -> registration; successful login -> existing authenticated role shell. The Auth0 button remains a visible mock action in this prototype and must not connect to Auth0.
- Local difference to resolve: the current renter/owner segmented control is not present in the Stitch login design. Preserve `AuthController.selectedRole`; role choice should move to the dedicated role screen rather than be deleted from business logic.

### 2. Create Account — `5404184524d146ce9710a1057a284887`

- Three-step card flow with a thin progress indicator and persistent RentHub header.
- Step 1: full name and email address. Step 2: security/contact, including Malaysian phone prefix, password visibility, and password guidance. Step 3: renter/owner radio cards plus Terms of Service and Privacy Policy consent.
- Completion state: prominent success icon, **Account created!** message, supporting copy, and a continue action.
- Required states: field validation, step progress, back/continue, role selected/unselected, terms unchecked/checked, submit loading, repository failure, and account-created success.
- Navigation: Login -> Create Account; step completion stays within the registration route; successful mock registration may enter the selected role shell or return to Login according to the existing `AuthController.register` result. The implementation should retain the current controller/repository contract.

### 3. Forgot Password & Reset — `aec18e52f24a47429524323a71626503`

- Four states in one coherent flow: request reset email, check inbox/enter six-digit code, create and confirm a new password, and password-updated success.
- Uses a compact top RentHub wordmark, centered bordered card, circular security/history icon, concise instructional copy, 50 px primary actions, and a return-to-login link.
- Password state includes visibility control and requirement feedback. Code state includes six single-character fields and resend action.
- Required states: invalid/unknown email, sending, email sent, incomplete/invalid code, resend cooldown feedback, password mismatch/weak password, updating, error, and success.
- This remains entirely local/mock. No email, OTP, Auth0, or backend reset integration is authorized in this batch.

### 4. Choose Your Role — `5d96cd5a932a43488f8a6ab9413cfa65`

- Centered RentHub card with title “How will you use RentHub?”, explanatory copy, and two large selection cards: rent/book as renter or list/offer as owner.
- Each role card has a contextual icon, title, short description, and radio indicator. The Continue button is visibly disabled until a role is selected.
- Required states: no selection, renter selected, owner selected, disabled/enabled Continue, and transition loading/error if role activation ever becomes asynchronous.
- Navigation: registration step can reuse the role-card component; dual-role accounts can open the standalone screen from Profile’s switch-mode row. Renter-only and owner-only accounts must not see role switching.

### 5. KYC Verification Gate — `f56ec35b312d4963b03a3ab6cbae7bca`

- Standard back app bar with centered RentHub title, large outlined verification icon, heading, explanation, and a bordered benefit card.
- Benefit rows communicate secure bookings, verified community members, and faster dispute support with icons plus text; a separate prototype notice explicitly says no real ID documents are uploaded or stored.
- Bottom actions: primary **Verify Identity** and pale-blue **Not Now**. The Stitch flow also contains a verification-success state.
- Required states: initial gate, mock verifying/loading, mock verified success, error/retry, and deferred/not-now return.
- Navigation: opened from Profile -> Identity Verification and optionally after registration for actions that require verification. In Batch 1 it must be a mock gate only and must not upload documents or call verification services.

### 6. Profile & Settings — `31ee7cf6f6da4d72a7a419781cce6b6c`

- Uses the normal five-destination mobile shell with Profile selected.
- Profile header contains avatar, user name, “Verified Renter” status, member-since text, and a trust-score card.
- Bordered sections cover Personal Info with Edit, Identity Verification with verified status, Addresses with Manage, Payment Methods with Manage, switch-to-owner mode, Help & Support, Security, and destructive Sign Out.
- Required states: verified/unverified/pending verification, role switch available/hidden, missing address/payment empty variants, profile edit success/error, and sign-out confirmation.
- Profile editing, addresses, payment methods, help, and security may route to lightweight local placeholder/detail pages only when the action visibly works. No real payment method or personal identity integration is in scope.
- Sign Out must require confirmation and invoke the existing `AuthController.logout`; it must not bypass repository/controller logic.

### 7. Notifications — `1e08ec672d5b4e1d96db269700749736`

- Large RentHub/Notifications heading, **Mark all read** action, and horizontally scrollable filter chips for All, Bookings, Messages, and Promotions.
- Notifications are grouped by Today and Yesterday. Cards use semantic leading icons or avatars, title, supporting text, timestamp, and a blue unread dot; read cards omit the dot and use quieter presentation.
- Uses the renter five-destination navigation in the Stitch reference. In Flutter this page should be reachable from both renter and owner shells without replacing either role’s correct five destinations.
- Required states: mixed read/unread, filtered results, mark-all-read success, individual removal with undo, empty filter, global empty state, loading, and error/retry.
- Notification taps should navigate to an existing relevant destination when one exists; otherwise they should perform an explicit mock detail action rather than be dead.

## Flutter file mapping

### Reuse and update

| Existing file | Planned treatment | Reason |
|---|---|---|
| `lib/core/theme/app_theme.dart` | Update | Keep the existing RentHub palette; expand typography and component themes. Change the unsupported hard-coded Roboto choice to project/default Material typography unless a bundled font is later added. |
| `lib/app/app.dart` | Update minimally | Preserve `Consumer<AuthController>` and authenticated role-shell selection; add explicit navigation into the account flow without changing authentication ownership. |
| `lib/modules/user/views/login_screen.dart` | Update | Rebuild with shared auth scaffold/fields/buttons and real routes to registration/reset while retaining controller validation and login. |
| `lib/modules/user/views/register_screen.dart` | Replace placeholder implementation | Implement the inspected multi-step native Flutter form while keeping the existing file and `AuthController.register`. |
| `lib/modules/user/controllers/auth_controller.dart` | Preserve; extend only if UI state cannot remain local | Existing login/register/logout/role methods remain authoritative. Do not duplicate authentication state inside screens. |
| `lib/modules/user/repositories/auth_repository.dart` | Preserve | Keep mock/live boundary and existing method contracts; no external authentication integration. |
| `lib/shared/models/domain_models.dart` | Preserve existing models | Do not reshape `User` or business models for visual convenience. Add UI-only view data separately if needed. |
| `lib/features/renter/renter_app.dart` | Update and split account widgets out | Replace embedded `ProfilePage` and `NotificationsPage` implementations with imports/reusable account screens; preserve renter feature logic and five-tab shell. |
| `lib/features/owner/owner_app.dart` | Update minimally | Reuse the shared profile/notifications screens and connect the owner bell; preserve owner shell and feature logic. |
| `lib/shared/widgets/renthub_components.dart` | Refactor carefully | Keep existing public widgets used by feature pages; move/extend common primitives without breaking listing/status/dialog consumers. |
| `lib/shared/widgets/common_widgets.dart` | Consolidate or retire duplicates during implementation | It currently duplicates `StatusBadge`; callers must be checked before removal or renaming. |
| `lib/shared/mock_data/mock_data.dart` | Extend | Replace notification strings with consistent local notification view data; keep existing listing/booking records unchanged. |
| `test/auth_controller_test.dart` and `test/app_widget_test.dart` | Extend | Protect existing authentication behavior and add navigation/form-state coverage. |

### Proposed new presentation files

The exact names may be adapted to repository conventions during implementation, but the proposed feature-oriented boundary is:

```text
lib/features/account/
  views/
    forgot_password_screen.dart
    role_selection_screen.dart
    verification_gate_screen.dart
    profile_screen.dart
    notifications_screen.dart
  widgets/
    auth_scaffold.dart
    role_option_card.dart
    profile_section_card.dart
    notification_tile.dart
lib/shared/widgets/
  renthub_buttons.dart
  renthub_form_fields.dart
  renthub_app_bars.dart
  renthub_feedback_states.dart
  renthub_navigation_bar.dart
```

Registration remains under `modules/user/views/register_screen.dart` to preserve the existing authentication module. If moving it becomes useful later, keep a compatibility export and avoid breaking imports/tests.

## Routes and navigation

The active app currently uses `MaterialPageRoute` and root authentication state rather than a configured `GoRouter`. Batch 1 should use that existing navigation approach and must not introduce a second active routing framework.

Proposed route semantics:

```text
Login
├─ Forgot Password -> Request -> Code -> New Password -> Success -> Login
├─ Create Account -> Details -> Security -> Role/Terms -> Success
└─ Successful login/register -> existing RenterShell or OwnerShell

RenterShell/Profile or OwnerShell/Profile
├─ Identity Verification -> KYC Gate -> mock success -> Profile
├─ Switch Mode (dual-role only) -> Choose Your Role -> selected shell
├─ Notifications (bell entry from either shell)
└─ Sign Out confirmation -> AuthController.logout -> Login
```

Navigation rules:

- Use `Navigator.push`, `pop`, and replacement only where required by the completed flow; do not stack duplicate role shells.
- Preserve the renter bottom navigation labels Home, Explore, Bookings, Messages, Profile.
- Preserve the owner bottom navigation labels Dashboard, Listings, Requests, Messages, Profile.
- Shared account detail pages may omit bottom navigation while pushed; Profile and Notifications should show the correct role shell context where appropriate.
- Important controls receive semantic labels, predictable focus order, and at least 48 x 48 logical-pixel touch targets.

## Reusable component plan

### RentHub colour theme

- Keep the existing shared palette in `AppColors`: primary `#2563EB`, dark primary `#1D4ED8`, light primary `#DBEAFE`, very-light-blue surface `#EFF6FF`, white, neutral `#F8FAFC`, text `#0F172A`, secondary text `#475569`, border `#E2E8F0`, and semantic success/warning/error/info colours.
- Resolve Stitch token differences in favour of the project instructions: do not adopt Stitch’s alternate `#1A4ED8`/`#0037AE` values as new scattered screen constants.
- Use colour only with text/icon status cues. Cards remain white with subtle borders and little or no elevation.

### Typography

- Centralize display/headline/title/body/label styles in `ThemeData.textTheme` with readable Material typography and strong hierarchy.
- Use the existing/default sans-serif rather than adding a network font or new dependency. Remove the assumption that Roboto is bundled unless verified.
- Support text scaling without fixed text containers or clipped actions.

### Buttons

- Native `FilledButton`, `OutlinedButton`, and `TextButton` wrappers for primary, secondary/pale-blue, text, and destructive actions.
- Minimum height 48–50 logical pixels, 10–12 px radius, full-width option, leading/trailing icons, loading spinner, and disabled state.
- Destructive sign-out continues to use the shared confirmation-dialog pattern.

### Form fields

- Shared labelled `TextFormField` patterns for email, password, phone, OTP, and confirmation fields.
- Persistent labels, leading icons where useful, password visibility, autofill hints, correct keyboard types, inline validation, focus/error borders, and accessible semantics.
- OTP input should support paste/backspace/focus progression without six independent business-state sources.

### Cards

- Shared bordered surface card with 12 px radius and flexible padding.
- Specialized role option, benefit, profile section, trust score, and notification cards compose the shared surface rather than hard-code colours.
- Card actions use `InkWell`/`ListTile` with clear selected, unread, disabled, and pressed states.

### App bars

- Compact branded auth header, standard back app bar, and role-shell header variants.
- Centered title only where shown by Stitch; notification and profile actions remain keyboard/semantics accessible.
- Continue using the RentHub text mark; do not import the Stitch logo bitmap.

### Bottom navigation

- Extract a shared wrapper around native `NavigationBar`, parameterized by the renter/owner destination lists.
- Preserve each role’s five required destinations and selected index; do not use the malformed icon-font labels visible in the raw Stitch export.
- Keep content within `SafeArea` and maintain minimum touch sizes at 360 px width.

### Loading, empty, success, and error states

- Create shared `LoadingState`, `EmptyState`, `SuccessState`, and `ErrorState` presentations with icon, title, message, and optional action.
- Reuse them for authentication submission, reset completion, KYC success/error, notification empty/filter-empty, and profile action feedback.
- Keep controller/repository errors visible and retryable. Snackbars remain appropriate for small reversible actions such as notification removal with Undo, but not for entire missing screens.

## Business-logic preservation

- Keep `AuthController`, `AuthRepository`, `MockAuthRepository`, `User`, `UserRole`, dependency injection, and authenticated shell selection intact.
- Forms call the existing `login`, `register`, `selectRole`, and `logout` methods. UI-local step state must not replace controller state.
- Do not connect Auth0, email delivery, OTP, KYC, document upload, payment, backend APIs, or new persistence services.
- KYC, password reset, profile management, and notification updates are explicit in-memory prototype actions.
- No production dependency should be added; the current Flutter/Material/provider stack is sufficient.

## Implementation order

1. Expand the shared theme and primitives: typography, button variants, fields, cards, app bars, navigation wrapper, and feedback states.
2. Implement Login and wire Create Account/Forgot Password navigation while preserving controller-driven loading/error behavior.
3. Replace the registration placeholder with the three-step form, role cards, validation, terms consent, and success state.
4. Implement the four-state mock password-reset flow.
5. Implement the reusable role-selection screen and connect it only where role eligibility permits.
6. Implement KYC gate and mock verification states; connect from Profile.
7. Extract and rebuild shared Profile & Settings, then connect both renter and owner shells including confirmed logout.
8. Rebuild Notifications with typed mock data, filters, read state, removal/undo, empty/error states, and both-role entry points.
9. Add widget/controller tests, run formatting/analyzer/tests/build, and perform mobile visual QA.

## Verification steps

### Automated

Run from `apps/renthub_flutter`:

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
flutter build web
```

Add or update tests for:

- Login validation, password visibility, controller loading/error, and successful shell transition.
- Registration step validation, role/terms gating, controller call, and success state.
- Reset email, OTP, new-password validation, resend, error, and completion states.
- Role screen disabled/enabled Continue and dual-role-only switching.
- KYC verify/not-now/loading/success/error behavior.
- Profile verified/pending variants, action navigation, sign-out confirmation, and `logout` call.
- Notification filters, read/unread changes, mark-all-read, dismiss/undo, empty and error states.
- Renter and owner five-destination navigation remains unchanged.

### Visual and interaction QA

- Test every selected screen at 390 x 844 and 360 px logical width with no overflow.
- Test system text scaling, keyboard appearance/insets, scrolling, autofill, focus order, back navigation, and disabled controls.
- Confirm all primary buttons, links, cards, filters, app-bar actions, and bottom-navigation destinations work or are visibly disabled.
- Confirm error is not communicated by colour alone and important controls/images have semantic labels.
- Confirm all screens work after restart with mock data and without credentials or network access.
- Compare the Flutter result with the seven retrieved Stitch screenshots for hierarchy, spacing, content, state coverage, and navigation—not HTML/CSS parity.

## Approval decision requested

Approve this seven-screen shared account batch before any Flutter source changes. After approval, implementation should remain limited to these screens, their navigation, their necessary shared components, mock view data, and proportional tests.
