# Azure student hosting review

5 November 2026 (Malaysia). The user confirms that Azure student activation has
completed. Actual remaining credit, expiry, subscription-specific free allowances,
regional quotas and capacity are still unverified. No Azure resource or paid
subscription was created or changed. No account identifiers or credentials are
recorded here.

## Budget finding

Azure for Students normally provides US$100 total credit for 12 months. This is
not a monthly allowance or a promise of a continuously available server for a
year. The previous Google US$300/US$80-per-month planning envelope cannot be
carried over to Azure.

Read-only requests to Microsoft's public Retail Prices API returned these
Singapore (`southeastasia`) Linux Consumption rates. Monthly arithmetic uses
720 hours/30 days. Windows, Spot, Low Priority and separate Cloud Services meters
were excluded. No reservation or savings-plan purchase is assumed.

| Reference size | USD/hour | USD/30 days, compute only |
| --- | ---: | ---: |
| B2as v2 | 0.0944 | 67.97 |
| D2as v5 | 0.108 | 77.76 |
| B2ms (older Bv1 reference) | 0.106 | 76.32 |
| B2s (older Bv1 reference) | 0.0528 | 38.02 |
| B2ats v2 (small free-service candidate) | 0.0118 | 8.50 |

B2as v2 provides 2 vCPU/8 GiB; B2ats v2 is a much smaller-memory size. Neither
listing a retail rate nor the generic student website establishes that the size
is free or available in this user's subscription. Bv1 has an announced retirement;
its rows are cost references, not deployment recommendations.

Even the current B2as v2 would cost approximately US$197.11 for 87 days of
continuous compute, before disks, public IP, backup, traffic, registry and logs.
Consequently, a single continuously running 8-GiB VM is not a defensible
US$100-through-January recommendation at these retail rates. No hosted AI
performance was measured by this price lookup.

## Free-service screenshots received

The user supplied two screenshots of the subscription's free-service meters.
These show unused monthly allowances of 750 hours for B1s, B2pts v2 and B2ats v2,
including separate Linux/Windows rows. They also show P6 disk, public-IP-hours,
outbound-transfer and Standard Container Registry allowances. This confirms those
displayed free meters, not availability of every size/SKU or a US$100 balance.

Current Microsoft specifications give B2ats v2 **2 vCPU / 1 GiB RAM**, and B2pts v2
**2 vCPU / 1 GiB RAM (Arm)**. The similar B2as v2 name is an 8-GiB paid-size
reference and must not be substituted for the free B2ats v2. A 1-GiB VM is not
a defensible recommendation for the whole existing Torch/YOLO/OCR stack.

For a split deployment, B2ats v2 Linux is the preferred x86 compatibility candidate
for lightweight API/chain hosting, conditional on measured memory headroom and
region/quota availability. Blockchain persistence and the API's upload memory
usage must be tested; it is not yet certified that both fit together comfortably.
AI remains a separate consumption-container candidate. Current Consumption
profiles support up to 4 vCPU/8 GiB per replica, subject to regional/account quotas.
Use a measured size and a bounded replica count, not an always-running large VM.

The screenshots show 15 GB of outbound-transfer allowance and 1,500 public-IP
hours. Verify their actual eligible SKU/traffic scope before allocating resources;
the generic meter label is not proof that every modern public-IP SKU is covered.
Also inspect disk, registry, logs and snapshots rather than assuming all ancillary
usage is free. No screenshot file, private account ID or new resource is committed.

## Paths to investigate before provisioning

1. The provided free-service meters establish a basis to plan without assuming
   promotional credit. The user could not find a credit balance and the
   Sponsorships portal reports no active sponsorship. The US$100 balance and
   exact offer remain unverified. Check selected resource SKUs/quotas and actual
   portal cost before provisioning; a small free VM cannot fit all AI models.
2. Price a split deployment: lightweight API and persistent demonstration chain
   on suitable compute, with CPU AI in Azure Container Apps Consumption scaling
   to zero when unused. This could reduce idle compute cost but introduces cold
   starts. Measure model RAM/startup, request timeouts, inference concurrency,
   API-to-AI authentication, quotas, registry/network costs and scheduled tasks.
   This is an unimplemented candidate, not an approved or priced final design.
3. Alternatively, run a larger shared VM only during testing/demo periods and
   deallocate compute otherwise. This does not provide continuous app access;
   disks and retained public addresses can still incur costs.
4. If always-warm, continuous AI is required, obtain a larger credit allocation
   or an explicitly agreed paid budget before selecting that design.

Existing Atlas and Supabase stay separate. Preserve all deployed model weights,
identity secrets, private upload access, saved chain state and evidence provenance.
The earlier Docker/runtime/persistence and nine-local-upload gaps remain as
described in the Google readiness review; no deployment fixes or model retraining
were performed by this account/pricing check.

## Evidence and next checks

- Student activation: user-described; 12-month free-service meters provided,
  with benefit expiry stated as 5 November 2027; promotional credit unverified.
- Public retail rates: retrieved successfully; no additional response pages.
- Displayed free VM/storage/registry/network meters: screenshot-confirmed.
- Exact resource quote/SKU coverage, regional capacity and CPU quota: pending.
- Multi-device and concurrent AI deployment tests: not run.
- Local public pricing response: ignored private file
  `services/api/.data/azure-retail-review.json` (no account data).
- Required next input: actual remaining credit and expiry; confirm acceptable
  AI cold-start behavior before choosing an on-demand design.

Sources:
[Student offer](https://azure.microsoft.com/en-us/free/students/),
[Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices),
[Basv2 sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/basv2-series),
[Bv1 lifecycle/specifications](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/bv1-series),
[Container Apps Consumption pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/).
