# Goritta Sports source: prepared, not enabled

24 October 2026. This delivers a permission-gated parser and regression tests,
not live Sports price coverage. No publisher permission was declared, environment
updated, source enabled, live prices imported or model retrained. Existing work
and all earlier sources remain intact.

## Delivered

- Registered `goritta` for the existing Equipment → Sports equipment domain.
  There are now 16 registered sources, still 22 physical subcategories. A source
  registration is not a usable observation or evidence of market accuracy.
- Inspected one allowlisted public rental page's Shopline structure after the
  access-policy check. The page was accessible. No catalogue was crawled, retail
  product links followed or price dataset saved. Source-dependent quote parsing
  was tested with hand-built fixtures, not executed as live collection.
- Parser accepts the explicit Tents section and its four-day period, with one
  unambiguous MYR amount per item. It keeps the source's model/colour title and
  description/specifications, original amount, full four-day period, pickup
  context and unknown-extra-charge caveat. No age/condition is inferred.
- Reviewed name prefixes Mobi Garden, DOD and KZM identify manufacturers; unknown
  names are excluded rather than assigned a made-up brand. Holiday Retreat and
  Tier Dome series are recognized as camping tents by the shared semantic
  matcher. These are identity/type rules, never brand-specific price rules.
- Maintenance/unavailable items, unsupported camping furniture/lights/power
  stations, multiple prices, deposits, retail/service bundles, headline minima,
  unsupported currencies, changed layout and ambiguous periods fail closed.
- The full package is compared only for four-day requests. An arithmetic daily
  equivalent is not an advertised one-day offer. No days are inferred from tent
  capacity, dimensions or equipment runtime.
- Existing source leases, deactivation, conflicts, deduplication, backoff,
  provenance and statistical/ML inference are reused. Synthetic transport tests
  verify source evidence reaches inference without creating completed rentals.

## Permission gate and onboarding

[Goritta's terms](https://goritta.com/policies/terms-of-service) require express
written permission for reproduction/exploitation. The adapter is marked
`requiresWrittenPermission`. Collection and the diagnostic CLI refuse requests
before configured approval—even with an injected diagnostic transport. The
existing administrator enablement gate also rejects unapproved collection.
Offline fixture parsing does not require a provider request.

After actual publisher permission and a maintainer review (not performed here):

1. Keep the permission/reuse conditions in a private project record; do not
   commit correspondence or imply that a public page establishes permission.
2. Only then append `goritta` to the existing approved-source ID list; preserve
   the other approved IDs. Restart the API. No `.env` was edited in this work.
3. Run the bounded diagnostic from `services/api`:

   ```powershell
   npm.cmd run inspect:price-sources -- goritta
   ```

4. If access and quote parsing pass, use the existing admin source controls to
   enable and sync. Enablement probes first; entering the source page alone does
   not create references. Verify four-day package amounts against the source.
5. Run `npm.cmd run audit:price-coverage`. Review actual eligible counts rather
   than treating the new configured mapping as completed coverage.

A short unsent permission request can say:

> I'm developing RentHub for my final-year project. May I store your published
> tent model/specification, rental amount and period, source URL and observation
> date as attributed asking-price references? I would refresh at most daily and
> would not copy photos, bypass access controls or present your quotes as achieved
> RentHub transactions. Please let me know any reuse or attribution conditions.

No email/message was sent on the user's behalf. Do not mark onboarding complete
until permission, live parser validation and deliberate enablement actually occur.

## Other source blockers rechecked

- **The Joy of Books:** the public product page remained unavailable through the
  web tool. One native policy probe passed, but the next bounded attempt reset
  during policy retrieval (`ECONNRESET`). No reliable product rental-fee/deposit
  separation was validated and no adapter added. Existing cached catalogue/about
  research is a lead, not a current per-title observation. No TLS/access bypass.
- **Fresco scooters:** the public page has period packages, but its FAQ still
  varies price by model. Exact-model association and reuse review remain open;
  the displayed X5 is not automatically assigned the page's package price.
  No adapter/source entry was added for an ambiguous quote.
- The book source cannot be stretched to cover Textbooks or Reference books,
  and a mobility scooter is not an e-kick-scooter. Manual pricing remains usable.

Sources reviewed: [Goritta rental page](https://goritta.com/pages/camp-like-a-pro-goritta-camping-equipment-rental),
[book product lead](https://thejoyofbooks.com/product/the-lord-of-the-rings/),
[Fresco rental page](https://electricwheelchair.com.my/electric-scooter-rental/).

## Verification

Focused source/parser/audit tests: 73 passed. Full API: **463 passed, three
optional skips** (466 total). Tests use temporary MongoDB and fixture transports,
not a live import or publisher approval. Permission gates make zero HTTP calls;
approved test fixtures preserve package amounts, exclude incompatible durations,
reach inference with completed count unchanged, deduplicate refreshes and retain
administrator deactivation. Full Flutter/AI/build results for the concurrent GPS
fix are recorded in the maps result document after the final checks.

Commit message:

```text
feat(pricing): prepare permission-gated Goritta tent references

- register Sports equipment source without enabling collection
- parse named tent identities and explicit four-day package quotes
- reject maintenance items, unrelated gear and ambiguous prices
- gate diagnostics and collection on recorded publisher permission
- test period compatibility, inference provenance and deactivation
- document remaining book and scooter onboarding blockers
```
