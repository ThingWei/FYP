# Gemini item-photo review

Implemented 16 November 2026. Gemini adds visual observations for administrators; it does not certify authenticity, ownership, functionality or hidden condition. Local YOLO/YOLO-World, quality, duplicate and risk checks remain separate. No model was retrained or deployed, and no live records or private environment files were changed during implementation.

## Enable it once

1. In [Google AI Studio](https://aistudio.google.com/api-keys), create a server API key for a **dedicated free-tier project**. Check that project's tier and [actual model quotas](https://aistudio.google.com/rate-limit). Do not enable billing to resolve an unavailable free quota. A Gemini consumer subscription is not the app's API configuration.
2. Open `services/ai/.env`. If it does not exist, copy `services/ai/.env.example` first; do not overwrite an existing file. Set:

   ```dotenv
   GEMINI_ITEM_REVIEW_ENABLED=true
   GEMINI_ITEM_REVIEW_MODEL=gemini-3.1-flash-lite
   GEMINI_API_KEY=your-private-key
   ```

3. In the existing `services/api/.env`, add:

   ```dotenv
   GEMINI_ITEM_REVIEW_ENABLED=true
   GEMINI_ITEM_REVIEW_DAILY_LIMIT=20
   ```

4. Keep the key in the AI service only. Never put it in Flutter, a screenshot, Git, a command-line argument or an API request from the app. Both laptops need their own private configuration; use the same dedicated project if they share this queue. Neither template contains a working key.
5. Stop the original launcher and restart your usual `run-renthub.ps1` command. The launcher loads the AI `.env` **only if the file exists**. Existing compatible processes must be restarted to load changed settings; Gemini is not a mandatory startup check.
6. Optionally check configuration/model access from `services/ai`:

   ```powershell
   .\.venv\Scripts\python.exe -m app.training.check_gemini_item_review
   .\.venv\Scripts\python.exe -m app.training.check_gemini_item_review --check-access
   ```

   The first command makes no network request. The second reads Google's model metadata; it sends no photos or generation prompt. Output contains no key. `access=available` confirms model access only, **not billing tier, remaining quota or image-review accuracy**. Verify free status in AI Studio.

V1 pins the supported model to `gemini-3.1-flash-lite`; a different configured model is unavailable rather than silently falling back to a potentially paid model. Google's current documentation lists image input, structured output and free-tier access for this model. Availability and quotas can change. RentHub does not upgrade the project, provision billing or switch providers. [Model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite), [pricing](https://ai.google.dev/gemini-api/docs/pricing), [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).

## Owner and administrator flow

1. The Owner creates/edits a physical listing and selects **Allow Google photo review (optional)** only for non-sensitive item photos. The notice explains Google's product-improvement use. Declining does not block drafts or the existing local/manual flow.
2. Submission runs the existing local checks and saves the pending listing. A consented snapshot is queued without waiting for Google. Services have no item-vision processing.
3. While the API remains running, its worker processes eligible jobs. Admin → Listings → record details → **AI photo review** shows the current state and, when available, item consistency, across-photo consistency, visible condition and branding observations.
4. Concerns reference photo numbers. Tap a finding to open that photo in the protected full-screen gallery. Additional observations stay collapsed under **Photo findings**.
5. **Refresh** reads status. **Check photos** explicitly retries eligible unavailable checks; concurrent taps reuse the job. No key is configured through the admin interface.
6. Administrators still decide the listing. Missing, delayed, declined or failed Gemini output never approves/rejects a listing or adds another approval gate. Existing local enforcement rules remain unchanged.

Replacing/removing photos invalidates consent. Reopening an unchanged saved draft preserves it; unrelated field edits preserve it on the server. Product, condition or photo-content changes invalidate old observations. Old results cannot appear as current. Existing listings are not bulk-processed: an Owner must supply consent through their existing edit/resubmission flow before an administrator can request an individual check.

## Privacy and results

- Only owned image uploads whose purpose is `listing_image` are eligible. No arbitrary URL fetching. Private verification documents, holder selfies, licences, vehicle grants, avatars, messages and addresses are excluded from this pipeline.
- Consent is recorded server-side with its policy version and selected-photo digest. Clients cannot write the consent snapshot or a Gemini result. The worker rechecks consent, ownership, upload purpose and the listing snapshot before forwarding.
- Google receives resized/re-encoded JPEG copies (maximum 1280-pixel side, bounded combined body), relevant declared product fields and fixed instructions. Originals, filenames, EXIF, account information and location fields are not included.
- The declaration is not an automatic redaction guarantee. Owners must not select photos containing people/identity documents, readable personal contact/address information or other confidential details. A wrongly labelled upload can still contain sensitive pixels. Revocation prevents future eligible work and stale results, but cannot recall data already sent to Google.
- Google's free-service terms permit product-improvement use and human review and say not to submit sensitive, confidential or personal information. Do not use this free integration for KYC. [Google's data-use terms](https://ai.google.dev/gemini-api/docs/terms).
- The prompt treats listing text and text inside photos as untrusted evidence, not instructions. It distinguishes actual items from screenshots/illustrations, allows close-up supporting views and requires uncertainty where details cannot be established.
- Strict schemas/enums, bounded findings and photo-index validation apply in Python and Express. Malformed, refused, truncated, obviously personal or explicit authenticity/functionality claims are rejected rather than rendered. These controls cannot eliminate hallucinations; administrators must inspect the underlying photos.
- `authenticityVerified` remains false. No authenticity probability or automatic decision is generated. Detailed observations are available only through admin detail access; public and owned listing responses exclude them. The Owner receives only their own current consent boolean.

## Coverage

The prompt registry covers the existing 22 physical subcategories. These are **configured and protocol-tested instructions, not measured recognition accuracy**.

| Category | Specific categories |
|---|---|
| Devices | Smartphones, Cameras, Computers, Audio, Gaming, Other devices |
| Vehicles | Cars, Motorcycles, Bicycles, Other vehicles |
| Equipment | Tools, Sports equipment, Event equipment, Other equipment |
| Books | Textbooks, Reference books, Fiction, Other books |
| Clothing | Formal wear, Costumes, Traditional wear, Other clothing |

Mice, keyboards, monitors and controllers have explicit separation guidance. Books include page/illustration context; clothing does not infer cultural styles or brand authenticity from appearance. Unknown category/subcategory contexts return an unassessed check. No new taxonomy was introduced.

## Reliability and interfaces

- Added internal FastAPI `POST /verify/item-vision` with a separate `renthub-item-vision-v1` contract and mandatory consent declaration. Existing scanner, licence and item-verification contracts are unchanged. Keep the AI service bound to localhost/private infrastructure; it is not a public client endpoint.
- Added admin-only `POST /api/v1/admin/listings/:id/photo-review` and additive `itemVisionReview` data on the existing admin listing-detail endpoint. Existing listing writes accept only an optional boolean `photoReviewConsent`.
- Private `ItemVisionJob` records are keyed by listing, content/profile snapshot, prompt contract and model. They store safe observations, attempts and timestamps, never image bytes, raw provider bodies or credentials. Shared MongoDB leases fence overlapping workers and stale results.
- One request at a time and at least 60 seconds between request starts across both laptops. The default daily application allowance is 20 attempts, configurable from 1–1000. Its UTC reset is separate from Google's quota schedule; it does not guarantee provider capacity. Failed/uncertain attempts conservatively consume allowance.
- Quota is claimed **before** downloading originals, so budget-waiting jobs do not repeatedly consume photo-storage bandwidth. Storage waits are bounded; request deadlines and leases are bounded separately.
- `429` and `503` responses receive bounded backoff, at most three automatic attempts. A timeout/crashed in-flight lease is unavailable and requires explicit retry rather than blindly repeating a possibly completed request. Each explicit retry still respects the shared allowance and successful snapshots remain cached.
- Bounded reconciliation revisits up to 20 consented pending listings per scheduler tick to repair an interrupted submission/job write. It does not reset failed jobs or rerun successful snapshots. API downtime pauses processing; saved jobs remain.
- Optional availability/model configuration is added to AI health. No network call or model download occurs during health checks. No source/pricing settings, payment rules, authentication behaviour, AI weights or historical listings were modified.

## Verification and remaining work

Tests use isolated temporary databases, synthetic pixel fixtures and mocked provider responses. No listing photos were sent to Google during verification.

| Check | Result |
|---|---|
| Python Gemini tests | Structured output, all 22 contexts, peripherals, unsafe claims, invalid images, consent, disabled/key/model states, timeout/refusal/quota and safe access diagnostic covered. |
| Full AI suite | 666 passed; four existing dependency deprecation warnings. |
| Full Flutter suite | 957 passed; three existing skips. |
| Flutter analyzer | No issues found. |
| Main/admin web and Android debug builds | Passed. Existing Wasm/icon-font and Gradle/Kotlin migration warnings remain non-blocking. |
| Launcher regression | Passed, including optional environment-file arguments and unchanged defaults. |
| Private render checks | Four passed, producing eight fixture-only previews at 360/390/1024/1440 widths with enlarged text. Mobile consent and mobile/desktop admin results inspected. |
| Final API suite | 809 passed; three existing skips; no failures. |
| Live Gemini/real-photo evaluation | **Not run. Accuracy not evaluated.** |

API regression cases cover authorization, wrong-purpose/foreign uploads, URL refusal, private projections, legacy clients, consent create/reopen/change/revocation, queue deduplication, two-worker scheduling, stale results, budget spacing, storage suppression, bounded recovery/retries, uncertain leases and unchanged moderation. UI tests cover preserved inputs, consent invalidation, responsive results, retry/loading recovery, safe errors and stale-account responses.

Private logs: `.data/testing/20261116-gemini-review/`. Previews: `apps/renthub_flutter/.data/gemini-review-previews/`. Neither is a real evaluation dataset or a source of genuine rental evidence.

Before claiming better real-world recognition, configure an eligible key and evaluate permitted overview/detail/unrelated photos across the 22 subcategories. Include the earlier flowchart, screen-photo and book-page failure patterns. Compare local-only and additional Gemini findings against independently reviewed labels; record false matches, misses, unavailable checks and latency separately. No accuracy percentage is justified by the mocked tests. Real-device gestures, screen readers and live Google/storage delivery remain walkthrough checks.

## Commit message

```text
feat: add consented Gemini photo review for administrators

- add bounded structured vision observations with all-22 category guidance
- retain local checks and mandatory human moderation without authenticity claims
- bind optional photo-sharing consent to owned listing images
- queue snapshot-specific jobs with shared leases, quota limits and safe recovery
- prevent duplicate inference, stale evidence and unbounded provider retries
- expose safe admin-only results, photo findings and explicit retry controls
- load optional AI configuration through the existing launcher
- add mocked AI/API/widget regressions, responsive previews and setup guidance
```
