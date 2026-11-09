# Tap-to-read help

Implemented on 9 November 2026 for RentHub's live interfaces. Optional section introductions now use a question-mark button beside the heading. Existing working changes have been retained. This change adds no dependency, endpoint, database change or model change.

## Interaction

- The shared `RentHubSectionHeader` and `RentHubHelpButton` use the existing theme and Material question-mark icon. Each help button has a minimum 48 × 48 target and an accessible **About [section]** name.
- Tap, Enter, Space or the screen-reader action opens persistent help. Hover text only identifies the button; it is not the explanation.
- At widths of at least 600 logical pixels, short help uses an anchored panel, at most 360 pixels wide. Text is measured at the current text size; the body must fit within 240 pixels. The panel opens above or below the button and stays within safe margins. Insufficient room uses the dialog instead.
- Smaller screens, longer explanations and enlarged text that cannot fit use a scrollable dialog. An open desktop panel also falls back to a dialog if the window, text size, keyboard inset or safe area changes.
- Outside tap, Back/Escape and the labelled Close control dismiss help. Keyboard focus returns to the triggering help button, without jumping back to an earlier form field. Repeated taps cannot stack help routes, and repeated closing cannot dismiss the underlying page.
- Opening help performs no API request or submission. It preserves the underlying screen, scroll position, input values, filters, selected images and saved product selection.

## Description coverage

| Live area | Description moved to help |
|---|---|
| Sign-in and administrator sign-in | Welcome/account instructions |
| Registration | Create Account, Security & Contact and Choose Role introductions |
| Password reset | Initial email-step introduction; later code/password instructions stay visible |
| Owner Home | Marketplace overview beside the greeting |
| Physical/service listing forms | Details, Photos, Product when applicable, Pricing, Location and availability |
| Product comparison details in the listing form | Optional version/package explanation; help does not expand the containing tile |
| Price suggestion | How this estimate was calculated; the amount, range and important limitations stay visible |
| Listing camera | Photo-taking guidance in a question-mark action |
| Public contact profile | Before you book advice |
| Profile | Application settings explanation; tapping help does not navigate |
| Trust page | How it works and minimum-history explanation; actual scores and insufficient-history states stay visible |
| Handover/return evidence | Optional introductory photo advice; required evidence remains visible |
| Agreement page | Document introduction; saved terms and acceptance history remain visible |
| Dispute progress | Initial explanation before a case exists; an existing case's next action stays visible |
| Admin record lists | Shared record/verification introduction across all supported collections |
| Admin detail sections | Extended the existing shared heading with optional help support; record fields remain visible |
| Admin dashboard | Platform overview, booking-chart scope and monthly demo-payout explanation |
| Admin reports | Operational-report and safety-report introductions |
| Platform settings | Introduction, Maintenance mode, listing-category guidance and rewards introduction |
| Rental-price updates | Update schedule and source-list introduction; disabled/update-failure reasons remain visible |
| Manual price import | Optional CSV preparation introduction; required format and confirmation instructions remain visible |

The audit also covered Home/Explore and recommendation sections, booking/order/payment pages, notifications/messages, addresses/maps, verification/scanners, reviews, rewards and support. Descriptions that communicate required actions, record information, errors or limitations remain visible there. This is a semantic cleanup, not a blanket removal of grey text. Older prototype feature screens were left unchanged; the common authentication screens continue to serve the live app.

## Information deliberately kept visible

- Status, amount, dates, public approximate areas, record labels and actual history.
- Required consent, verification/review confirmations, code/password rules, upload formats/counts/limits and field validation.
- Checkout simulation, the payment deadline, Owner approval requirements and disabled-action reasons.
- Empty/loading/error states, retry actions and unavailable model/provider guidance.
- Approximate-location and GPS accuracy/privacy guidance; exact pins and protected documents retain existing access rules.
- Important AI limitations, including broader price comparisons, missing real validation, recognition versus authenticity, and advisory manipulation-risk results.
- Required agreement wording and acceptance; current dispute next steps, completion cutoffs and condition-record limitations.
- Short chart notices identifying demonstrations and separating demo payouts from real sales or platform revenue.

The existing review-edit deadline remains visible, with its wording simplified to “You can edit a submitted review for 24 hours.” CSV read errors are shown with the saved-price list, while file-operation errors stay with the import controls, avoiding a duplicated error message after the layout change.

## Verification

Verification uses isolated fixtures, not personal documents or live account changes. No manual result in the existing P0 sheets was marked passed.

- `section_help_test.dart`: popup/dialog selection, persistent display, 48-pixel targets, outside dismissal, Close, Enter/Space, Escape/Back, named semantics, focus restoration, repeated taps/close, resize, four screen edges, scroll retention and long text.
- `inline_help_coverage_test.dart`: real listing form and admin record list at 360/390/1024/1440 pixels with 150% text; retained draft values/photos and records; no API writes or extra reads from help. Tests also cover nested import/profile controls and unchanged sign-in input.
- Existing account, pricing and CSV widget tests were updated to open the new help button. They continue to check important visible warnings, explicit price acceptance, unavailable estimates, preserved photos/drafts and file retry.
- Full Flutter run and builds: see final verification below.

### Final verification

Command: `./scripts/test-renthub.ps1 -Suites flutter -Builds`

Private execution pack: `.data/testing/20261109-210528-b6bf2349/`.

| Check | Observed result |
|---|---|
| Full Flutter tests | **712 passed, 3 existing skips**, no failures |
| Flutter analysis | Passed; no analyzer issues |
| Main web build | Passed |
| Administrator web build | Passed |
| Android debug build | Passed |
| Deployed-model checksums | Unchanged |
| Diff whitespace check | Passed |

The shared component has 14 interaction/layout tests; live coverage adds 11 more. Separate fixture renders cover listing help and administrator records at 390/1440 pixels with 130% text, plus sign-in at 390 pixels. Five render cases passed; the resulting images were inspected for readable help, alignment and clipping. Preview images are private under `apps/renthub_flutter/build/ui-checks/inline-help-*.png`; they contain only test fixtures. The mobile/desktop coverage tests additionally exercise 360/1024 widths at 150% text, and the component tests exercise 180% mobile text and long desktop help.

No new unrelated test or analyzer failures were observed in this run. The three skips remain recorded in the execution pack; they are not counted as passes. Real Android touch, TalkBack and a browser screen reader were not exercised during this change. API/AI suites were not rerun for this presentation-only task; no server code or model files were changed by it.

## Walkthrough

1. Open an Owner listing and tap the question mark beside **Details**, **Product** or **Pricing**. Close help and confirm the draft is unchanged.
2. Open a price suggestion. Its amount and limitations remain visible; use the question mark beside **How this estimate was calculated** for the supporting explanation.
3. Open an administrator record list or **Platform Settings**. Short desktop help appears beside its heading; narrow the window or increase text size to check dialog recovery.
4. On Android, confirm Back closes only help. Check a real screen reader and device keyboard during the final device walkthrough; widget semantics and keyboard tests do not replace assistive-technology testing.

## Commit message

```text
feat(ui): add accessible tap-to-read help across live RentHub screens

- share responsive question-mark help across renter, Owner, auth and admin sections
- keep required guidance, record details and AI/payment/location warnings visible
- preserve drafts and focus with persistent, dismissible popups and dialogs
- cover keyboard, semantics, screen edges, large text and nested controls
- document coverage, retained notices and verification results
```
