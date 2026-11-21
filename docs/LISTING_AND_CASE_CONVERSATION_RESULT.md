# Listing readability, case conversations and delivery advice

Implemented on 20 November 2026.

## What changed

### Listings

- Long descriptions initially show four lines with **See more** and **See less**. Short descriptions have no extra button. Renter details and Owner previews use the same component.
- The expanded product-comparison section now leaves space above populated Version/capacity and ISBN fields so their floating labels do not collide with the heading.
- **Manage listing** replaces the Owner detail page's Edit action. It groups Edit and Delete, retains disabled-state reasons and deletion confirmation, and links to bookings/rentals when deletion is blocked.
- The listing status badge fits its text.

### Dispute conversations

Open an existing case to discuss it with the other participant and the admin team. Each message shows its author, role, time and attachments. Any authorized administrator can reply; staff messages identify the individual administrator.

The progress flow is **Opened → Discussion → Admin review → Closed**. Narrow layouts use **Chat** and **Review** to keep labels readable; accessibility labels retain the full stage names.

The admin Conversation tab includes **Review & resolve**, leading to the existing decision controls in the same workspace. Earlier booking messages remain available in a collapsed section. They are separate from the new case conversation.

When a case closes, the participant view also refreshes its linked booking and rental. Resolved cases cannot retain a stale Submit return action.

Opening a case, requesting evidence, starting review, escalating and closing produce readable timeline updates from saved case/audit records. Earlier participant responses appear without copying or rewriting them. Closed cases retain history and have no message composer.

Only the actual case participants and active, authorized admins can access the conversation. Evidence remains protected and cannot be deleted once attached. Message editing/recall is deliberately unavailable for case evidence. Ordinary messaging retains its current behavior.

### Delivery guidance

- The booking screen reuses the renter's selected discovery area. The renter can change it or explicitly choose a saved place. An unrelated saved address is never selected automatically.
- The same state and no more than 25 km straight-line distance count as nearby. For a different state or a longer trip, **Delivery recommended** appears when the Owner offers delivery.
- An initial recommendation may select delivery before the renter makes a choice. Once the renter explicitly chooses a fulfilment method, changing the area does not replace that choice.
- Pickup remains available for renters willing to travel. The recommendation cannot enable delivery on a pickup-only listing.
- Missing/unknown state or coordinates produces no recommendation. Recognized state aliases include Penang/Pulau Pinang and federal-territory names.
- Guidance uses the public approximate listing point, not its private pickup address. The selected departure area stays local to this booking screen. It is not submitted as a new private booking field.
- Delivery fees and the confirmed delivery-address requirement continue through the existing booking/payment flow. No central meetup-location workflow was added.

## API and compatibility

| Interface | Behavior |
| --- | --- |
| `GET /api/v1/disputes/:id/messages?limit=20&before=...` | Latest messages and system updates, newest first. `meta.nextCursor` loads earlier history; `meta.status` supplies the fresh case state. Maximum limit: 50. |
| `POST /api/v1/disputes/:id/messages` | Accepts `idempotencyKey`, optional `text` up to 2,000 characters and up to ten owned `dispute_evidence` references. Requires text or evidence. |
| `case:join` / `case:leave` | Existing authenticated socket connection subscribes to an authorized case. |
| `case:update` | Sends only a case identifier; clients retrieve the authorized projection through HTTP. |

New messages use a separate indexed collection. The server derives names/roles from authenticated records, not client-supplied role labels. Request keys are unique per sender and case; retrying the same payload returns the original message, while changed content with the same key is rejected.

Sending checks fresh membership and case status inside the existing lifecycle lock. A closed case rejects new sends with `DISPUTE_CLOSED`; a previously saved send can still be recovered with its original key. Notification delivery failures do not undo a saved message.

The client merges live updates without duplicates, retrieves earlier pages, refreshes after reconnection, pauses while backgrounded and has a 30-second read-only fallback refresh. It retains text, attachments and the original send key on failure. Account changes invalidate pending results. Missing historical timestamps remain unavailable rather than receiving invented dates.

The existing participant response endpoint and all review/resolution/claim endpoints remain supported. Chat messages do not change case status or move money. Admin resolution continues to use the existing remaining-held-funds checks and confirmation workflow. No historical migration, source enablement, pricing-model change or new production dependency was introduced.

## Verification

All automated database tests used temporary isolated databases, disabled external integrations and fixture accounts. No shared marketplace records were created or changed.

| Check | Result |
| --- | --- |
| Focused Flutter interaction checks | 79 passed; the additional legacy saved-place case also passes in the full suite |
| Final dedicated case-chat API checks | 12 passed |
| Full API suite | 851 passed, 3 skipped |
| Full Flutter suite | 1,006 passed, 3 skipped, 1 known existing failure |
| Flutter analysis | Passed |
| Main web build | Passed |
| Admin web build | Passed |
| Android debug build | Passed |
| Fixture layout renders | 12 passed at 360/390/1024/1440 pixels with increased text size |
| Deployed AI model/report checksums | Unchanged |

Coverage includes foreign access and forged admin roles; multiple admins; duplicate/concurrent sends; changed-key payloads; immutable attachments; missing timestamps; cursor pagination; closure races; socket subscription permissions; closed history; stale account responses; retained drafts; description expansion; compact status; guarded listing management; and delivery/no-location/type boundaries.

The existing failing Flutter test is `item_detail_polish_test.dart`: **full photo gallery starts on selected image, swipes, zooms and closes without losing the draft**. It expects the old `Preview Camera, photo 2` semantics selector. This failure was already recorded in [the previous admin handoff](ADMIN_PHOTO_REVIEW_AND_CASE_WORKSPACE_RESULT.md); the gallery implementation and that test were not changed here. The full Flutter suite must not be described as entirely passing.

Web builds retain existing WebAssembly dry-run/Cupertino-font warnings. Android retains existing plugin/Kotlin migration warnings. All three builds produced their requested artifacts.

Private logs are under `.data/testing/listing-case-20261120-201100/`. Fixture renders are under `apps/renthub_flutter/.data/listing-case-previews/`; they contain no real case information. Physical-device interaction, live push delivery and actual Wi-Fi reconnection still require a walkthrough.

## Quick walkthrough

1. Restart the API and reopen/rebuild the app so both sides support case messages.
2. Open a long listing description; expand/collapse it. Open an Owner listing and check Manage listing, compact status and blocked-deletion guidance.
3. Enter Version/capacity in the expanded comparison section; check that the label remains clear.
4. Select a distant area on a delivery-enabled listing. Confirm the delivery suggestion, then choose pickup and change area; the explicit choice should remain.
5. Use an unfinished rental to open a case. Send a message as the renter, Owner and admin. Check author labels, attachments and earlier messages.
6. As admin, request evidence and resolve through Review & resolve. Both participants should see updates and the final decision; closed history should have no composer.

## Commit message

```text
feat: improve listing readability and add shared dispute conversations

- collapse long descriptions and separate comparison field labels
- group Owner edit/delete actions under Manage listing with compact status badges
- add paginated renter/Owner/admin case chat with protected immutable evidence
- guard case sends with fresh authorization, lifecycle locks and idempotent retries
- synchronize case messages and decisions through authorized socket updates
- preserve legacy responses and provide a clear review-to-resolution flow
- recommend delivery using the renter's chosen area and a 25 km nearby threshold
- retain explicit pickup choices, existing charges and private pickup locations
- add regression coverage, responsive previews and implementation handoff
```
