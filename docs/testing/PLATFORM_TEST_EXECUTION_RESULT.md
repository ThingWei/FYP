# Full-platform test pack and regression execution

Executed **7 November 2026**, Malaysia time. This records the implemented test pack,
automated results, corrected regressions and work still needing human/device evidence.

## Delivered

- [Full priority-ordered plan](RENTHUB_FULL_PLATFORM_TEST_PLAN.md): **82 flow groups,
  584 separately recorded variants**, all ten modules, all 22 physical subcategories,
  peripherals and separate service flows.
- [Operating instructions](README.md): dedicated accounts/fixtures, safe test setup,
  exact commands, result/evidence requirements and final acceptance criteria.
- A versioned case catalogue, renderer, consistency checker and **10 test-pack tests**.
- New private, non-overwriting manual execution sheets and JSON registers with
  IDs, actors, preconditions, steps, expected/actual results, build/date/platform,
  status, evidence and defect fields. New entries start **Not run**.
- A single PowerShell regression entry point that isolates child settings, runs
  selected suites/builds, retains failures/logs and verifies deployed artifact hashes.

Priority breakdown:

| Priority | Flow groups | Independent variants |
| --- | ---: | ---: |
| P0 | 26 | 161 |
| P1 | 46 | 300 |
| P2 | 10 | 123 |

The 66 recognition-evaluation batches reference the existing private 198-slot
collection kit; they are not new photos, fabricated annotations or an accuracy result.
Automated regression references are a coverage map, not proof that each manual
variant has been executed.

## Final consolidated automated run

Command from the project root:

```powershell
.\scripts\test-renthub.ps1 -Builds -LauncherIntegration
```

Final private run: `.data/testing/20261107-232355-a16a0302/`.
It completed successfully; `automated-results.json`, individual logs and
`summary.md` retain actual command exit codes, durations and available test counts.
The working tree includes existing uncommitted work; these are working-tree
results, not a claim that a clean tagged release has been tested.

| Check | Final observed result |
| --- | --- |
| Test-pack schema/coverage/safety tests | **10 passed** |
| Full Express API suite, no test-name exclusions | **677 passed, 3 existing opt-in skips**; 680 total |
| Full AI Python suite | **639 passed**, 4 existing warnings |
| Full Flutter suite | **644 passed, 3 existing opt-in skips** |
| Flutter analysis | **No issues** |
| Main web build | **Passed** |
| Administrator web build | **Passed** |
| Android debug APK | **Passed**; not installed or operated on a phone |
| Hardhat contract tests | **4 passed** on the isolated test network |
| General launcher suite with integration fixtures | **Passed** |
| Launcher reliability with integration fixtures | **Passed** |
| Atlas access fixture suite | **Passed** |
| Atlas automation/credential-store fixture suite | **Passed** |
| Deployed AI model/metrics SHA-256 inventories | **Unchanged**, before/after inventories retained privately |
| Case catalogue/rendered-document consistency | **Passed** |
| Whitespace check | **Passed** |

Express tests use temporary databases, mock authentication and local test storage.
Live provider opt-ins, external delivery, live blockchain and unattended source/
lifecycle jobs are disabled in the test child environment. Test-specific controlled
jobs and clocks remain exercised normally. No live database, cloud source setting,
approved identity, genuine transaction or model artifact was rewritten.

The 3 API skips are the existing live catalogue/pricing E2E opt-ins. The 3 Flutter
skips are the existing live MongoDB write/read phases and opt-in UI capture.
They are not counted as device/provider passes. There is no longer a special
name-pattern exclusion for the paid-pending booking test.

## Failures found and corrected

Intermediate failed logs remain in the private test runs. They were not deleted
or edited into passes. The final run above reran all suites/builds.

| Reference | Finding | Correction and retest |
| --- | --- | --- |
| TP-001 | Legacy duplicate fixture set the Owner deadline into the past but expected the paid request to remain pending. | Separate payment-window and Owner-decision assertions. A paid legacy request blocks duplicates after payment time while its Owner deadline is current; after Owner expiry is processed it expires/releases the hold and permits a new request. Production expiry policy unchanged. |
| TP-002 | Messaging test assumed its message was the only unread notice, ignoring the new checkout-payment notice. | Capture the initial unread count and identify the message-category notification explicitly; retain read/delete/clear assertions. |
| TP-003 | Old financial test attempted to open a dispute after final settlement. | Assert the new completion rejection and unchanged payments/state/notifications. Preserve zero-held-balance coverage using a genuinely unfinished, fully refunded test rental and its permitted case. |
| TP-004 | Multiple Node installations on PATH produced an array of executable paths, causing native startup failure. | Select the first matching executable for Node, ADB and Atlas resolution, including one-time setup. Startup fixtures now supply multiple Node matches and assert one selected path. |
| TP-005 | Native Unicode JSON output depended on the noninteractive Windows code page; timeout cleanup could return before root exit was observed. | Explicit UTF-8 output/error decoding and Framework-compatible UTF-8 stdin bytes; bounded owned-root exit wait after cleanup. Actual disposable-process tests cover Unicode, spaces/quotes, pipe pressure, timeout and exited-process behavior. |

Launcher fixes preserve process-ownership safeguards, current profile precedence,
startup commands, narrow Atlas access and private configuration. No service
account was created, credential rotated or Atlas policy changed in this task.

No runtime payment, dispute or authentication rule was changed to make the
outdated tests pass. The existing full-platform behavior remains authoritative.

## Manual and evidence status

The user chose **“Leave device checks for my walkthrough.”** A read-only ADB
inventory found no attached Android device. No new phone walkthrough, manual
account login, booking/payment, moderation, KYC approval or notification delivery
was performed as part of this execution.

**All 584 manual variants in this run remain Not run.** There are separate
`P0-results.md`, `P1-results.md`, `P2-results.md` and `manual-results.json` files
inside the final private run. The automated counts above must not be copied into
those manual rows as Pass.

Still required for full-platform acceptance:

1. Run P0 on the current app with the dedicated accounts, including real
   ten-minute expiry/reminder delivery, competing requests, future scheduling,
   handover/return evidence, service lifecycle, extensions and completed-dispute
   cutoff. Use separate staged records for branches.
2. Complete P1 across the module pages, especially current admin record/details,
   messaging actions, reward/referral progression and source/CSV controls in staging.
3. Run the Android permission/reconnection cases, second-laptop/school-network
   startup and separate backup/restore rehearsal before the presentation.
4. Supply reviewed independent item-photo/risk ground truth, rental observations
   and consented relevance feedback where evaluating AI quality. Unit tests and
   demo records do not establish real-world recognition, authenticity, pricing or
   recommendation accuracy. Missing cohorts remain Not evaluated/Blocked.
5. Rehearse the exact presentation build and record safe screenshots/results.

Previous staged lifecycle, GPS and push observations retain their historical
build/date. They are not automatically rerun or reclassified here. Source permission
and catalogue/price-data gaps remain separate from the passing regression suites.

## Existing nonblocking warnings

- AI: existing Starlette/AnyIO and spaCy/Click deprecations, plus sparse pricing
  imputation warnings in controlled fixtures; 4 warnings total.
- Web: existing Socket.IO WebAssembly dry-run and missing optional Cupertino font
  warnings; normal JavaScript builds succeed.
- Android: existing future Kotlin Gradle Plugin migration warnings for Firebase
  and preferences plugins. No new unrelated analyzer error was observed.

No new production dependency, hosting change, dataset, automatic retraining or
model deployment was introduced. Existing uncommitted work was preserved; nothing
was staged or committed.

## Commit message

```text
test(platform): add prioritized full-flow verification pack

- document 82 flow groups and 584 independent variants across all ten modules
- prepare private non-overwriting manual sheets, evidence fields and defect records
- add an isolated API/AI/Flutter/contract/launcher regression and build runner
- validate case coverage, result requirements, safe settings and artifact preservation
- reconcile payment-deadline, notification and completed-dispute regression fixtures
- select one native executable and preserve UTF-8 CLI data and bounded cleanup
- record unfiltered suite/build results separately from deferred device validation
```
