# RentHub local launcher reliability

Updated 5 November 2026. This keeps the current local API, AI and Ganache setup,
with the configured MongoDB Atlas and photo storage. No hosting deployment,
database changes, secret changes, model downloads or model deployment were made.

## Recommended use

Run from `apps/renthub_flutter` with Node.js 22+:

```powershell
# Launch Windows with stable services
.\run-renthub.ps1 -Presentation

# Launch/rebuild Android (replace YOUR_DEVICE_ID with adb devices output)
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation

# Use the already installed Android app, with continuous connection monitoring
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation -ServicesOnly

# Temporary service startup/readiness check, then stop services this check started
.\run-renthub.ps1 -Presentation -CheckOnly
```

Use one launcher per presentation setup. For the strongest stability, close the
original development launcher normally before starting presentation mode.
Compatible existing services are reused, never killed or silently reconfigured;
they retain their original reload settings.

`-ServicesOnly` and `-CheckOnly` no longer require Flutter or reject an already
running Windows app. They still require API dependencies and the configured AI
environment/blockchain dependencies unless those services are explicitly skipped.
Node preflight rejects an unreadable version or Node below 22 before Atlas or
service startup, matching the existing storage SDK runtime requirement.

## Reliability changes

| Area | Behaviour |
| --- | --- |
| Presentation mode | Disables API/AI development reload for newly started processes. Normal development defaults remain unchanged. |
| AI startup | Default 180-second deadline, 10-second health requests, progress messages and mandatory current contracts. An existing listener with no ready health response gets time to warm up. |
| API startup | Default 90-second deadline; database readiness and current capabilities remain mandatory. |
| Deadline controls | `-AiStartupTimeoutSeconds 10..600`, `-ApiStartupTimeoutSeconds 10..300`. A final bounded health request/sleep can extend the wall-clock deadline slightly. |
| Failed startup | Exited owned processes fail immediately with an exit code and private log path. Timeouts give targeted guidance; raw log tails are no longer dumped into terminal errors. |
| Atlas | Read-only ping first; CLI/login/access-list work is skipped when the connection already works. CLI calls have 30-second limits and DB probes have 20-second limits. JSON stdout and stderr remain separate. |
| Phone address | Newly launched Android builds use `localhost:3000`; reverse forwarding targets the PC's selected API port. The selected-port mapping is also retained for older custom-port builds. Desktop/browser URLs still use the PC port. |
| Reconnection | Services-only and retained post-debug sessions check the selected device about every five seconds, restore forwarding and distinguish debugging authorization from disconnection. Calls are bounded; no global ADB restart. |
| Service monitoring | Retained sessions check API/database, required AI contracts and configured blockchain approximately every 30 seconds. State changes are reported without automatic restarts or retrying application writes. |
| Blockchain | Requires chain ID 1337. Unavailable custom/remote RPCs produce guidance instead of starting unrelated localhost Ganache. Existing persistent chain data is retained. |
| Windows paths | Direct native tools and Ganache arguments use Windows argument quoting, including spaces, quotes, Unicode and trailing backslashes. No shell interpolation. |
| Flutter directory | Flutter runs inside the app directory even when the launcher is invoked from another folder, then restores the caller's directory. |
| Cleanup | API, AI and blockchain cleanup verify owned PID and original start time. Only that process tree is stopped. Harmless taskkill stderr during exit races is suppressed; genuine cleanup failure still warns. |

Monitoring runs while the launcher owns its service-session loop. While interactive
`flutter run` is active, Flutter owns the terminal; the monitor begins when Android
debugging ends. Use the installed app with `-ServicesOnly` for continuous launcher
monitoring. An already paired/connected wireless ADB device works by selecting its
device ID; the launcher does not perform wireless pairing or reconnect an expired
wireless endpoint automatically.

## Recovery and limits

- Keep the PC awake, connected to the internet, and its launcher terminal open.
  USB debugging must remain connected, or use an already connected wireless ADB
  device. Local services cannot remain available when the PC is off.
- If Android is offline during services-only startup, services stay up while the
  launcher waits. Unlock/authorize or reconnect the same device. A changed wireless
  device ID requires restarting with that ID. A normal Flutter launch fails clearly
  when forwarding is unavailable; use services-only while resolving the connection.
- Atlas CLI account sessions can still expire. The launcher cannot extend them.
  If the DB is reachable, no CLI session is needed. Otherwise follow the classified
  error, including normal `atlas auth login --profile default` when renewal is
  actually required. No permanent credentials or wider network rules are created.
- A service crash is reported, not automatically restarted during bookings or
  payments. Check the log, close the original launcher normally and rerun. Existing
  unowned services must be managed from their original terminal/launcher.
- Readiness does not mean every trained model exists. Missing price-model and
  optional YOLO-World warnings remain visible; the launcher does not download them.
- Atlas synchronizes database records, not independent local blockchain instances
  or Socket.io sessions. Use one active API/blockchain host for a multi-device demo.
- Apps compiled with custom LAN URLs retain those URLs. ADB recovery applies to
  localhost builds; rebuild with this launcher to adopt the stable device port.

Private logs remain in:

- `services/api/.data/logs/launcher-api-error.log` (or `launcher-api-PORT-error.log`).
- `services/ai/.data/logs/launcher-ai-error.log`.
- `blockchain/.data/logs/launcher-ganache-error.log`.

Review logs locally. They can contain private runtime diagnostics; do not commit
them or paste unredacted logs containing credentials or identity information.

## Verification

All three suites passed on Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_launcher_test.ps1 -Integration
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_atlas_access_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_reliability_test.ps1 -Integration
```

Coverage includes current AI/API contracts, port conflicts, environment restoration,
same-PID/different-start-time cleanup guards, disposable Python tree cleanup,
classified private Atlas failures, working-DB CLI bypass, narrow IP access rules,
CLI/ping timeouts, warming/exited services, presentation settings, Android
offline/unauthorized/forward-failure/reconnect states, stable device ports and
monitor retry wiring. Full executable-body tests cover Windows, Android,
check-only and services-only with fake service boundaries and cleanup verification.
Native integration tests use disposable Node processes to verify quoting, stdin,
large simultaneous stdout/stderr, bounded timeout and actual owned-process exit.

Windows process-inspection/termination integration tests needed execution outside
the restricted tool sandbox. They passed there. No live RentHub service startup,
Atlas access-list mutation, booking/payment action or device reconnection was
performed for this verification. Real phone cable removal/reconnection and a full
cold-start presentation remain manual smoke checks. No Dart/API/AI implementation
changed, so application builds and full application suites were not rerun for this
launcher-only task.

## Commit message

```text
fix(launcher): stabilize local startup and Android reconnection

Add presentation mode, bounded readiness and Atlas probes, Node runtime
validation, stable Android API forwarding and retained-session monitoring.
Verify Ganache chain identity, quote Windows arguments safely, and guard
owned blockchain cleanup without exposing private log output.

Cover startup paths, reconnect states, tool timeouts and disposable process
cleanup; document local demo commands and remaining connectivity limits.
```

## Follow-up: false chain-ID failure

The first reliability change introduced a regression: `Get-RentHubBlockchainHealth`
returned the complete JSON-RPC response object, while startup and monitoring
compared its return value with the string `0x539`. A healthy chain was therefore
rejected. The initial tests missed this because their chain-health mock returned
a string instead of exercising the actual RPC adapter.

Fixed the adapter to return only a validated, normalized hexadecimal chain-ID
string. JSON-RPC errors and malformed results remain unavailable; a genuinely
different chain still fails without stopping or replacing the existing process.
Tests now pass real response envelopes through the actual adapter for both new
chain startup and existing-chain reuse, including wrong-chain safety and cleanup.
The new regression failed before the fix and passed after it. Equivalent hex
formatting, malformed responses and error responses are also covered.

Read-only verification against the running local RPC returned `0x539` (1337),
and the corrected launcher helper accepted it. All three standalone launcher
suites passed after the correction. No blockchain restart, reset, transaction,
database write or live full-launcher startup was performed for this follow-up.

## Full-platform regression follow-up — 7 November 2026

The platform test pack exposed multiple executable matches on PATH and
noninteractive native Unicode/timeout edge cases. The launcher now selects the
first executable, uses explicit UTF-8 native JSON I/O and waits briefly for an
owned timed-out root to exit after cleanup. All four launcher suites pass with
their disposable-process/credential-store integration fixtures. No live startup,
Atlas policy or credential change was performed. See
[the full testing result](testing/PLATFORM_TEST_EXECUTION_RESULT.md).

## Interactive keyboard follow-up — 9 November 2026

The reported terminal was showing Flutter's run-key instructions, rather than
services-only monitoring. The launcher now starts Flutter in the same console
using `Start-Process -NoNewWindow`, preserves its working directory/arguments and
waits for its exit code. Flutter stdin, stdout and stderr are not redirected or
routed through the bounded, captured-output helper used for service checks.
The native handle is retained before waiting, so Windows PowerShell can also
report a rapidly exited child correctly. Interrupted cleanup is restricted to
that owned process tree and original start time.

Previously the three background service starts did not explicitly isolate stdin.
They now receive an empty input file (EOF), rather than being able to consume
console keys. The launcher creates one empty temporary file and removes it in
its existing cleanup. Only newly started services get the new input handling;
compatible services already running are neither restarted nor reconfigured.
The original source of the lost key events was not measured inside the old
Flutter process; this change removes the shared-input risk and explicitly hands
the terminal to Flutter.

Use a normal VS Code Terminal or Windows Terminal and wait for **Flutter run key
commands**. In debug mode, **r** reloads, **R** restarts and **q** ends Flutter's
session without Enter. `-Presentation` does not disable these Flutter controls.
Redirected-input hosts receive guidance to use an interactive terminal.
Services-only/post-debug monitoring has no active Flutter key handler. On Android
the backend intentionally remains running after q; use **Ctrl+C** to stop this
launcher's owned services. Reused services remain owned by their original session.

Verification:

- All four launcher suites and the ten platform-pack unit tests passed via
  `scripts/test-renthub.ps1 -Suites pack,launcher -LauncherIntegration`.
- The new disposable console test is included by the reliability integration
  suite. It checks native batch arguments (spaces, quotes, Unicode, empty values,
  URL ampersands and trailing backslashes), exit-code preservation, background
  EOF and continued Node development-watch operation without keyboard input.
- A separate real terminal probe using the production handoff helper reported
  `tty=true` and received **r**, **R**, **q** in order without Enter, then exited
  successfully. This was a disposable Node/batch fixture, not a claim that a real
  phone hot-reload session was exercised.
- Logs: private `.data/testing/20261109-133514-af90e2cb`. Model/metrics inventories
  were unchanged; manual results remain Not run.
- No live launcher restart, phone action, Atlas change, API write or model change
  was performed. Stop the existing launcher normally and relaunch to use the fix;
  the actual Flutter/phone hot reload is the remaining device confirmation.

Commit message: `fix(launcher): preserve Flutter console input and isolate service stdin`.

## Android startup retry follow-up — 9 November 2026

Normal Android startup now waits for up to about **30 seconds** instead of
failing after a single connection/forwarding attempt. It retries roughly every
two seconds after each check, continues immediately on success, and reports the
current problem when it changes or about every five seconds while waiting.

The messages distinguish an absent phone, an offline phone, missing USB-debugging
authorization, a timed-out ADB check, failed/timed-out forwarding, missing ADB,
an invalid selected device ID and an unknown ADB error. Raw tool errors, paths
and arbitrary output are classified privately and are not dumped to the terminal.
Missing ADB and syntactically invalid IDs fail immediately. A valid-looking ID
for an absent phone remains retryable, because the phone may still reconnect;
the guidance also asks the user to check the selected ID.

Each attempt receives the remaining overall time budget; individual native ADB
calls remain capped at five seconds. Native timeout cleanup and a final
fractional-second call can extend wall time slightly, so this is an approximate
30-second connection deadline, not an exact whole-launcher duration. Existing
startup and owned-service cleanup take their own time.

Services-only mode retains its continuous reconnection monitor rather than
stopping after 30 seconds. Its initial check remains bounded and its state-change
messages use the same readable diagnoses. Normal startup failure still cleans up
only processes started by that launcher. Existing services, per-device forwarding,
Flutter console controls and Atlas behavior are preserved. No ADB-server restart,
device reset, wireless pairing, SDK download or application write is performed.

Verification: all four launcher suites plus the ten platform-pack tests passed
with integration fixtures. Added checks cover immediate readiness, delayed phone
appearance, later authorization, forwarding recovery, overall deadline, per-call
budgets, USB/wireless/mDNS/emulator IDs, missing/invalid setup, safe diagnostics,
failed-start cleanup and services-only continuation. The retry deadline is tested
with the same helper's shortened one-second budget; no test sleeps for 30 seconds.
Logs: private `.data/testing/20261109-134858-e0bed5e0`; model/metrics inventories
unchanged. No live launcher or phone connection was restarted to run the tests.

Use the usual launcher command; no new option is required. Restart the existing
launcher normally to load the changed script. Real-device delayed authorization
and reconnection remain a manual walkthrough check.

Commit message: `fix(launcher): retry Android readiness with actionable connection states`.
