# Catalogue browsing and freshness

Date: 24 October 2026. Scope: improve the existing providers and picker before
onboarding another API. No new category, vendor account, production dependency,
product-review queue, training, price ingestion or database migration.

## Owner experience

- Brand/model sheets now offer **Refresh suggestions** and **Load more** when
  another bounded window is available.
- Saved/reviewed suggestions appear immediately. When a check is needed, the
  sheet keeps them selectable while updating in the background.
- Failure retains the displayed choices, search text, selected product and
  manual-entry action, with friendly retry guidance instead of raw errors.
- Search changes invalidate pending refresh/expansion responses. A one-character
  query still makes no search request. Manual entry remains accessible while
  loading, after failures and for unsupported products.
- Older API responses without new metadata remain usable, without inventing
  pagination or automatically repeating unknown requests.

## Contract and implementation

Existing authenticated `/api/v1/catalog/brands`, `/models` and `/search` paths and
their `data` list remain unchanged. Optional query controls:

| Control | Meaning |
| --- | --- |
| `limit` | Requested expanding window, 1-120; defaults to existing `CATALOG_MAX_RESULTS` (normally 12) |
| `preferCache=true` | Preview saved/reviewed suggestions before provider work, if any exist |
| `refresh=true` | Check providers rather than accepting a fresh cached shortcut; recent failures still back off |

Response metadata adds `limit`, `hasMore`, `nextLimit`, `reachedLimit` and
`refreshNeeded`, alongside existing provider availability/staleness information.
The picker asks for 12, then `nextLimit` (normally 24, 36, ... up to 120).
Each response replaces the whole requested window; this is not offset paging.
Server-side deduplication and retained canonical IDs avoid repeated cards or
page-boundary omissions when curated/provider results overlap.

One extra result is requested internally as lookahead, bounded at 121. Cache
reads and writes are bounded. Providers now honor expanding windows rather than
silently returning their original first 12 rows. SPARQL uses stable label/entity
ordering. General/device text candidate searches respect Wikidata's 50-candidate
bound; Open Library scans at most 500 works and validates at most five authors
per brand search. These limits can require a more specific search; they are not
exhaustive catalogue crawls. Category/manufacturer/subject validation is retained.

Successful query-window checks are remembered in a bounded 256-entry process
map for at most 24 hours (or the shorter configured catalogue TTL). The map also
coalesces simultaneous identical provider refreshes. It contains no account
credentials or private listing data. Restart/eviction simply requires another
check. This is per-process, not a distributed scheduler or freshness guarantee.

Cached previews flag unknown/old query windows for one foreground-triggered
background check. A recent failure with saved records backs off for 60 seconds
per query/window. Failed checks do not update external `lastSyncedAt` dates or
discard records. NHTSA make refreshes bypass the in-memory TTL but replace that
snapshot only after successful retrieval. Old external rows retained alongside a
new check remain marked stale when appropriate. Cache availability is not proof
that an external provider is currently reachable.

`ApiClient.requestEnvelope` preserves metadata and existing HTTP error details;
normal `request` still returns only `data`. `CatalogPage` validates metadata,
and the Owner form uses the new loader. Existing Auth0 behavior, authorization,
manual selections, canonical IDs and pricing payloads are unchanged.

## Actual live check

Executed against public Wikidata with a new temporary MongoDB, not the user's
development database. Apple / Smartphones, selected manufacturer Q312:

| Step | Count | Provider/result | Observed elapsed time |
| --- | --- | --- | --- |
| Saved preview, limit 12 | 2 | reviewed cache; `refreshNeeded=true` | 30 ms |
| Explicit refresh, limit 12 | 12 | Wikidata available; `nextLimit=24` | 1,281 ms |
| Load more, limit 24 | 24 | Wikidata available; `nextLimit=36` | 2,445 ms |

These are individual observed runs, not latency promises or a complete/current
product coverage benchmark. No live marketplace data was changed by this check.

## Verification

- API regressions cover windows beyond 12, stable IDs, repeated cache reads,
  stale previews without network calls, explicit refresh, failure/date
  preservation, backoff, concurrent refresh coalescing and malformed controls.
- Provider tests cover smartphone window expansion, anonymous search caps and
  bounded book scans with unchanged subject filtering.
- Flutter tests cover metadata compatibility/errors, authenticated transport,
  401/403 preservation, retained choices during background updates at
  360/390/1024 pixels with 1.5x text, expansion/retry and superseded responses.
- Existing Owner tests still exercise catalogue selection, manual no-match vs
  unavailable states, price suggestions and explicit price application.
- Full API: 480 passed, 3 existing optional live tests skipped.
- Full Flutter: 473 passed, 3 existing skips.
- Dart analysis: no issues.
- Rendered and inspected the 390-pixel catalogue preview with the installed
  Roboto/Material icon fonts; header refresh/close controls, search and manual
  entry remain readable. Generated preview:
  `apps/renthub_flutter/build/ui-checks/catalog-picker-390.png` (not a source asset).
- OpenAPI YAML: parsed successfully, including new shared parameters/schema.
- Web build: passed; existing Socket.IO Wasm dry-run and optional Cupertino-font
  warnings remain non-fatal.
- Android debug build: passed. Existing Firebase/preferences Kotlin Gradle
  migration warnings remain non-fatal; no plugin upgrades were included.
- Pricing artifact remains unchanged:
  `2B9B23AC8069A3FEE776181131F65D1EBC82AA135A88CA918ABEDCAE5059A976`.

## Remaining limits and handoff

This exposes more available records and makes refresh explicit. It cannot create
a missing product, fill missing source classifications, guarantee Malaysian
variants or order every product by release date. Some categories remain curated
or use text-search fallback; an empty brand browse does not scan all Wikidata.
At the 120-result/candidate bounds, use a precise model search or manual entry.
Product identity remains separate from legitimacy and Malaysian rental prices.

The optional new-product review workflow and second-provider onboarding were
not implemented. Test specific missing recent models before choosing another
provider or promising broader coverage. No model retraining is needed for these
browsing changes.

Restart the API and hot-restart/relaunch Flutter. Open a listing's Brand/Model
sheet, use the refresh icon, then scroll to **Load more** if offered. Check a
failed update retains choices. Physical-device network/interaction UAT is still
recommended; widget tests and builds do not replace it.

Suggested commit:

```text
feat(catalog): add bounded browsing and stale-while-refresh suggestions

- expand provider/cache result windows with lookahead and safe limits
- expose refresh, cache-preview and expansion metadata without changing paths
- retain choices while checking updates and ignore superseded responses
- coalesce refresh requests and preserve cached evidence after failures
- retain legacy API data requests and metadata-free catalogue responses
- test provider bounds, authentication, cache freshness and picker recovery
```

## Logitech initial-model update fix — 25 October 2026

Reproduced selecting Logitech in Devices → Computers: the manufacturer-only
SPARQL traversal exceeded the existing 4,000 ms request timeout. Curated MX
Master 3S and MX Keys S remained selectable, but the update warning appeared.
Typed exact-model lookup used a bounded model query and did not have that same
unconstrained traversal.

Computers/Gaming initial model browsing now uses Wikidata's indexed
`haswbstatement` manufacturer/brand discovery and validates the returned entity
claims. It requires the selected manufacturer/brand and an allowed product
class through P31/P279 ancestry. Explicit conflicting brands are excluded, so
OEM manufacture alone does not put an Apple-branded mouse under Logitech.
This is shared domain logic, with no Logitech-specific endpoint or exception.
Typed searches retain their model-bounded query. The API format, cache, manual
entry and request timeout are unchanged.

Discovery is limited to 50 product candidates, entity reads to 50 IDs per request,
and ancestry exploration to 96 additional entities and four checked levels.
Unconfirmed classifications remain excluded; this is a first-page diagnostic
improvement, not an exhaustive manufacturer inventory or release-date ordering.
No rental prices or model artifacts changed.

A read-only public check of canonical Logitech returned 12 validated external
mouse/keyboard models plus the two curated choices, with all individual calls
under the unchanged timeout (about nine seconds total with an intentionally
slower one-second request spacing). Repeated subsequent diagnostic requests
received HTTP 429, including another manufacturer's lookup. Thus external
availability is not guaranteed. Those failures still retain saved/curated
choices and the existing short failed-refresh backoff; they do not masquerade
as a successful update. The UI now explains that newer suggestions could not
be checked and that the current choices/manual entry remain available.

Regression coverage includes indexed discovery, canonical manufacturer checks,
conflicting brands, direct/subclass product types, cycles/depth/budget limits,
malformed responses, cache persistence and outage layouts at 360/390 pixels
with 1.5× text. Verification results are recorded after the final checks below.

- Focused catalogue API/provider tests: 42 passed.
- Full API suite: 484 passed, 3 existing optional skips.
- Full Flutter suite: 475 passed, 3 existing skips.
- Dart analysis: no issues.
- Web build: passed; existing Socket.IO Wasm dry-run and optional Cupertino-font
  warnings remain non-fatal.

Restart the API and hot-restart/relaunch the app to load this fix. If an old
failed lookup is still under the process-local 60-second backoff, wait before
refreshing or restart the API. No database cleanup is required.

Additional commit message:

```text
fix(catalog): avoid broad manufacturer scans when preloading device models

- discover bounded products using indexed manufacturer and brand claims
- validate product classes and reject conflicting OEM brand identities
- retain saved choices and clarify external update failures
- cover bounded ancestry, malformed responses, cache and mobile outage states
```
