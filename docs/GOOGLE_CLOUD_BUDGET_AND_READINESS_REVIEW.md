# Google Cloud budget and deployment readiness

Review date: 5 November 2026 (Malaysia). The user now confirms creating a Google
Cloud account. Trial activation, remaining credit, expiry and project ID have not
yet been confirmed. No Google Cloud resources, billing account, paid subscription
or deployment was created by this review. Cost and hosted performance remain
unverified; this document is a preparation and acceptance plan.

## Goal and credit envelope

Keep one shared RentHub backend available to several devices through January
2027, including Express/Socket.IO, scheduled tasks, Python AI and the current
demonstration blockchain. Atlas and Supabase remain separate hosted services.

Google currently offers eligible new users US$300 credit for 90 days. Eligibility
and the actual credit/expiry must be confirmed at signup. If activated on
5 November 2026, 90 days would end around 3 February 2027; activating later moves
that date. Credit exhaustion can end the trial earlier. On an unupgraded Free
Trial account, resources stop when credit/time expires; continued paid operation
requires a deliberate billing upgrade. This is not an uptime guarantee.

Proposed planning envelope, **not a Google quote**:

| Item | Target |
| --- | --- |
| All Google resources combined | At most US$80 per 30 days |
| 90-day planned usage | At most US$240 |
| Reserve from a full US$300 credit | US$60 |
| Actual account credit and expiration | Not yet available |
| Actual regional VM/disk/network quote | Not yet confirmed |

The all-in target must include compute, provisioned disks, saved chain data,
backups/snapshots, public IPv4, internet traffic, container-image storage and
logging/monitoring above free allowances. Provisioning a machine just because its
VM-only price fits is insufficient. Traffic and usage assumptions must accompany
the quote. Tax/currency treatment must be checked against the billing account.

Published in-use standard-VM external IPv4 pricing is US$0.005/hour, about US$3.60
per 30 days for one address, before any applicable allowance/tax. Regional
compute/disk prices must be confirmed in the official calculator/console; no
exact Singapore VM price was verified by this review. No committed-use purchase,
GPU, paid load balancer, NAT gateway or extra database is assumed in this plan.

Google credits cover eligible Google usage; they do not pay separate Atlas,
Supabase or Auth0 bills. Check each existing account's actual free plan, quotas
and activity rules. Supabase currently lists 1 GB file storage, 5 GB egress and
free-project pausing after one week of inactivity. Confirm the project remains
available before demonstrations. FCM itself is a separate configured integration;
do not assume all Firebase products share the same pricing.

## Candidate to benchmark

Start by evaluating one standard Linux Compute Engine VM with **2 vCPU / 8 GB
RAM**, in Singapore or another suitably close region with a verified quote.
This is a candidate, not a measured minimum or promise of smooth AI inference.
Reserve one stable external IP and allow it in Atlas without temporary expiry;
use the existing database-user URI for runtime connections. Keep AI and Ganache
private to the host/container network, with only HTTPS/WebSocket app access public.

Repository observations:

- AI uses CPU YOLO, optional YOLO-World, Torch risk classifiers, EasyOCR,
  XGBoost and recommendation artifacts. Some requests run multiple models and
  orientations. Small artifact file sizes do not establish low peak RAM or CPU.
- Current model caching helps warm requests but does not bound concurrent image
  inference. Full MyKad scanning and multi-image item checks need explicit
  concurrency and timeout evaluation alongside ordinary API requests.
- Existing API Dockerfile still uses Node 20; the installed Supabase SDK needs
  a supported Node 22+ runtime. Update and test the image before deployment.
- Existing Compose starts local MongoDB and overrides the Atlas URI; create a
  deliberate cloud configuration using Atlas instead of deploying this unchanged.
- Existing Compose does not persist Ganache state or configure restart policies.
  Persistent chain data, key/contract continuity, backups and service auto-start
  must be prepared. Starting a fresh chain will not reproduce old rental receipts.
- Package only needed runtime artifacts and cached OCR/World assets. Training
  datasets and private evaluation photos are not required to serve the models.
- Nine legacy local upload records need a separate reviewed storage migration
  for complete file availability; copying database records alone is insufficient.

## Verification before confirming the configuration

1. Prepare Linux-compatible dependency images, model paths, cached assets,
   secrets, HTTPS, persistence and startup checks locally before activating trial.
2. Obtain the account-specific all-in 24/7 regional quote. Compare the remaining
   credit and actual presentation date against the full running cost and reserve.
3. Deploy one bounded candidate, warm required models, and measure idle/peak RAM,
   CPU, image disk size, startup time and network usage. Local Windows tests are
   useful diagnostics but cannot certify cloud CPU/network performance.
4. Test at least three simultaneous devices: renter, Owner and admin. Exercise
   browse/search, photos, messages/push, booking/demo payment, approval, return,
   agreements and chain receipt retrieval. All use the same backend and chain.
5. Time warm/cold pricing, recommendation, full front/back KYC and three-photo
   item checks. Include simultaneous AI submissions and record queue time, p50,
   p95, failures/timeouts and peak RAM. Preserve strict validation and model
   thresholds. Do not change correctness rules to make performance look better.
6. Initial acceptance targets, **not observed results**: ordinary warm API actions
   p95 at most two seconds excluding third-party sign-in and file transfer;
   expensive AI checks complete within an explicitly measured/configured timeout;
   no process crashes, out-of-memory kills, duplicate financial effects or false
   ready status. Verify usable UI loading/retry behavior while AI is busy.
7. Test service restart/VM reboot, retained blockchain state, protected files,
   scheduled work and reconnection without Atlas CLI/browser sign-in. Perform
   a 24-hour soak and inspect the first day's actual cost before relying on it
   through January. Low AI latency on a laptop is not cloud verification.
8. If this candidate fails, re-price a larger candidate or revise the agreed
   concurrency target before promising budget/performance. Do not silently add
   machines, paid services or resources beyond the chosen trial budget.

Use budget alerts to monitor actual and forecast spend. An alerts-only budget
does not enforce a hard spending cap. Preserve enough reserve for testing,
network, backups and the presentation. Check credit, service availability and
restore procedures before the assessment.

## Current outcome

- Repository/dependency review: completed.
- Official trial, IP, storage and budget terms: checked.
- Google Cloud account: created by the user; trial/billing status pending confirmation.
- Final bill/credit eligibility: pending trial details and a regional quote.
- Hosted concurrency, AI timings and uptime: not tested.
- Google Cloud provisioning/deployment: not performed.
- Guarantee of zero cost or smooth performance through January: not established.

## Official references

- [Trial and free-tier terms](https://docs.cloud.google.com/free/docs/free-cloud-features)
- [Compute pricing](https://cloud.google.com/products/compute/pricing)
- [Pricing calculator](https://cloud.google.com/products/calculator)
- [Disk/snapshot pricing](https://cloud.google.com/compute/disks-image-pricing)
- [Network and external IP pricing](https://cloud.google.com/vpc/network-pricing)
- [Budget configuration](https://docs.cloud.google.com/billing/docs/how-to/budgets)
- [Supabase pricing and inactivity policy](https://supabase.com/pricing)
- [Atlas Free limits](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/)
