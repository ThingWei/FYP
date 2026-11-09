# Notification badges and unpaid-checkout reopening

Updated 9 November 2026 for the live Renter and Owner application.

## Notification bell

- Home, Explore, renter Bookings and Owner Home use the same accessible bell with
  a small red dot when the signed-in account has unread notifications.
- The existing notification API supplies the account-wide unread total. The dot
  does not depend on the inbox page, its category filter, or whether the inbox has
  been opened. No new API endpoint or permission is introduced.
- The count refreshes on workspace loading, authenticated socket connection and
  reconnection, incoming notification events, push events, and app foreground
  return. An already-loaded inbox also refreshes without resetting its filter.
- Reading/removing notifications and marking all read/clearing update the count.
  Failed summary requests retain the previous known count. Logout/account changes
  clear it, and delayed replies cannot apply another account's state.
- The dot means **unread**, not merely that historical notifications exist.

## What the reported Canon booking actually contains

A bounded, read-only check of recent booking/payment summaries found that the
reported Canon test request was `pending`, with `paymentStatus = authorized`.
It had a persisted successful demo authorization approximately 37 seconds after
creation. It did not have an Owner decision timestamp or approved booking status.
No live record, payment, booking or setting was changed by that inspection.

This establishes the saved state, not the user's intent or the origin of the
earlier authorization request. The retained records do not prove which screen
interaction sent that request. Automatically creating a payment merely by
reopening was **not reproduced** in the isolated tests. The earlier occurrence
still needs a fresh-request Android reproduction before its exact cause can be
declared resolved. The existing recorded payment has not been silently reversed.

## Checkout protections and clearer status

- Payment-dialog results are typed choices. Dismissing/cancelling the dialog does
  not select success, and a new attempt has no default successful decision.
- Backgrounding/inactivating the app invalidates a pending payment decision. On
  return, the user must review and make a new explicit selection. A pause or
  account/role change while fetching the latest booking prevents the write.
- Checkout loading is read-only: it retrieves booking/payment history and never
  submits payment or Owner approval. Stale load responses cannot replace a newer
  checkout state, and old success wording is cleared when a new status is loaded.
- Known declines retain friendly retry guidance. Valid, explicitly successful
  payments and recovery of already-durable payment attempts continue to work.
- Extension authorizations are excluded from the initial-checkout payment list;
  they cannot be mistaken for the initial booking's payment.
- The progress rail says **Owner approval**, rather than **Approved** on an
  unreached/current approval step. Paid pending bookings remain **Awaiting Owner
  approval**; unpaid ones retain **Awaiting payment** and no rental-progress rail.
- The server still requires a distinct authorized Owner decision for approval.
  Payment compatibility, the ten-minute unpaid deadline and existing saved
  financial history are preserved. There is no bulk correction or new payment
  provider.

## Verification

- Focused notification/checkout/progress checks: 93 passed before the additional
  inbox-refresh test; that additional test is included in the final full suite.
- Full API suite: **679 passed, 3 existing opt-in skips**, no failures.
- Final full Flutter suite: **656 passed, 3 existing skips**, no failures.
- Final Flutter analysis: **No issues found**.
- Final main web, admin web and Android debug APK builds: **passed**.
- Model/metrics artifact inventories: **unchanged**. No APK was installed and no
  live booking/payment was created by the automated checks.
- Checks cover global totals beyond the current page, filtered inbox refresh,
  read/delete/clear, unavailable summaries, stale/account-changing replies, red
  badges at 360/390 widths with larger text, leave/dismiss/reopen without payment,
  pause/resume decision invalidation, explicit payment afterward, extension
  separation, and unpaid/expired API reads creating no payment or rental.

API results: private `.data/testing/20261109-121459-6dc085e1`. That intermediate
run also built web/admin/Android successfully, but its initial analysis reported
two new lint issues; those were corrected rather than classified as unrelated.
Final Flutter results: `.data/testing/20261109-121734-cef75fb0`.
The isolated runner leaves manual cases Not run and checks model/metrics hashes.
No training, model deployment, source enablement or production dependency change.

## Android handoff

1. Rebuild/relaunch with the usual Android launcher so the installed app includes
   these changes. Producing an APK does not install it or exercise the phone UI.
2. Check the dot with an unread notification, then mark all read and check it
   disappears. Repeat after app resume and a role change.
3. Use a fresh unpaid booking. Leave checkout without choosing **Pay demo**, close
   and reopen the app, and check that **Awaiting payment** and the same deadline
   remain (or **Expired** after ten minutes). If reusing the same item/dates,
   cancel the existing eligible request through the normal UI first.
4. On a separate request, explicitly pay and verify it says **Awaiting Owner
   approval**, not approved. Confirm the Owner must separately approve it.

If the unintended payment recurs, retain its booking reference and event time for
private diagnosis. Do not reset money/status fields or overwrite prior results
to conceal the reproduction. Real Android behavior remains a manual check.

## Commit message

```text
fix: add unread notification badges and harden checkout restoration

- use account-wide unread totals across renter and Owner notification bells
- refresh counts on reconnect, push, foreground return and inbox actions
- preserve inbox filters and reject stale account responses
- require explicit typed payment decisions and invalidate paused decisions
- guard checkout loads and exclude extension payment attempts
- clarify Owner approval progress without claiming pending requests are approved
- test unpaid reopening, expiry, badges and payment recovery
- document observed Canon state and the remaining device reproduction
```
