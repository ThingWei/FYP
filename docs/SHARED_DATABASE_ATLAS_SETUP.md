# Shared RentHub database: MongoDB Atlas

3 November 2026. The original local database has been copied to the user's
Atlas `renthub` database. The original laptop's API `.env` now uses Atlas.
The other laptop still needs the same private URI and the updated launcher.
The local source database remains intact for rollback; it no longer receives
updates made through the Atlas-connected API.

## Prepared locally

- The launcher reads `MONGODB_URI` instead of always demanding localhost:27017.
  Single local hosts retain a TCP check using their configured port, including
  IPv6 loopback. Atlas SRV, remote and multi-host connections are verified by the
  existing API/database readiness flow. Credentials are not printed or passed
  to Flutter. Existing Auth0, model, storage and blockchain checks remain.
- Launcher syntax and regression checks passed for local, remote, SRV,
  multi-host, custom-port, malformed-config and credential-disclosure cases.
- Read-only original-database inspection found MongoDB **9.0.2**, 32 collections
  and **1,446 documents**.
- Official portable MongoDB Database Tools 100.20.1 were downloaded into the
  ignored private `.data/tools/` folder. Their archive SHA-256 was checked against
  MongoDB's official `downloads.mongodb.org/tools/db/full.json` manifest.
- A private compressed BSON backup and manifest were created under
  `services/api/.data/backups/renthub-2026-11-03-tVIUj1/`. The archive is 152,268
  bytes. Collection counts were stable before/after; no source database writes
  were performed. It is a live standalone backup, not an atomic cross-collection
  snapshot. Keep application writes paused during the final migration.
- The backup contains private application data and remains Git-ignored. It was
  retained locally; a separately verified logical snapshot was used for Atlas.

## Transfer and verification completed

- Source: MongoDB **9.0.2**; target: Atlas MongoDB **8.0.36**.
- **32 collections / 1,446 documents** transferred, including 16 accounts,
  27 listings, 27 bookings, 10 rentals, 30 payment records and 117 upload records.
  Payment records retain their actual simulation/provenance status.
- The logical snapshot contains **1,207,329 bytes** of BSON. Private snapshot,
  manifest, transfer report and pre-switch API configuration are in
  `services/api/.data/backups/atlas-logical-1793718304549/`.
- Every collection's count and sorted raw-BSON SHA-256 matched before normal
  target TTL expiration was enabled. IDs, dates, numeric BSON types, leading-zero
  strings, relationships, private fingerprints and evidence markers were copied
  unchanged. Verification reports contain aggregate results, not private values.
- Text, compound, partial unique and TTL indexes were recreated. The first pass
  stopped because MongoDB 9's geospatial index encoding version 4 is unsupported
  on the target. The verified-prefix resume rebuilt that index using Atlas's
  supported default encoding. Fields, directions and uniqueness/filter options
  were checked; server-specific encoding versions and explicit-versus-implicit
  simple collation are intentionally normalized during index comparison.
- The private `verified_mykad_identity_unique` index is present and unique.
  No source records were changed or removed. No identity secret was rotated.
- Only `MONGODB_URI` changed in the original API environment. All other parsed
  settings were compared before/after and preserved. The old environment is
  backed up privately inside the logical snapshot directory.
- Read-only checks using the application's configured Mongoose connection and
  Express app passed: readiness **200**, public listings **200**, unauthenticated
  admin listings **401**. Schedulers, index creation and application writes were
  disabled for these checks. No user password or sign-in token was fabricated.
- Migration/index/BSON tests plus existing identity-binding and precise-location
  tests: **28 passed**, using isolated temporary databases and explicit mock/test
  settings. An initial run inherited live Auth0 mode and returned expected 401s
  to mock headers; rerunning with the proper test environment passed. The live
  authentication configuration was not changed.
- Launcher syntax/regression tests and `git diff --check` passed. No Flutter
  presentation changes were made for this transfer, so app builds were not repeated.

### Finish on the other laptop

1. Copy the updated `apps/renthub_flutter/run-renthub.ps1` from this workspace
   (or pull it once committed). Older launchers may still demand local MongoDB.
2. In that laptop's `services/api/.env`, set `MONGODB_URI` to the **same private
   Atlas connection**, including `/renthub`. Do not paste it into chat or Git.
   Keep the other settings, with compatible identity/session secrets and Supabase
   credentials as described below. The private `atlas-target.env` can be used as
   the source for the single setting; it is not a public transfer artifact.
3. Complete the [one-time Atlas automation setup](ATLAS_AUTOMATION_SETUP_RESULT.md) on that laptop. It registers its current individual IP when needed; daily browser login and manual IP approval are unnecessary after setup.
4. Stop/restart its API through the usual launcher, then refresh/reopen RentHub.
   Accounts and saved records should come from the shared database. No restore,
   seed command or model retraining is needed on that laptop.
5. Use the normal sign-in yourself to verify accounts, bookings and protected
   documents. Authenticated device/account verification is still required; it
   was not simulated by the migration checks.

## Account and connection setup

1. Create an Atlas account and choose a **Free** cluster. `renthub` is a suitable
   cluster name. Cluster name and database name are independent.
2. Create a database user with read/write access to the intended application
   database. Keep its credentials private.
3. Add the laptops' current public outbound IP addresses to Atlas Network Access.
   Two laptops on the same network may share one public IP. Update the allowlist
   when moving networks; avoid depending on an unrestricted network entry.
4. Open **Connect → Drivers**, select Node.js and copy the connection string.
   It must select the `renthub` database, not an omitted/default database.

Example shape only; never commit a real password:

```text
mongodb+srv://DB_USER:URL_ENCODED_PASSWORD@YOUR_CLUSTER/renthub?retryWrites=true&w=majority
```

During preparation, keep the future connection string in a private local file
such as `services/api/.data/atlas-target.env`. Do not paste credentials into chat
or replace the working source connection before data migration is verified.

## Transfer tool and rollback

`services/api/src/scripts/migrateSharedDatabase.js` provides a bounded logical
transfer without new packages, source writes or automatic environment changes.
It refuses collection options/views it cannot preserve, excessive document/data
sizes, nonempty targets and changed source snapshots. Ordinary dump/restore
compatibility was not assumed across the source/target server versions.

From `services/api`, before a future one-time move into another empty target:

```powershell
node src/scripts/migrateSharedDatabase.js
node src/scripts/migrateSharedDatabase.js --snapshot
node src/scripts/migrateSharedDatabase.js --snapshot --apply
```

The first command only plans; the second saves a private snapshot without target
writes; the third explicitly copies. These commands expect a local source in
`.env` and an Atlas target in `.data/atlas-target.env`. **Do not rerun them now**:
the active environment already points to Atlas and the target is populated.
The completed transfer did not rely on Mongoose defaults, model hooks or seeds.

After an interrupted transfer, an explicit `--apply --resume=atlas-logical-NNN`
can continue only when existing target collections are empty or exactly match
that snapshot and all existing indexes are compatible. Unexpected records,
partial document batches, changed sources or unknown collections abort without
merging/deleting records. There is no automatic cleanup or environment switch.

For rollback, stop application writes first. The original local source and
`api-local-before-atlas.env` remain available. Restore only the original database
URI if appropriate; do not overwrite unrelated settings. New Atlas writes are
not copied back into the old local database, so rollback after further use needs
a separate reconciliation plan.

For any future transfer, stop application writes and scheduled jobs on both
laptops. Compare per-collection counts, identifiers, relationships and indexes,
including the private verified-identity uniqueness index.

After verification, set the same target `MONGODB_URI` and database name in each
laptop's `services/api/.env`. Preserve compatible private identity-matching,
session-signing and storage configuration across instances. Do not rotate the
identity-matching secret while moving existing fingerprints. Restart APIs so
they load the changed environment, and copy the updated launcher to both laptops.

Sharing one database makes saved records available to both APIs on their next
read. It does not replicate two local databases. Existing Socket.IO connections
are process-local; a refresh may be needed to see another instance's update.
Instant cross-instance events require separate implementation/verification.

## Other services and demonstration limits

### Images on the second laptop

The Supabase bucket does not appear inside MongoDB Atlas. Atlas stores upload
references and application records; the existing Supabase project stores file
bytes. Do not create a new empty bucket/project just for the new laptop.

For the reported missing images in RentHub on the other laptop, a private setup
bundle was prepared at `services/api/.data/storage-transfer-private-v2.zip`. Extract
it into the other laptop's `services/api/.data/` so it contains
`.data/storage-transfer/setup-storage.mjs` and `storage.env`. Stop that API, then
run from `services/api`:

```powershell
node .data/storage-transfer/setup-storage.mjs --apply
```

The script verifies bucket access with the proposed configuration before any
environment write, backs up the old environment privately, and replaces only
the four storage fields. No database setting, authentication setting, bucket
content or record is changed. Restart the API/launcher after success. Conflicting
inherited process environment variables are reported by name only and require
a fresh/correctly configured terminal. Default/`--check` mode is read-only.

The bundle contains a server secret: transfer privately and never commit or
post it. Its script is a portable copy of
`services/api/src/scripts/setupSharedStorage.js`. Six isolated tests passed
for setting preservation, idempotence, duplicate/malformed input, runtime guards,
safe failure categories and wrong-key versus missing-bucket responses.
The portable tool's live read-only bucket check passed on the original
laptop. It has not yet been run or diagnosed on the other laptop; missing storage
configuration remains a likely cause, not a confirmed remote diagnosis.

The first remote setup attempt returned a generic failure under Node.js 20.
Inspection of the installed Supabase 2.117.2 SDK found that client construction
initializes Realtime even for Storage calls. With native WebSocket removed in a
controlled local reproduction, construction throws before any bucket request.
This is consistent with that remote runtime but the original generic response
does not conclusively identify its exception. Version 2 of the setup bundle
requires Node.js 22+ and native WebSocket/fetch before inspecting private files,
and reports missing setup/environment files, DNS/HTTPS failures, timeout,
authorization failure and missing bucket without printing raw SDK errors.
Install Node.js **24 LTS** on the other laptop, reopen PowerShell, verify `node -v`,
then retry with the updated bundle. Supabase's
[support notice](https://github.com/orgs/supabase/discussions/45715)
requires Node.js 22 or later. No dependency downgrade, WebSocket shim, TLS bypass,
automatic retry or environment write on a failed check was introduced.

In the second laptop's `services/api/.env`, use the same four settings from the
original laptop (copy their actual values privately, not these placeholders):

```dotenv
STORAGE_MODE=supabase
SUPABASE_URL=https://YOUR_EXISTING_PROJECT.supabase.co
SUPABASE_SECRET_KEY=YOUR_EXISTING_SERVER_SECRET
SUPABASE_STORAGE_BUCKET=YOUR_EXISTING_BUCKET_NAME
```

Restart the API after changing these settings. The server secret belongs only
in the API environment, never in Flutter/Dart defines or chat. If a bucket is
missing in the Supabase dashboard itself, check the original account, organization
and project under Storage; changing the MongoDB connection does not move or
create Supabase buckets.

Read-only recheck on 3 November 2026 still downloaded representative public and
private Supabase objects successfully and matched their stored checksums. The
second laptop's settings have not been inspected directly. The nine older local
files described below are a separate case and will not be fixed by these settings.

- MongoDB Atlas does not host the Express API, Python AI or trained model files.
- Both instances need consistent Supabase/storage settings to access shared
  uploaded files. Of 117 stored upload records, 108 identify Supabase and nine
  identify legacy local files. Representative public and private Supabase files
  were downloaded in memory and their checksums matched; this is a sample, not
  a full 108-file availability certification.
- All nine legacy local files still exist on the original laptop; eight are
  referenced by other stored records. Atlas holds their records, not their file
  bytes. These require a separate reviewed storage migration to make them shared.
  Merely copying local bytes to the other laptop is insufficient while the
  current storage adapter selects the configured Supabase backend globally.
  No legacy files were uploaded, deleted, relabelled or made public in this work.
- Two independent local Ganache chains are not synchronized by Atlas. For a
  consistent booking/payment/blockchain demonstration, use one active backend
  or a deliberately shared blockchain RPC/network/contract configuration.
- Price-source jobs already use database leases; lifecycle operations contain
  per-operation locks/atomic claims, but a shared database alone is not a full
  multi-instance deployment certification. Use one scheduled-job/financial
  processing instance until multi-instance behavior is separately verified.

No trained models need retraining for this database move. Demo records retain
their provenance and do not become genuine rental evidence by moving to Atlas.

References: [Atlas Free limits](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/),
[mongodump](https://www.mongodb.com/docs/database-tools/mongodump/),
[mongorestore](https://www.mongodb.com/docs/database-tools/mongorestore/).

## 5 November 2026: Atlas CLI session expiry and launcher recovery

The launcher formerly mapped every failed Atlas CLI request to a login/permissions
instruction and contacted the administration CLI before trying the database.
This could force an unnecessary browser sign-in even when the current network
already had working database access.

Startup now performs a read-only connection/ping first. A successful database
probe skips CLI discovery, CLI authentication, IP discovery and access-list
operations entirely. If the database is unreachable, the existing temporary
single-IP registration flow remains, followed by bounded propagation checks
before any RentHub services start. `-SkipAtlasAccess` retains its explicit behavior.
Existing access entries, 24-hour expiry and other laptops' entries are preserved.

CLI failures now have safe, distinct guidance for expired/missing sessions,
missing profiles, project permissions, unsupported CLI flags, rate limits,
network/TLS failures and saved-credential access. Unknown failures do not assert
that a login expired. Native account details, tokens and URLs are not repeated.

For the reported failure, the real project-list request explicitly reported an
expired session and requested login. `atlas auth whoami` could still display the
remembered account when run with normal Windows credential access; that did not
establish that its project requests remained authorized. An earlier restricted
credential check returned signed-out status and was superseded by the actual
project-request diagnostic. The current read-only database probe also failed;
its boolean result alone does not prove whether the cause is expired IP access,
connectivity or database credentials. No access entries or database records were
changed by this diagnostic work.

MongoDB documents a **12-hour timeout** for Atlas-credential sessions in Atlas CLI
and other developer tools, potentially shorter when the main web session ends.
That session is separate from the launcher's 24-hour network entry and from
RentHub's database-user URI. See
[MongoDB session timeout documentation](https://www.mongodb.com/docs/atlas/tutorial/manage-organization-settings/).

Renew this user's session normally, then rerun the updated launcher:

```powershell
atlas auth login --profile default
# Complete the browser sign-in yourself, then from apps/renthub_flutter:
.\run-renthub.ps1
```

No passwords or device authorization codes need to be shared. Default/user-account
sessions were not replaced with a service account or made permanent by this fix.

Both standalone PowerShell suites passed: general launcher regression checks and
Atlas-specific tests. Coverage includes a reachable database with no CLI installed,
unreachable database with missing CLI, successful registration, failed CLI sign-in,
profile preservation, bounded retries, precise error classification and redaction.
All access-list mutations in tests were mocked. Real renewal and post-renewal
launcher startup remain user sign-in/device verification steps.


## 6 November 2026: per-laptop automation replaces daily personal login

The earlier session-expiry section documents the previous personal-profile recovery.
For everyday operation, use the new [Atlas automation setup](ATLAS_AUTOMATION_SETUP_RESULT.md).
The original laptop has a verified `renthub-launcher` service-account profile in
Windows Credential Manager; its secret expires on 6 November 2027. The organization
was confirmed to contain exactly the configured RentHub project before its
administration-API IP-list requirement was disabled. The dedicated service account
has only Project Network Access Manager permissions and an empty administration-API
IP list. Database network entries remain separate and narrowly scoped.

No database records, shared storage configuration or application secrets were
changed. The second laptop requires its own one-time setup and device verification.
Do not copy the original laptop's credential store. The database remains shared;
API, AI and blockchain hosting remain local as described above.
