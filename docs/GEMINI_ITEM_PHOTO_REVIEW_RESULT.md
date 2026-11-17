# Administrator item-photo assessment

Updated 17 November 2026.

Gemini provides photo observations for administrator decisions. The admin listing details use one **AI photo assessment** panel. Existing local image checks continue in the submission flow.

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

The integration pins the supported model to `gemini-3.1-flash-lite`; a different configured model is unavailable rather than silently falling back to a potentially paid model. Google's current documentation lists image input, structured output and free-tier access for this model. Availability and quotas can change. RentHub does not upgrade the project, provision billing or switch providers. [Model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite), [pricing](https://ai.google.dev/gemini-api/docs/pricing), [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).

## Everyday flow

1. Owners upload item photos and submit their listing. Processing is controlled by the platform. The Owner form has no AI enable/disable checkbox.
2. Eligible physical listings enter the shared review queue. Existing pending submissions are reconciled in batches of 20. Drafts, services and deleted listings are excluded from processing.
3. Open **Admin → Listings → record details → AI photo assessment**. The current saved result appears immediately. Missing current-format checks are ensured automatically, and pending results update while the details remain open.
4. Choose a photo under **By photo** to read only its observations and concerns. Comparisons involving several images appear under **Across-photo notes**, with all relevant photo numbers. Selecting a photo opens the full-screen black gallery.
5. Approve or reject using the existing moderation controls. Photo observations provide assistance. Authenticity, ownership, functionality and hidden defects require evidence beyond photos.

Opening an eligible physical listing ensures one current assessment through the existing admin photo-review endpoint. `intent=ensure` reuses work and cached results. Explicit `intent=retry` recovers failed attempts. Status refreshes perform read-only requests. Gallery and dialog return resume status updates automatically.

## Availability and recovery

Both API and AI services use their own `GEMINI_ITEM_REVIEW_ENABLED` flag. The AI service also needs its key and supported model. Restart the original launcher after editing private environment files so running processes load the changes.

The internal `GET /verify/item-vision/status` checks configuration without sending photos or calling Google. Preflight checks have a 2.5-second local-service timeout. API/AI disagreement, missing configuration and service outages produce distinct safe reasons. The API readiness response includes its running photo-review flag and processing contract. The launcher checks both services, warns when a reused API differs from its saved configuration, and rejects older API capabilities.

The panel separates current service availability from the last assessment. An earlier disabled/configuration failure becomes eligible after configuration recovers. The scheduler requeues these pending jobs once. Saved successful assessments remain visible during an outage. Storage/provider timeouts require an explicit retry because the earlier request may have reached the provider.

The panel distinguishes waiting, checking, setup required, service unavailable and local daily-limit states. A temporary request-spacing wait is shown as waiting. Provider quota responses retain a general limit/wait state because the provider may enforce several quota periods.

## Processing and privacy

- The internal processing contract is `renthub-item-vision-v3`. Express supplies `processing_authorized=true` after server eligibility checks. Historical Owner consent records are retained. The deprecated optional `photoReviewConsent` write field is accepted for older clients and has no effect on review eligibility.
- Only 3–10 owned, registered listing-photo uploads are eligible. Identity documents, holder photos, vehicle grants, avatars, foreign uploads and arbitrary URLs are excluded.
- Images are bounded, resized and re-encoded with filenames and metadata removed. The prompt uses all 22 physical subcategory contexts and peripheral distinctions.
- The provider schema requires exactly one assessed-or-unassessable result per supplied image and separately scoped findings for several photos. It rejects malformed results, sensitive-content findings, invalid photo numbers and prohibited authenticity claims.
- Google receives eligible item images under the configured project's service terms. Free-tier data-use conditions should be reviewed in the existing Google project setup.
- Gemini results are admin-only. They do not change listing moderation or independent pricing-evidence eligibility.

## Queue and limits

One shared database-backed budget coordinates both laptops. The default is 20 attempts per UTC day, one in-flight request and at least 60 seconds between starts. Failed or uncertain provider attempts consume allowance conservatively. This application limit operates alongside Google's quotas.

Budget is claimed before reading originals. Storage waits, provider deadlines and leases are bounded. Queue writes are deduplicated using listing identity, current photo-content hashes, relevant item fields, processing contract and model. Changed or deleted listings invalidate in-flight results.

Provider quota/busy responses have at most three automatic attempts with bounded backoff. Successful snapshots are cached. Expired in-flight leases require explicit retry. API downtime pauses the worker.

## Verification

Current results and remaining walkthrough checks are recorded in [Admin photo review and case workspace](ADMIN_PHOTO_REVIEW_AND_CASE_WORKSPACE_RESULT.md). Earlier deletion and review behavior is documented in [Listing deletion and admin photo review](LISTING_DELETION_AND_ADMIN_PHOTO_REVIEW_RESULT.md). Earlier verification logs remain in the private `.data/testing/20261116-gemini-review/` and configuration-recovery directories.

Automated provider tests use synthetic pixel fixtures and mocked responses. Real-photo recognition and authenticity accuracy require separately reviewed evaluation data. Provider model access alone does not establish remaining quota or successful image inference.

## RentHub allowance and Google rate limits

The daily application allowance is separate from Google's RPM, TPM and RPD limits. RentHub defaults to 20 attempts per UTC day, shared across both laptops. Each attempt is reserved before reading images, so failed or uncertain attempts can consume the application allowance. A low current-minute RPM does not describe the application's daily counter.

The admin message identifies RentHub's allowance, shows its used/limit count and the next reset. UTC midnight is 8 am in Malaysia. A saved budget reason from an earlier day is treated as a waiting state once the current allowance is available.
