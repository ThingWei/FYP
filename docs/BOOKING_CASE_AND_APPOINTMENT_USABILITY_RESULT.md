# Booking, case and appointment usability

Follow-up: [Compact booking screens and disputed returns](COMPACT_BOOKING_AND_DISPUTED_RETURN_RESULT.md) updates the shortcut labels, dashboard alignment, condition galleries, saved-address checkout, typography and return-during-dispute behavior. Verification below records the earlier implementation; current results are in the follow-up report.

## What changed

- Renter booking details include **View Owner profile**, using the existing authenticated public-profile page. It shows the profile, not only trust history; existing visibility and blocking rules still apply.
- Physical bookings use one **Pickup & return times** sheet with hour, minute and am/pm dropdowns for both appointments. Each appointment shows its own date. Close discards the sheet changes; **Save times** applies them together and stays visible while the fields scroll.
- The picker supports every minute, including midnight/noon. Both appointments are required and a same-day return must be later than pickup. Changing dates retains the selected times but submission revalidates them. The API still receives strict `HH:mm` values; daily prices, full-day reservations and service scheduling are unchanged.
- Appointment cards fill the available width and show two centred date/time cells. Larger text or narrow space uses separate rows. Booking, checkout and handover displays now pass the relevant dates, including the latest saved rental dates.
- Owners see **Waiting for your approval** for paid pending requests. Unpaid/expired requests address the renter's payment responsibility; scheduled service copy addresses the correct participant. Owner handover wording describes sending the record for renter confirmation.
- Owner Home separates **Awaiting approval** and **Overdue returns**, with independent database-wide counts and destinations. Existing combined summary metadata remains compatible but is not shown as a combined card.
- Rental/service actions use equal-width pairs when they fit, full-width single actions and separate rows at larger text sizes. Status notes sit outside action rows. Long text remains left-aligned; short titles, appointment cells and actions are centred. Desktop booking/Owner/case content is width-constrained.

## Cases and claims

The case header now uses connected **Reported → Response → Review → Decision** icons. It maps to saved case status, including information requests and closed cases. It contains no radio checklist or interactive status control.

The page uses short **Evidence**, **Condition photos**, **Updates** and **Your response** labels. The supporting reference is expandable; participant statements, administrator messages, decisions and amounts remain visible. No case stage implies a refund or automatic finding of fault.

The damage-waiver form is scrollable and keyboard-aware, with **Amount (RM)** and **Damage & repair** fields. Validation and evidence requirements remain unchanged. Text survives validation, evidence-picker cancellation or a failed submission; it clears after a successful claim. The next-step label is **Continue** because selecting evidence still precedes submission.

## Overdue-return disappearance fix

The previous dispute update constructed a partial rental with status `disputed`, losing overdue flags, appointment times and some supporting-record information. The overdue cache then treated it as ineligible and removed it.

Status updates now preserve all current rental fields. A legacy `overdue` status also preserves its effective overdue flag when becoming disputed. After the case POST succeeds, its local record is retained immediately; a background read refreshes the rental and relevant Owner pages/counts. Page number and page size are retained. Failed reads leave the successful case and overdue record available and never repeat the POST.

Account guards, rental revision checks and collection request generations prevent superseded responses from replacing newer state. A pre-dispute active/overdue response cannot undo the known open-case transition. Existing server overdue eligibility already includes unreturned disputed rentals; it remains authoritative for completed/returned/resolved records.

The orders screen has explicit loading, retry and genuine-empty states, retained records during failure and a **View all orders** recovery action. Opening a case does not grant approval controls or perform any payment, refund, return or settlement operation.

## Verification

- Focused API checks: **53 passed**, covering public-profile authorization/privacy, overdue/disputed eligibility and counts, appointment rules and disputes. These ran against isolated temporary databases with external effects disabled.
- Full Flutter suite: **881 passed, 3 skipped**. Final analysis: **No issues found**.
- Main web, administrator web and Android debug builds all passed. Saved AI-model artifact checksums remained unchanged.
- New tests cover the paired picker, every-minute values, noon/midnight, invalid same-day ordering, cancellation, dated displays, role wording, profile navigation, overdue-case navigation, failed refreshes, account changes and retained fields.
- Claim tests exercise 360/390/1024-pixel widths, 1.6x text, keyboard insets, inline errors and preserved input. Connected case stages are checked without radio icons.
- Readable-font previews were rendered at **360/390/1024/1440 pixels** with 1.3x text. Mobile appointment/claim/case/Owner and desktop case/Owner previews were inspected. No overflow remained in the checked views. Private previews: `apps/renthub_flutter/.data/booking-case-previews/`.
- No live database records, account permissions, APIs, schemas, prices, model weights or dependencies were changed. Existing uncommitted work was preserved.
- Real Android keyboard, TalkBack and touch walkthroughs were not performed; automated widget results and Android build success are not device observations.

Final full-check logs: `.data/testing/20261115-143359-47461f4b/`. Focused API, widget and visual logs: `.data/testing/20261115-booking-ux/`. Earlier failed checks remain as historical records; their corrected reruns are separate files. No unrelated Auth0 analyzer errors were observed in the final run.

## Quick walkthrough

1. Create a physical booking, open **Pickup & return times**, select both appointments and save. Check dates/times in checkout and booking details. Open **View Owner profile**.
2. Switch to the actual Owner: verify separate approval/overdue cards and participant-specific pending status. Check action buttons at a narrow width and larger text size.
3. On an unfinished overdue rental, open/report an issue, return to Overdue returns and verify the same item remains with **View case**. A completed transaction must still reject a new dispute.
4. Open an eligible damage-waiver claim, focus Damage & repair with the keyboard visible, enter invalid/long text and verify scrolling, errors and retained values.

Restart/rebuild the app for these UI/controller changes. No migration or data refresh script is required.

## Commit message

```text
fix: simplify booking appointments and preserve overdue case records

- add full Owner-profile access from renter booking details
- replace clock dials with one dated pickup and return selector
- centre appointment cells and balance responsive rental actions
- separate Owner approval requests from overdue returns
- use participant-specific booking status wording
- replace dispute checklists with a concise connected case flow
- make damage claims scroll safely with the keyboard and retain drafts
- preserve rental metadata and overdue pages after reporting issues
- guard background refreshes against stale records and account changes
- add responsive, privacy and navigation regressions and handoff notes
```
