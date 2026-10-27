# RentHub pricing/recommendation evidence: next test session

27 October clarification: demo tester sessions remain staged evidence. They can
evaluate usability and recommendation behaviour but cannot establish achieved
rental-price accuracy. [The latest follow-up](PRICING_EVIDENCE_FOLLOWUP_RESULT.md)
reports zero independently verified achieved rentals and the current frozen-model
evaluation. Use `--mode deployed` explicitly when evaluating pricing; do not fit
a candidate merely because a session generated more demo bookings.

Prepared 22 October 2026. This is a collection guide, not completed participation
or a claim of improved model accuracy. See [the measured first-round results](PRICING_RECOMMENDATION_EVIDENCE_ROUND1_RESULT.md).

## What you need to do

Arrange a small pilot with **5–10 willing people**, if your supervisor permits it.
This is a practical starting target, not a statistically sufficient sample size.
Several accounts operated by one person do not count as independent participants.
No new training command is needed yet.

Use dedicated test accounts and the existing normal app flows. Do not bypass KYC,
create activity on someone's behalf, ask for their IC/password/OTP, or use actual
payment credentials. Prepared authorized accounts avoid collecting new identity
documents merely for a recommendation study. Keep staged and natural activity on
different accounts. Follow institutional requirements and record consent privately.

Suggested invitation:

> Could you help test my RentHub FYP for about 15 minutes? We will use demo
> accounts and demo payments, not real money. If you agree, I will use your app
> actions and feedback in my evaluation, reported using participant codes and
> aggregate results. You can stop or ask me to exclude your test data.

An invitation is not consent. Leave the blank feedback template empty until
someone agrees and performs the session. Non-consenting records must not be
exported; `--all-staged` is a provenance label, **not** a consent/exclusion filter.

## Session A: natural interests, not prescribed clicks

1. Let the tester choose a realistic rental need, budget and area. Do not tell
   everyone to want the same camera or click a target listing.
2. Before browsing, note whether Home recommendations are useful for that new
   account. Record an empty feed or unavailable result honestly.
3. Ask them to explore **5–10 distinct listings** relevant to their own need.
   Opening details is a view; seeing a card is not. Do not repeatedly refresh a
   single listing to manufacture evidence.
4. They may save items they genuinely find useful; **do not require a fixed number
   of saves**. Our current export has zero retained save signals, but fabricated
   saves would not fix that evidence gap.
5. Return to Home and check refresh, Recently Viewed and the selected area. When
   dates/location are used, note whether the suggestions are available/relevant.
   Do not record exact GPS positions or private addresses in evaluation notes.

## Session B: later feedback/holdout

Use a later session if practical, preserving timestamps and failures. Record the
first **up to five** organic Recommended For You results in the order actually
shown; record fewer if fewer are returned. Do not rerun until attractive results
appear. Keep promoted placements distinct from organic recommendations.

For each result ask:

- Relevance from 1 (not useful) to 5 (very useful), with an optional explanation.
- Does it fit the task/category, budget and selected area?
- Would they consider renting it? Yes/no/unsure, independent of a click or save.

Keep explicit feedback separate from the app's implicit 2/3.5/4/4.5 action weights.
A view does not mean satisfaction. Do not turn these feedback answers into
completed rentals, alter live ratings or automatically retrain from them.

Optionally compare with an equally eligible, non-personalized listing set using
a predeclared ordering and counterbalanced display order. Record the actual
baseline rule and list shown; without that comparison, report only descriptive
feedback, not a causal improvement claim. Never expose excluded/own/blocked items
or private coordinates to manufacture a larger candidate pool.

## Optional booking scenario

If the tester wants to exercise a booking, use the normal agreement → pending
request → demo payment → Owner approval sequence. Decline/cancel paths are useful
tests too. Do not force completion just to inflate historical evidence. All such
scripted bookings remain `demo_seed` in the evaluation export, even if the app
lifecycle reaches `completed`.

## Price-evidence priorities

First-round external references are concentrated in cameras and cars. Start with:

- Smartphones: only two product groups.
- Tools: only one product group.
- Computers, Gaming and Clothing: thin identity/price coverage.
- Other vehicles, Sports equipment and all four Books subcategories: no eligible
  external observations in this round.

Use already-approved sources where suitable. A missing source/permission or an
ambiguous amount is a gap, not permission to guess, scrape unrestricted pages or
enable a blocked source. Existing collection/source-health tools remain the
normal workflow; reviewed CSV is the fallback.

Each observation needs an explicit MYR rental amount, duration/band, compatible
item/package, source link/name and observation time. Preserve excluded charges;
do not compare a body-only camera with a kit or equipment with an inseparable
operator/service package. Sale prices, deposits and headline "from" amounts are
not daily-rental targets. Multiple duration bands are not independent products.

**All 334 current external quotes lack age and condition.** Record these only if
the source/Owner actually supplies them. Never infer them from a model release
year, assign random ages, clone a quote at several ages, or invent discounts.
Unknown stays null. More rows without these fields cannot establish learned
age/condition effects. Permissioned Owner quotes remain asking prices; only
genuine achieved transactions can support achieved-rental claims.

## Export/evaluate afterward

Existing first-round files are private and immutable. Choose a new round2 path.
If **all** current platform activity is yours/consenting dedicated staged accounts:

```powershell
cd C:\Users\weith\FYP\services\api
npm.cmd run export:pricing-data -- --all-staged --output .data/evidence/round2/pricing_observations.json
npm.cmd run export:recommendation-data -- --all-staged --output .data/evidence/round2/recommendation_interactions.json

cd ..\ai
.\.venv\Scripts\python.exe -m app.training.evaluate_pricing `
  --real-export ../api/.data/evidence/round2/pricing_observations.json `
  --report .data/evaluation/pricing-evidence-round2.json
.\.venv\Scripts\python.exe -m app.training.train_recommendation `
  --real-export ../api/.data/evidence/round2/recommendation_interactions.json `
  --evaluate-only --no-synthetic --report .data/evaluation/recommendation-evidence-round2.json
```

The evaluation directory exists in this workspace. Export commands create their
new parent directories and refuse overwrites. They do not alter database history.
`--all-staged` leaves external asking prices external. Do not use it once natural
and staged activity are mixed; use reviewed `--staged-users PRIVATE_JSON` for the
staged subset and resolve exclusions before exporting other participants' data.

Offline model fitting here writes only reports, never deployed weights. Review
results/baselines, provenance, sample sizes and fresh holdout data before any
separate deployment decision. Human feedback supports a small FYP usefulness
study; scripted history cannot validate real commercial performance.

Blank private feedback template:
`services/ai/.data/evaluation/pricing-recommendation-round1/tester_feedback_template.json`.
Keep it, participant-code mappings and completed responses out of Git. It is a
blank collection aid, not an implemented feedback importer or automated study.
