# Checkout rewards and live-screen cleanup

Updated 14 November 2026.

## Delivered

| Area | Current behaviour |
|---|---|
| Item payment section | Shows the included security-deposit amount when one applies. Services do not show an item deposit. |
| Checkout | Offers available loyalty rewards, removal of a selected reward, and access to points/redemption. Saved server charges show the discount before payment. |
| Rental details | Appointments appear above the condition evidence. Separate compact **Handover** and **Return** cards show the right party's saved photos, condition and short notes. Dates and full notes remain under Details. |
| Evidence galleries | Photos use a 160-pixel preview with enlargement. Multiple photos retain carousel controls; a single photo has no redundant navigation row. |
| Progress | Removed the duplicate Return record expansion. Receipt acknowledgement, disputes, returns and completion rules are unchanged. |
| Discovery filters | Category chips determine items/services; removed the duplicate Listing type selector and long location helper paragraphs. Pin validation and short approximate-area labelling remain. |
| Home | No Choose/Change area or GPS panel in the sections. Choosing a pin through Filters adds **Near You** between Recommended For You and the general trends/highlights section. |
| Saved locations | Confirmed listing locations and renter-entered booking destinations are remembered privately, deduplicated and bounded to ten recent locations. They can be reused for delivery, completed as saved addresses, or removed. |
| Phone | Remains an optional private contact field. The profile no longer prompts everyone to add one. No public sharing or SMS feature was added. |
| Owner reviews | Smaller author/listing/text rows with five stars; long reviews remain accessible through View all reviews. |
| Listing form | Short upload requirements and private-registration label. Removed the unfinished-draft paragraph and product-source success descriptions, retaining product/package selections and validation. |
| Admin | Record dialogs are constrained to 720 pixels and 78% viewport height on larger screens; shared action dialogs default to a 560-pixel maximum. Narrow record dialogs remain full-screen for usability. |
| Platform Settings | Shows Support and customer messages, and Points and referral rewards. Saving support settings sends only the supported fields; hidden fee, identity, maintenance and taxonomy values are not reset. |

## Using rewards

1. Open Profile → Rewards and redeem points for an available configured reward, or use an existing referral reward.
2. Open an unpaid checkout and choose the reward under **Loyalty reward**.
3. Review the reduced total. Choose **No reward** to remove it before payment.
4. Continue the existing payment and Owner-approval flow.

The selected funding policy is **RentHub covers the discount; Owner earnings stay unchanged**. Rewards apply to rental/service charges only, up to that charge, and never reduce the deposit, delivery or waiver amount. One reward is allowed per booking. It is reserved during checkout and used when capture succeeds. Closing, cancelling or expiring an uncaptured request makes its reservation reusable on a subsequent reward check. Redemption into a reward code still spends the configured points under the existing rules; it is not a direct points toggle at checkout.

The existing payment integration is simulated. A separate `reward_credit` transaction explicitly records the platform contribution; it is not represented as money collected from the renter. Settlement still funds the original Owner charge. Rewards cannot be withdrawn as cash. A full customer refund returns unused platform contribution to RentHub separately, without paying it to the renter or changing prior Owner payouts. Applying a reward does not approve a booking, capture a payment, extend its deadline or create rental history.

Server controls include account/booking ownership, active renter status, paused rewards, original checkout expiry, payment leases, atomic cross-booking reward reservation, server-valued amounts, and capture/contribution idempotency. Interrupted bookkeeping recovers from durable capture and contribution records. The client reads saved charges after uncertain outcomes rather than automatically repeating a write.

### Interfaces

- `GET /api/v1/rewards/checkout/:bookingId` — eligible owned rewards.
- `PUT /api/v1/rewards/checkout/:bookingId` with `rewardId` — select one or use an empty string to remove it.
- Optional pricing metadata: `rewardDiscount`, `rewardId`, `rewardCode`.
- Optional `separateNearby=true` on the existing recommendation feed: keeps recommendations location-aware, makes trends general, and adds a separately computed nearby section. Existing clients without this option keep their existing behaviour. Section retry accepts `nearby`.
- `DELETE /api/v1/users/me/recent-locations/:id` — remove only the signed-in account's remembered location.

Nearby results use eligible approximate public points and the existing availability rules, with no additional AI inference or exact-distance disclosure. The Home feed remains one request; sections retain their own success/failure state and stale-response guards. Existing base recommendation weights are unchanged.

Remembered locations come only from explicit valid selections on successful saves. There is no background GPS, automatic reverse geocoding or guessed postcode/house number. Another participant's private pickup location is not copied into a renter's address book. Missing address parts remain empty until the user completes them. Saved-address identifiers and booking snapshots remain intact. Public profiles and feeds do not receive recent locations.

## Live inventory: exact status

One additional **regular marketplace** listing was submitted under the requested verified Owner account:

- **JBL Go 4 Portable Bluetooth Speaker** — RM10/day, RM30 deposit, pickup at the most recent confirmed listing pin, four reviewed catalogue photographs.
- Status: **pending review**, not publicly active.
- Condition: the Owner-requested Good default. Age is unknown and omitted.
- Product-photo source: [JBL Online Store MY](https://jblonlinestore.com.my/products/jbl-go-4-ultra-portable-bluetooth-speaker), credited in the description. These are catalogue images, not handover/return condition evidence or independent ownership evidence.
- Price is an Owner-entered, unverified asking price. It is not labelled independently validated and does not become clean AI training evidence automatically.
- All four new public upload URLs returned HTTP 200 with bytes matching the prepared source files.

The original **50 entries are still preparation**, not 50 published records. Their original Wikimedia bulk-photo collection remains incomplete. An additional private review contains **99 duration-specific source offers covering 32 named products**: 15 Cars, 15 Motorcycles and 2 Smartphones. Duration bands are retained rather than counted as separate physical items. This review does not supply new iPhone or independently sourced speaker rental prices.

Vehicle publication still requires the Owner's private registration evidence and normal review. Service listings await the actual services offered and starting rates requested from the user. No qualifications, vehicle documents, completed rentals, reviews, payment history or independent pricing observations were generated. The older listings and booking history were not deleted, archived or relabelled.

Private preparation/results are under `services/api/.data/evidence/regular-owner-batch-2026-11-14/`, including the updated INVENTORY-REVIEW, additional-source review, photo sources and speaker submission receipt. No credentials or exact pickup addresses are included here.

### Approval boundary

Automatic approval review rejected an initial direct-publication command because it would have used a synthetic administrator actor to force a live listing active. That step was removed. The executed safer command uploaded the photos and used normal Owner creation/submission only; it stopped at pending review. **A real administrator must review and approve the speaker in Admin → Listings.** No administrator decision or audit approval was invented.

## Verification

- Final Flutter tests: **853 passed, 3 skipped**.
- Final API tests: **774 passed, 3 skipped**, in isolated temporary databases.
- Flutter analysis: clean.
- Main web, administrator web and Android debug builds: passed.
- Private readable-font previews: 360/390/1024/1440 pixels at 1.4x text for rewards and compact evidence cards; inspected mobile and desktop output.
- Existing GPS denial, permanent denial, disabled GPS, timeout and late-reading coverage remains in the map-picker suite. Obsolete Home GPS-control tests now assert no unsolicited Home positioning and exercise filter-selected areas.
- Regression coverage includes cross-account reward/location access, duplicate/concurrent reward use, expiry/leases, unchanged deposits and Owner charges, full refund contribution reversal, interrupted bookkeeping, recent-location deduplication/privacy, source-text removal, section ordering, stale account/area responses and retained form values.
- Real Android walkthroughs and cross-laptop operation were not performed during this task. The screenshot condition photos were illustrative UI fixtures; no return/handover record was created with them.
- Deployed model artifacts are unchanged. No retraining, new production dependency or database migration was performed.

Final private logs: `.data/testing/20261114-202550-d4c2e08f/` and `.data/testing/20261114-125824-4975df16/final-rewards-nearby-complete-api.log`. Preview output is under `apps/renthub_flutter/.data/compact-trust-previews/`.

Restart the API and reopen/rebuild the app to use the coordinated checkout/feed changes. Refresh the Owner list and Admin pending listings to see the new speaker submission.

## Commit message

```text
feat: add checkout rewards and simplify live rental screens

- apply single-use, platform-funded rewards to unpaid bookings
- preserve Owner earnings and deposits with separate reward contribution records
- guard reward reservations, payment leases, recovery and cash-refund limits
- separate nearby Home results from general trends while retaining location-aware ranking
- remember confirmed private locations without changing saved-address IDs or snapshots
- compact handover and return evidence, move appointments first and remove duplicate history
- simplify discovery, listing copy, Owner reviews and admin dialogs/settings
- add reward, privacy, concurrency, recovery and responsive UI regressions
- document actual inventory submission status and remaining publication requirements
```
