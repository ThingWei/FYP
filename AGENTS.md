# RentHub UI Prototype Instructions

## Project objective

Build a polished, fully navigable UI prototype for RentHub, a multi-category rental marketplace in Malaysia. The prototype must cover all three user interfaces:

1. Renter mobile application
2. Owner mobile application
3. Administrator web portal

Use Flutter and Dart for the mobile application and Flutter Web for the administrator portal. Use realistic local mock data and working navigation. This phase is a UI prototype only. Do not connect real backend APIs, Auth0, MongoDB, Firebase, payment services, AI models, maps, or blockchain services unless the user later explicitly requests integration.

## Working approach

- Inspect the existing repository, source structure, dependencies, routes, and reusable widgets before editing anything.
- Preserve existing working code and follow the repository's established conventions where they are reasonable.
- Do not delete or rewrite unrelated files.
- Prefer extending existing screens and components over creating duplicates.
- Do not add production dependencies without first checking whether the same result can be achieved with Flutter and the packages already installed.
- If the repository does not contain a valid Flutter project, report that clearly and ask before generating an entirely new project.
- Implement the requested UI rather than stopping after a plan or wireframe.
- Use mock repositories or local in-memory data so every major screen can be demonstrated without a backend.
- Keep business logic separate from presentation code, even for mock behaviour.

## Product context

RentHub allows renters to discover and book physical items or services from owners. Physical-item examples include electronics, vehicles, event equipment and clothing. Service examples include photography, catering and tutoring.

The interface must clearly distinguish physical-item rentals from service bookings:

- Physical items may show condition, security deposit, damage waiver, item verification, collection or delivery, rental tracking, extension and return functions.
- Services may show package details, service date, duration, venue or service location and completion status.
- Do not show item condition, item-return controls or physical-item verification for service bookings.
- Use the term `Owner` consistently for the person who supplies either a physical item or a service.

The prototype must support role switching only when a mock user contains both renter and owner roles. Administrator functions must remain in the separate web portal.

## Prototype behaviour

- Every primary navigation item, card, button, tab and list item must lead to the intended screen or perform a visible mock action.
- Use local mock data for listings, users, bookings, payments, messages, notifications, disputes, reviews, verification records and dashboard statistics.
- Use dialogs, bottom sheets, snackbars and confirmation screens to demonstrate actions such as booking, approval, rejection, cancellation, payment, blocking, reporting and dispute submission.
- Destructive actions must show a confirmation dialog.
- Form submissions must validate required fields and then show a realistic success state.
- Do not leave dead buttons unless the control is visually and semantically disabled.
- Do not use network-dependent images. Use local placeholder assets, Flutter icons or stable code-generated placeholders.
- The prototype must remain usable after restart without requiring credentials or external services.

## Visual direction

Use a clean, modern marketplace design that communicates safety, reliability and convenience. The interface should feel professional and approachable, not corporate, futuristic or overly decorative.

### Colour system

Use the following default palette consistently through a shared theme:

- Primary blue: `#2563EB`
- Primary dark blue: `#1D4ED8`
- Primary light blue: `#DBEAFE`
- Very light blue surface: `#EFF6FF`
- White background: `#FFFFFF`
- Main text: `#0F172A`
- Secondary text: `#475569`
- Border and divider: `#E2E8F0`
- Neutral surface: `#F8FAFC`
- Success: `#16A34A`
- Warning: `#F59E0B`
- Error: `#DC2626`
- Information: `#0284C7`

Do not introduce unrelated dominant colours. Status colours may be used only for meaningful feedback. Avoid large gradients, glassmorphism, neon effects and excessive shadows. Blue should guide attention but should not fill every surface.

### Typography and spacing

- Use one clean sans-serif family supported by the project. Prefer the existing project font; otherwise use Flutter's default Material typography.
- Use clear heading levels and readable body text.
- Use an 8-point spacing system, with 4-pixel increments only for compact internal spacing.
- Use consistent corner radii, normally 12 pixels for cards and inputs and 16 pixels for prominent containers.
- Use subtle borders or low-elevation shadows to separate white cards from light backgrounds.
- Keep mobile content margins between 16 and 20 pixels.
- Keep desktop content constrained and aligned instead of stretching text and forms across the full viewport.

### Branding and imagery

- Use `RentHub` as a text-based logo.
- Do not invent a complex logo or download branding assets.
- Use tasteful image placeholders that preserve the intended image ratio.
- Use consistent icons from the existing Flutter or Material icon set.
- Use Malaysian Ringgit formatting such as `RM 120.00`.
- Use Malaysian locations, names and realistic marketplace copy in mock data.
- Do not use lorem ipsum.

## Responsive targets

### Mobile application

- Design primarily for a 390 by 844 logical-pixel viewport.
- Support widths from 360 logical pixels upward without overflow.
- Respect safe areas, keyboard insets and scrollable content.
- Use minimum touch targets of 48 by 48 logical pixels.
- Avoid fixed heights for text-heavy cards and forms.

### Administrator web portal

- Design primarily for desktop and laptop browsers at 1440 by 900 pixels.
- Remain usable at 1024-pixel width.
- Use a persistent sidebar on wide screens and a drawer or compact navigation pattern on narrower screens.
- Support Google Chrome and Microsoft Edge layouts.
- Use tables for dense administrative data, but provide responsive horizontal scrolling or card alternatives when necessary.

## Shared UI components

Create or reuse shared components rather than repeating styles. The component set should include:

- RentHub text logo
- Primary, secondary, outline, text and destructive buttons
- Search bar with filter action
- Listing card and compact listing row
- Category chip and filter chip
- Verification badge
- Trust-score indicator
- Status badge for booking, rental, payment, dispute and verification states
- Price and deposit summary
- User avatar and profile header
- Empty, loading, error and success states
- Notification tile
- Message bubble and conversation tile
- Form field, dropdown, date selector and image placeholder
- Confirmation dialog and bottom sheet
- Desktop sidebar and top application bar
- Mobile bottom navigation bar

All reusable components must use the shared theme. Do not hard-code colours repeatedly inside feature screens.

## Common and authentication screens

Provide these shared screens or states:

- Splash screen with the RentHub text logo
- Short onboarding presentation
- Login screen
- Registration screen
- Forgot-password screen
- Role selection or active-role switching for eligible users
- Notification centre with individual removal and clear-all actions
- User profile and profile editing
- Identity-verification status
- Application settings
- Help and support information

Authentication is simulated. A mock login should allow the reviewer to enter the renter, owner or administrator experience without contacting Auth0.

## Renter mobile application

Use a bottom navigation structure with these five destinations:

1. Home
2. Explore
3. Bookings
4. Messages
5. Profile

The renter prototype must include the following screens and flows:

- Home with search, categories, nearby listings, recommendations and promoted listings
- Browse and search results
- Filters for category, location, price, availability, verified owner and physical item or service
- Listing details with images, price, owner profile, verification badge, trust score, reviews, location and availability
- Wishlist
- Listing comparison
- Booking date or service-schedule selection
- Fulfilment selection for applicable physical items
- Booking summary and price breakdown
- Simulated checkout and payment result
- Active and historical bookings
- Physical-item rental tracking
- Rental extension request
- Return confirmation and condition evidence placeholders
- Service completion confirmation
- Conversation list and messaging
- Interview-style communication is not part of RentHub and must not be added
- Review and rating submission
- Dispute submission with evidence placeholders
- Insurance-claim status where applicable
- Loyalty points and referral information
- Block owner and report listing actions

The renter home screen should prioritise discovery. Use horizontally scrollable category or recommendation sections only when they remain easy to scan and accessible.

## Owner mobile application

Use a bottom navigation structure with these five destinations:

1. Dashboard
2. Listings
3. Requests
4. Messages
5. Profile

The owner prototype must include the following screens and flows:

- Dashboard with listing, booking, revenue and action-needed summaries
- Listing list with active, draft, pending-review and inactive states
- Create and edit physical-item listing
- Create and edit service listing
- Image-placeholder management
- Availability management
- Suggested-price display
- Item-verification result for applicable physical items
- Promotional-discount configuration
- Bundle-listing management where supported by the existing project
- Incoming booking requests
- Booking-request details
- Approve or reject booking with a reason
- Active rental or service order management
- Physical-item handover and return status
- Extension-request approval or rejection
- Service-delivery completion
- Simulated earnings and transaction history
- Conversation list and messaging
- Renter profile, verification badge and trust score
- Review submission
- Dispute response and evidence placeholders
- Insurance-claim submission where applicable
- Notification centre

Physical-item and service listing forms must conditionally show only relevant fields.

## Administrator web portal

Use a left sidebar with these destinations:

1. Dashboard
2. Verification
3. Users
4. Listings
5. Bookings and Transactions
6. Disputes and Claims
7. Reports
8. Reviews
9. Platform Settings
10. Audit Logs

The administrator prototype must include:

- Dashboard with key statistics, trends, recent actions and pending-work summaries
- User directory with search, filters and account-status actions
- Identity-document review with OCR-result placeholders
- Approve, reject or request resubmission actions
- Listing moderation and listing details
- Physical-item verification review
- Booking and transaction monitoring
- Dispute review with participant details, evidence and conversation history
- Insurance-claim review
- User, listing, review and message reports
- Review moderation
- Account suspension or banning with a required reason
- Platform-setting management
- Append-only audit-log viewer

Administrative actions must be easy to distinguish from read-only information. Approval, rejection, suspension, refund and resolution actions must require confirmation and then update the mock UI state.

## Mock data requirements

Create a central mock-data source rather than embedding unrelated sample objects in every screen. Include enough data to demonstrate:

- Verified and unverified users
- Renter-only, owner-only and dual-role accounts
- Physical-item and service listings
- Available, unavailable, draft and pending-review listings
- Pending, approved, rejected, cancelled, active, completed and disputed bookings
- Successful, pending and refunded transactions
- Read and unread messages and notifications
- Open and resolved disputes
- Pending, approved, rejected and resubmission-required identity documents
- Reviews with different ratings and moderation states

Use consistent identifiers and relationships across screens. A listing shown on the home screen must display the same owner, price and status on its details screen. A booking must reference an existing mock user and listing.

## Accessibility and usability

- Maintain sufficient contrast between text, icons and backgrounds.
- Do not communicate status using colour alone. Pair status colours with text or icons.
- Add semantic labels to important interactive controls and images.
- Support system text scaling without clipping important information.
- Keep form labels visible and provide clear validation messages.
- Ensure keyboard navigation and focus states work in the administrator web portal.
- Use concise, understandable language for actions and errors.
- Avoid crowded dashboards. Prioritise information and use progressive disclosure for details.

## Flutter implementation guidance

- Use Material 3 unless the existing application has a deliberate compatible design system.
- Define application colours, typography, spacing and component styles centrally.
- Prefer small reusable widgets over very large `build` methods.
- Use `const` constructors whenever possible.
- Keep mock models, mock repositories, screens, shared widgets and theme files separated.
- Follow a feature-oriented structure where it fits the existing repository.
- Use named routes or the repository's existing router consistently.
- Do not introduce a second navigation framework.
- Avoid hard-coded viewport assumptions. Use `LayoutBuilder`, `MediaQuery`, flexible widgets and sensible constraints.
- Avoid unnecessary state-management frameworks for static mock behaviour. Reuse the existing state-management approach if one is already present.
- Keep visible strings in one organised location when the existing project already supports localisation or string constants.
- Resolve all overflow warnings, unbounded constraints and runtime exceptions.

A reasonable structure for a new or currently unstructured UI layer is:

```text
lib/
  core/
    theme/
    routing/
    constants/
  shared/
    models/
    mock_data/
    widgets/
  features/
    auth/
    renter/
    owner/
    admin/
```

Adapt this structure to the current repository rather than reorganising working code without a clear reason.

## Quality checks

After implementation, run the commands that apply to the repository. For a standard Flutter project, run:

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter build web
```

Also perform a visual and interaction check of the major flows:

- Renter searches for a listing, opens its details, creates a booking and completes simulated payment.
- Owner creates a listing, reviews a booking request and approves or rejects it.
- Renter and owner exchange mock messages.
- Renter submits a mock dispute.
- Administrator reviews verification documents and resolves a mock moderation item.
- Administrator portal remains usable at 1440-pixel and 1024-pixel widths.
- Mobile screens remain usable at 390-pixel and 360-pixel widths.

Do not claim completion while analyzer errors, broken routes, dead primary actions, visible overflows or inconsistent mock records remain.

## Completion criteria

The UI prototype is complete only when:

- All three interfaces are accessible.
- Primary navigation works in each interface.
- The required major screens and user flows are implemented.
- The shared blue-and-white design system is applied consistently.
- Physical-item and service interfaces show the correct conditional information.
- Representative loading, empty, error and success states are included.
- Mock actions visibly update the relevant screen state.
- The code is formatted and passes the applicable Flutter analysis and tests.
- No real secrets, credentials or personal data are added.

When handing off the work, summarise the implemented screens, important design decisions, mock limitations, validation commands and any remaining issues. Include screenshots or preview instructions when the environment supports them.
