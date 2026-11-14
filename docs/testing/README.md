# RentHub testing: start here

This pack covers the current live Renter/Owner app and separate admin portal:
**82 flow groups and 584 separately recorded variants across all ten modules**.
It includes all 22 physical subcategories, peripherals and the separate service
lifecycle. It does not add another business module or introduce Toys & Entertainment.

- [Full priority-ordered cases and expected results](RENTHUB_FULL_PLATFORM_TEST_PLAN.md)
- [Latest execution and remaining manual work](PLATFORM_TEST_EXECUTION_RESULT.md)
- [Normal startup and supervisor operating guide](../../README.md)
- [Overdue reminder and Owner-protection walkthrough](../OVERDUE_REMINDERS_AND_OWNER_PROTECTION_RESULT.md#verification-and-demonstration)
- [Current trust, comparison, appointment and private-document walkthrough](../TRUST_COMPARISON_AND_REVIEW_EVIDENCE_RESULT.md#short-walkthrough)

For new executions after 14 November 2026, include both physical appointment times in P0-09/P0-11/P0-16/P0-17, a private registration photo for Cars/Motorcycles in P0-08, and the separate MyKad holder photo/manual review in P0-05/P0-06. Check extension reserved-range blocking in P0-20 and collapsed saved proof in P0-26. Existing completed result sheets remain unchanged; these additions do not pass their earlier variants automatically.

## What to do first

1. Prepare a dedicated test environment/accounts and the fixtures below.
2. Prepare a fresh execution pack. Follow P0 before P1, then P2.
3. Run the automated regression command separately.
4. Perform the hands-on cases and record actual results. A suite pass does not
   prove a device, identity review, notification delivery or AI accuracy case passed.
5. Fix/retest failures, then rehearse the exact presentation equipment/network.

All commands below run from the project root. Nothing here starts the live app,
seeds accounts, approves identities or changes shared marketplace records.

## Prepare your blank walkthrough sheets

```powershell
.\scripts\test-renthub.ps1 -PrepareOnly
```

The output names a new private `.data/testing/<run>/` directory. It contains:

- `P0-results.md`, `P1-results.md`, `P2-results.md`: readable execution tables.
- `manual-results.json`: the same cases with preconditions, ordered steps,
  expected result and per-case build/date/account/evidence/defect fields.
- `defects.md`: a place for reproducible defects and retest notes.
- `summary.md` and `automated-results.json`: the selected automation run, if any.
- Artifact checksum inventories for checking that test execution did not replace
  deployed models/metrics.

Every variant starts **Not run**. Existing execution packs are never overwritten.
Keep one record format authoritative for a session: either the Markdown sheets or
the JSON register. The runner does not import/synchronize handwritten sheet edits.
If using JSON, validate it with:

```powershell
.\services\ai\.venv\Scripts\python.exe scripts/platform_test_pack.py --results .data/testing/YOUR_RUN/manual-results.json
```

Pass/Fail entries require an observed actual result, build, date/time, device,
account alias and safe evidence. Fail also needs a defect reference. Blocked needs
a reason. Do not enter a real email, password, IC number or exact private address.

## Automated checks

```powershell
# All isolated suites, source analysis, both web entry points and Android build:
.\scripts\test-renthub.ps1 -Builds -LauncherIntegration

# A smaller rerun when investigating one area:
.\scripts\test-renthub.ps1 -Suites pack,api
```

The runner uses the existing AI Python environment and installed Node, Flutter,
Java/Android and PowerShell toolchains. It does not install dependencies or download
training weights. A missing tool is recorded as Blocked, not Pass. Build tooling
may use its normal compiler/package caches; arrange dependencies before a demo.

Each command has a 30-minute timeout. Logs/results remain private. Failed commands
do not hide later check results. A timeout/interruption stops only the process tree
created for that check. No existing RentHub service, global ADB server or unrelated
process is stopped. Nonzero exit status means at least one automated check failed,
was blocked/interrupted, or deployed artifacts changed. Selected suites only are
reported: this is not a whole-platform acceptance verdict.

The child environment excludes inherited service credentials, personal Atlas
profiles, Node preload options and opt-in live test flags. Express uses an empty
test dotenv file, mock authentication, local test storage, temporary databases,
disabled external email/FCM/blockchain and disabled schedulers. API live-provider
tests and Flutter live MongoDB phases stay opt-in and are **not** invoked here.
The normal API suite controls its own fixture clocks/jobs explicitly.

Hardhat runs its isolated test network, not the active Ganache chain. Launcher
integration checks use disposable owned processes and a disposable nonsecret
Windows credential-store probe; they do not log into Atlas or grant live access.
Normal application `.env` files and authentication behavior are unchanged.

## Dedicated fixtures

Use aliases in the report, not real account identifiers:

| Alias | Required state |
| --- | --- |
| Owner A | Existing verified marketplace account with its own physical and service listings |
| Renter B | Different verified marketplace account |
| Renter C | Third verified account for competing requests |
| User D | Unverified account for restricted actions and fresh registration/reset tests |
| Admin M | Separate administrator account |
| Restricted user | Dedicated expendable account for suspension/deactivation/reactivation |

Choose existing permissioned accounts or prepare them through normal workflows.
Do not fabricate identities or use an actual customer's account for moderation.
Identity binding/concurrent approval bypass tests belong in isolated fixtures;
ordinary approval must never be bypassed to make a walkthrough convenient.

Prepare separate labelled-demo listings/bookings for:

- Available today, future date, delivery fee, vehicle/licence requirements and
  each supported service venue mode.
- Payment success/decline/cancel/expiry, Owner rejection, cancellation/refund,
  extension approval/rejection and dispute resolution.
- At least three compatible comparison listings plus incompatible/service examples.
- Draft, pending-review, active/inactive listings and known unavailable dates.
- More than 50 fixture rows where paging/filtering totals are tested; do not
  create these as fake genuine marketplace evidence.

Use dates relative to the actual **Malaysia test day**, not dates copied from an
old screenshot. A same-day physical rental counts as one inclusive day. Prepare
known confirmed/manual blocks to test start/end range crossing. Future handover
boundaries use controlled automated clocks; never change a device clock or rewrite
live dates. The initial unpaid checkout window is ten minutes; the separate Owner
response deadline remains configured independently. Extension checkout retains its
own existing quote-expiry policy.

Use owned permissioned item photos for handover/return. Keep malformed/large file
fixtures and deliberately unreadable documents private. Do not put unmasked ICs
into reports, committed fixtures or training data. Provider errors, stale states,
races and crash points are simulated in tests, not by damaging a live database.

## Actual walkthrough order

1. **P0 startup/access:** startup, login, role/privacy and verification restrictions.
2. **Physical baseline:** dates → unpaid checkout → payment → actual Owner
   approval → scheduled → Owner handover/photos → renter confirms receipt → active rental → return/photos → inspection → settlement
   → agreement/history and review.
3. **Service baseline:** required venue → checkout → approval → start → delivery
   → renter completion; verify physical-only controls are absent.
4. **Branch tests:** expiry, duplicates/soft holds, cancellations/refunds and paid
   extensions on separate records.
5. **Disputes/claims:** raise before completion, exchange evidence, admin outcome,
   pending-funded claim and final-completion cutoff. Preserve existing case history.
6. **P1 all modules:** remaining profile, discovery, AI assistance, messages,
   reviews, rewards and every admin detail/pagination/action type.
7. **P2 readiness:** device permissions/reconnection, responsive layouts, failures,
   independent AI evidence, restore rehearsal and five-minute presentation.

One ordinary physical lifecycle, basic GPS and push checks were observed in earlier
handoffs. Those do not automatically pass the latest build's timer/dispute cases.
Keep historical evidence with its original build/date, separate from this run.

## Evidence and defect rules

- Record UI status, persisted result and relevant count/balance/authorization for
  P0 writes. Never decide success from a snackbar alone.
- A successful FCM send is not proof the Android device displayed/opened it.
- Local EVM receipts/state prove only the recorded demonstration operation; they
  do not move real MYR, certify identity or protect the entire agreement text.
- A functional pricing/recommendation response is not an accuracy study.
- The 66 recognition batches refer to the existing private 198-slot collection
  kit. Missing photos/reviewed boxes remain incomplete; no new dataset is seeded.
- A symptom on a stale build must be reproduced on the intended current build
  before closing it. Preserve failures and retest records rather than editing them
  into passes.
- Mark severity Critical for unauthorized private access, financial duplication or
  unrecoverable lifecycle corruption; High for a blocked core flow; Medium/Low for
  contained secondary/usability issues. Record owner, fix and retest evidence.

## Acceptance

All applicable P0 variants pass; all ten modules have end-to-end evidence; no
Critical/High issue remains; P1/P2 gaps and skips are explicit. Phone/admin manual
results, automated checks and AI accuracy are separate. No demo activity is
relabeled genuine. The exact presentation laptop/phone/network gets a final smoke
test, with a tested fallback and private backup. Restore only to a separately
approved test target, never over the shared demonstration database.

## Maintaining the pack

`tests/platform/case_catalogue.py` is the reviewed source. Check consistency:

```powershell
.\services\ai\.venv\Scripts\python.exe scripts/platform_test_pack.py
```

After an intentional catalogue change, regenerate the plan with `--render`. Keep
existing case IDs/order stable and use a new execution pack. Do not regenerate or
overwrite a filled result register to conceal removed or failed cases.
