# Atlas automation for both laptops

Implemented and checked on the original Windows laptop on 6 November 2026.

Normal RentHub startup can now use a per-laptop automation account instead of a
short-lived personal Atlas CLI browser session. The second laptop needs its own
one-time setup after receiving these scripts; it has not been directly tested.

## Everyday use

From `apps/renthub_flutter`, use your usual command:

```powershell
.\run-renthub.ps1 -Presentation
# Or the connected phone:
.\run-renthub.ps1 -Device YOUR_DEVICE_ID -Presentation
```

No daily `atlas auth login` is needed after successful automation setup. Internet,
valid database credentials, a working Windows credential store and a valid,
unrevoked automation credential are still required. This does not host services
or keep a sleeping laptop online.

The launcher first tries a read-only database connection/ping. If it works, it
skips Atlas CLI entirely. Otherwise it verifies that the configured cluster
belongs to the configured project, finds the current public IPv4, reuses a
current matching individual-IP entry or creates one expiring in 24 hours, and
waits for the database connection. Existing entries are preserved. No database
`0.0.0.0/0` entry is created. Expired matching entries cannot count as successful
registration, including after a concurrent-create failure.

**The message saying access expires in 24 hours remains correct.** It describes
the network entry, not the service-account credential. When needed on a later
day, the credential registers the network again without a personal browser login.
After changing Wi-Fi during an active session, rerun the launcher. Existing
connections are not an uninterrupted network-handover guarantee.

## One-time setup on the other laptop

1. Copy/pull `run-renthub.ps1`, `setup-renthub-atlas.ps1` and
   `scripts/atlas-automation.ps1`. Keep that laptop's working private API `.env`
   and the same shared Atlas database URI. Do not replace `.env` with a template.
2. Install a current MongoDB Atlas CLI. This implementation was verified with
   CLI 1.59.4 and Windows PowerShell 5.1.
3. Open PowerShell as your normal Windows user, from `apps/renthub_flutter`.
4. Sign into the administrator profile once, preview, then apply:

```powershell
atlas auth login --profile default
.\setup-renthub-atlas.ps1
.\setup-renthub-atlas.ps1 -Apply
```

The preview is read-only and creates no files or credentials. If you use another
administrator profile, pass `-AdminProfile YOUR_ADMIN_PROFILE` to setup. The
administrator must be allowed to manage the project service account and the
organization's API access policy. It is separate from the runtime account.

Setup verifies the cluster/project and that the organization contains exactly one
project, matching RentHub. Only then can `-Apply` disable the organization's
administration-API IP-list requirement. This is the authorized changing-network
policy for a RentHub-only organization; it is not a database network setting.
An unexpected or shared organization stops setup rather than relaxing its policy.

Each laptop/Windows-user pair receives a separately named service account with
only `GROUP_NETWORK_ACCESS_MANAGER` (Project Network Access Manager). No Project
Owner role is granted. Its administration-API access list must be empty; setup
will not delete an existing restrictive list or repurpose an overprivileged
account. Protect this credential because its administration API can be used from
changing networks. Individual database network restrictions still apply.

The account's 365-day secret and client ID are saved in Windows Credential Manager
using the Atlas CLI's secure-store format. No secret goes in command arguments,
Git, Flutter, the API `.env`, logs or setup receipts. The CLI profile file contains
only nonsecret metadata. Setup verifies secure storage and real project/access-list
requests before selecting the new profile. Do not copy the credential store to
another laptop. Run setup separately under the Windows user who runs RentHub.

Setup changes only `ATLAS_PROFILE=renthub-launcher` and the verified
`ATLAS_PROJECT_ID` in the private API `.env`. Other application settings are
preserved. Profile precedence is:

1. Explicit launcher `-AtlasProfile NAME`.
2. Private API configuration `ATLAS_PROFILE`.
3. Existing `default` fallback for older installations.

No application endpoints, database schema or records are changed. Running setup
again reuses the matching account and stored credential; it does not create a new
secret unless `-RenewSecret` is explicitly supplied. A local mutex prevents two
setup runs for the same laptop/user from racing. Normal startup only registers
network access and does not create service accounts or change organization policy.

## Renewal and recovery

The original laptop's secret expires **6 November 2027, 10:15 am MYT**. Renew before
that date. Each laptop displays its own date, also retained in an ignored,
nonsecret receipt at `services/api/.data/atlas-automation/setup-DEVICE.json`.

```powershell
# Only needed for this occasional administrator operation
atlas auth login --profile default
.\setup-renthub-atlas.ps1 -Apply -RenewSecret
```

Test the normal launcher, then retire the previous secret for this laptop's
service account in Atlas. Setup does not delete old secrets automatically. Never
revoke the other laptop's credentials. A new Windows profile or lost credential
store requires explicit credential recovery/renewal; do not paste or copy secrets.

| Message/check | Recovery |
| --- | --- |
| Automation credential invalid, expired or revoked | Review the dedicated account, then explicitly renew using the administrator setup. Personal browser login alone does not repair the runtime profile. |
| Missing automation profile | Run the one-time setup on this laptop. A custom profile must be selected consistently. |
| Administration-API network restriction | Check the dedicated organization policy and this account's empty API access list. Do not widen database access to all IPs. |
| Project permission denied | Restore the intended Project Network Access Manager role for the correct project; do not grant Owner as a shortcut. |
| Network, DNS, TLS or rate-limit failure | Resolve connectivity or wait, then rerun. No automatic personal login or cloud-write retry is started. |
| Credential-store unavailable | Run as the Windows user who configured the profile and check Windows Credential Manager. Plaintext fallback is rejected by setup. |
| Setup times out after a cloud request | Run the read-only preview before retrying. It checks for an existing laptop account; an uncertain write is not blindly repeated. |
| Atlas authentication environment overrides detected | Remove conflicting `MONGODB_ATLAS_*`/`MCLI_*` authentication or endpoint overrides from that terminal. Their values are never echoed. |

The matching database URI still needs valid database-user credentials. The
service account is for Atlas network administration, not application data access.
No application-secret rotation, model training or hosting change is involved.

## Verification results

| Check | Result |
| --- | --- |
| PowerShell syntax, startup compatibility and owned-process cleanup | Passed general launcher suite with disposable process-tree integration. |
| Port recovery, native command arguments/stdin/timeouts, presentation/services-only and Android startup paths | Passed reliability suite, including integration fixtures. |
| Project/cluster matching, new/shared IPs, expiry, concurrent duplicate registration and preservation of other entries | Passed Atlas access suite with mocked cloud writes. |
| Profile precedence and validation; automation vs personal error guidance | Passed automation suite. |
| Organization isolation, minimum role, empty account API list, 365-day request, reuse and explicit renewal | Passed automation fixtures. |
| Credential privacy and secure-vs-insecure CLI redaction markers | Passed automation regression; actual profile metadata contains no plaintext credentials. |
| Windows credential-store compatibility | Disposable nonsecret probe saved, read and removed successfully. |
| Real original-laptop setup | Applied successfully: dedicated organization verified, account/credential stored, cluster and project access verified with that service account. |
| Real database network check and read-only ping | Passed using `renthub-launcher`; current IP already allowed and all prior entries preserved. No new database entry was needed. |
| Second laptop and changed-network live registration | Requires user/device verification; concurrent registration and expiry behavior were tested with fixtures, not by removing working live access. |

The first live setup stopped at a conservative credential verification check:
Atlas CLI returns a redacted secure-storage marker, which the initial code treated
as plaintext. The check was corrected and regression-tested; setup then reused
the same account/secret successfully. No duplicate account or extra secret was
created for that retry. No credential values were printed.

One early restricted test run could not inspect its disposable process tree.
The integration suite was rerun with Windows process inspection and passed;
the earlier disposable process had already exited. No unrelated service was
stopped. Flutter/API/AI code was unchanged, so their builds/tests were not repeated.

Commands from the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_atlas_access_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_atlas_automation_test.ps1 -Integration
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_launcher_test.ps1 -Integration
powershell -NoProfile -ExecutionPolicy Bypass -File apps/renthub_flutter/test/run_renthub_reliability_test.ps1 -Integration
```

Before the demonstration, finish setup on laptop two, run its normal launcher,
check that records/photos are shared, then repeat after a network change. Keep
one main backend/blockchain host for the complete multi-device demonstration;
Atlas does not synchronize two separate local chains or live socket servers.

## References

- [Atlas administration API access configuration](https://www.mongodb.com/docs/atlas/configure-api-access/)
- [Service-account secret lifetime and rotation](https://www.mongodb.com/docs/atlas/tutorial/rotate-service-account-secrets/)
- [Atlas CLI secure Windows keyring implementation](https://github.com/mongodb/atlas-cli-core/blob/master/config/secure/go_keyring.go)
- [Atlas CLI profile redaction behavior](https://github.com/mongodb/mongodb-atlas-cli/blob/master/internal/cli/config/describe.go)

## Commit message

```text
feat(launcher): add secure per-laptop Atlas automation setup

- select Atlas profile from launcher arguments or private configuration
- provision narrowly scoped laptop service accounts with 365-day secrets
- verify the RentHub-only organization before changing API access policy
- store credentials in Windows Credential Manager and preserve application settings
- handle expired IP entries and classify automation failures without browser fallback
- cover setup, secure storage, profile precedence and network-access regressions
- document one-time laptop setup, daily startup, renewal and recovery
```
