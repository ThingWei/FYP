# Administrator photo review and case workspace

Updated 17 November 2026.

## Photo review

Open a listing in **Admin → Listings → details**. A saved current-format assessment appears with the record. The panel automatically ensures missing work, receives queue updates and continues checking beyond the former two-minute polling limit. Returning from a gallery or dialog refreshes the assessment. Backgrounding the application pauses polling, and account changes invalidate pending responses.

New checks run under the existing shared allowance and provider deadlines. Admin-opened jobs receive queue priority and wake the existing worker. A completed current snapshot is reused without waiting for AI-service configuration checks. Failed or uncertain requests require explicit retry. Opening a listing does not restart those attempts.

The endpoint `POST /api/v1/admin/listings/:id/photo-review` accepts optional `intent=ensure|retry`. Omission retains the previous explicit-retry behavior. Ensure creates or reuses the current job and can recover configuration-only failures. Status refreshes use the existing read-only listing-detail endpoint.

### Findings tied to the correct photos

The internal processing contract is `renthub-item-vision-v3`.

- Every supplied photo requires one result, with a unique valid photo number, assessed/unassessable status, short observations and concerns.
- Comparisons involving several photos have a separate result with multiple distinct valid references.
- Validation rejects missing views, repeated view numbers, out-of-range references, malformed findings and prohibited claims or personal information.
- The UI shows the selected photo under **By photo**, with its observations and concerns. **Across-photo notes** identifies every relevant image.
- Compatibility fields for older admin clients contain per-photo findings only. Set-wide observations are kept separate.
- Existing historical jobs remain stored. The versioned snapshot prevents older-format comments from becoming current results. Opening an eligible listing requests the new format once under the normal shared limits.

This validation establishes output structure and attribution boundaries. Accuracy of the actual visual observations still requires reviewed real-photo evaluation.

### Listing gallery

The separate **View photos** action was removed. The record section is named **Listing photos**, and selecting a thumbnail opens the existing full-screen black gallery on that image. Swipe, zoom, keyboard arrows, Escape and Close retain their existing behavior. Protected documents elsewhere continue using their existing viewers.

## Central case workspace

Open a dispute or damage-waiver claim from the existing **Disputes & Claims** queues. Both lead to the same dedicated case page. Claim entries initially show the Decision tab with the claim decision first.

| Tab | Contents |
| --- | --- |
| Overview | Participants, issue, dates, description, held funds, linked claim, saved decision and activity |
| Evidence | Reported attachments, handover, return, service milestones where applicable, claim evidence and participant responses |
| Conversation | Paginated messages belonging to the case's booking |
| Decision | Inline case actions and a separate linked claim decision |

Decision forms show fields appropriate to the chosen action. A short confirmation summarizes the action before submission. Notes and entered amounts survive failed requests and section changes. Successful actions refresh the workspace, queues and dashboard through the existing controller revision mechanism. Queue filters and page selection are retained when returning.

Desktop decision forms use two columns. Narrow layouts stack the forms and retain readable controls with increased text size. Activity, responses and conversation each have independent loading, retry and pagination, defaulting to 20 records with 10/20/50 choices.

### Read-only case interfaces

All new routes require an authenticated administrator.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/v1/admin/cases/:id` | Approved projections for the case, booking/rental context, claim, held balance and action eligibility |
| `GET /api/v1/admin/cases/:id/conversation?page=1&limit=20` | Stable, booking-scoped conversation pagination |
| `GET /api/v1/admin/cases/:id/activity?page=1&limit=20` | Case and claim audit activity |
| `GET /api/v1/admin/cases/:id/activity?kind=responses&page=1&limit=20` | Paginated participant responses and their evidence |

Case reads perform no lifecycle recovery or financial mutation. Private upload access uses existing authorization. Projections exclude credentials, payment leases, internal lifecycle data, original/recalled message content and arbitrary audit metadata. Recalled messages display a placeholder. Missing related records remain explicit.

Existing dispute-status, resolution and claim-decision endpoints apply mutations. Before confirmation the page fetches fresh case state and balance. Settlement requests include the reviewed allocation amounts, allowing the backend's cents-based validation to reject a concurrent balance change. Earlier payouts remain part of the existing ledger rules. Claim approval records its existing pending-funding state.

## Startup

Restart the original RentHub launcher after updating the code. The API advertises `admin-item-photo-assessment-v3` and `admin-case-workspace-v1`. Launcher checks detect older API/AI contracts. Existing private Gemini settings and model selection are reused.

## Verification

Automated checks used isolated databases, generated pixel fixtures and mocked provider responses. They did not use the shared database as test storage.

| Check | Result |
| --- | --- |
| Full API suite | 839 passed, 3 existing skips |
| Full AI suite | 670 passed, 4 existing dependency warnings |
| Full Flutter suite | 987 passed, 3 skips, 1 existing unrelated gallery semantics failure |
| Flutter analysis | Clean |
| Main/admin web and Android debug builds | Passed |
| Launcher regression suite | Passed |
| Responsive previews | 12 fixture-only renders across 360/390/1024/1440 widths |
| Model and metrics artifact checksums | Unchanged |
| Live provider accuracy and physical-device walkthrough | Pending |

Regressions cover automatic ensure, cached results, repeated opens, uncertain retries, polling after two minutes, dialog return, account changes, per-photo completeness, cross-photo scope, full-screen listing photos, administrator access, read-only projections, recalled content, booking isolation, later pages, claim entry, confirmation, funding status, preserved notes and changed balances.

The existing failing Flutter test is `item_detail_polish_test.dart`, **full photo gallery starts on selected image, swipes, zooms and closes without losing the draft**. It expects the older `Preview Camera, photo 2` semantics label in the listing-detail carousel. This was documented before this update. The new admin gallery has its own passing navigation regression.

An initial full API run stalled after the booking file. The isolated booking file then passed all 56 cases, and a bounded full rerun passed all 839 cases. The initial stall's cause remains unconfirmed.

Private logs are under `.data/testing/admin-workspace-20261117-153018/`. Previews are under `apps/renthub_flutter/.data/admin-workspace-previews/`.

### Remaining walkthrough

1. Restart RentHub, open a physical listing and observe a cached or newly queued assessment without refreshing the page manually.
2. Compare every photo's findings with the actual image and review any across-photo notes. Record observed provider latency, missed details and incorrect statements.
3. Open Listing photos and confirm the full-screen gallery on the presentation device.
4. Open a dispute and its linked claim from their queues. Review evidence, conversation and the inline decision forms before confirming any authorized action.

## Commit message

```text
feat: streamline admin photo assessments and centralize case reviews

- ensure photo checks automatically when listing details open
- reuse cached jobs and keep pending results updating without manual reload
- resume review status after dialogs, galleries and app backgrounding
- validate complete per-photo findings and separate cross-photo observations
- version the Gemini review contract and preserve historical assessments
- remove duplicate photo actions and use the full-screen listing gallery
- add a shared case workspace for disputes and damage-waiver claims
- group case evidence, messages, held funds, decisions and activity
- add projected admin-only case reads and independent paginated histories
- preserve confirmation, allocation validation, funding rules and failed drafts
- update launcher readiness, regression coverage and handoff documentation
```
