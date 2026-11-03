# Content-first cold-start evaluation and hybrid roadmap

Evaluated November 1, 2026 on branch `test/content-first-evaluation`, based on
`8049a62` (main after onboarding recommendations PR #131). Related:
[#103](https://github.com/relax-mode/lagaw/issues/103) onboarding recommendations,
[#94](https://github.com/relax-mode/lagaw/issues/94) deployed collaborative serving.
The [approved pitch](pitch.md) remains the product scope: hybrid recommendations
with content-based support for new users. This evaluation changes no serving
behavior, weights, catalog records, infrastructure or model artifacts.

## Evaluation design

The new `cold-start-v1` fixture extends existing evaluation coverage with 16
authored travel scenarios, all with zero interactions and a top-three request.
Each is evaluated against two **separate** catalogs:

1. **Source catalog:** the current committed `supabase/data/locations.json`, with
   unknown costs/access/setting preserved. The existing fixture converter assigns
   synthetic IDs; only its ten source-derived rows are used, not appended fictional
   variants. These are source records, not newly verified prices or a live ranking
   snapshot. Canonical source and fixture SHA-256 hashes are stored in the report.
2. **Controlled catalog:** eight explicitly fictional venues with authored costs,
   groups and constraints, including unknown-cost and inactive controls. These
   exercise discrimination and filters without fabricating facts about Bacolod
   destinations. They never enter either hosted database or the source catalog.

Scenarios cover solo budget cafes, couple heritage/photography, family nature,
friends cafes, modest/high-budget food, combined food/relaxing interests, confirmed
free photography, empty interests, very low budgets, step-free requirements,
indoor preferences, short visits, free indoor visits, nearby photography, and an
empty catalog. A student persona uses the supported `solo` group; no unsupported
`students` enum is invented. Budgets are explicit PHP per person per venue visit,
excluding transport and lodging; they are not silently allocated profile defaults.

The fixture marks scenarios `onboarding_compatible` or
`engine_constraint_diagnostic`. The latter exercise existing optional engine
accessibility, setting, duration and distance fields; these options are **not**
new fields in #103's HTTP request. Pace/travel style is not scored.

Every case has a manually authored expected top name or expected empty result.
Expectations check configured behavior, not independently judged traveler relevance.
The runner verifies eligibility, unique/bounded output, repeated-call and reversed
catalog determinism, and exact parity with `HybridRecommender()` **without a model**.
It exits nonzero on a failed expectation. Existing tests also validate score bounds
and ordering through the shared response contract.

## Reproduction

Activate the repository virtual environment with declared development dependencies
installed. From the repository root:

```powershell
Set-Location backend
python -m app.recommendations.cold_start_fixtures
python -m app.recommendations.evaluate_cold_start --output ../docs/evidence/cold-start-evaluation.json
python -m pytest -q test_cold_start_evaluation.py test_content_based.py test_hybrid_recommendations.py test_onboarding_recommendations.py
python -m ruff check .
```

The first command deterministically regenerates only
`backend/fixtures/recommendations/cold_start_cases.json`; it leaves older fixtures
and evidence intact. The second uses that fixture and committed source data,
without environment loading, credentials, network, provider calls or training.
It writes timing-free JSON so the saved report can be reproduced exactly.
Tests compare regenerated fixtures/report to their committed evidence and include
a deliberately wrong expected ranking to verify the command fails on regressions.

Existing content and trained-synthetic hybrid comparisons remain available:

```powershell
python -m app.recommendations.evaluate_content
python -m app.recommendations.evaluate_hybrid
```

The second command is **not required for the new cold-start evaluation**; it runs
the old synthetic training/held-out experiment. See its
[existing results and limitations](evidence/hybrid-results.md). This task does not
retrain, deploy or modify #94's artifact.

## Results

Full deterministic evidence: [cold-start-evaluation.json](evidence/cold-start-evaluation.json).

| Measure | Committed source catalog | Fictional controls |
| --- | ---: | ---: |
| Scenarios | 16 | 16 |
| Authored behavior expectations/checks passed | 16 | 16 |
| Empty results | 7 | 3 |
| Returned slots / requested slots | 9 / 48 (18.75%) | 35 / 48 (72.92%) |
| Nonempty cases with requested tags | 8 | 12 |
| Top result shares at least one requested tag | 2 / 8 | 11 / 12 |
| Distinct top destinations | 1 | 6 |
| No-model hybrid parity | All cases | All cases |

The museum is the only source destination returned, in nine scenarios. For a cafe
request, cafe-tagged places exist but their unknown costs make them ineligible; the
museum may still appear because there is no minimum relevance threshold. It is a
valid budget/group result with **no matching interest**, not a successful cafe
recommendation. Seven empty cases include the explicit empty-catalog scenario;
do not report the empty count as a population-wide failure rate.

The controlled low-budget cafe case similarly returns a free park when cafes cannot
fit the ceiling. The food-only high-budget case still prefers the cheaper matching
food stop. Adding `relaxing` changes its top choice to premium dining. These expose
the configured budget bias and preference sensitivity rather than concealing them.

Fill is returned slots divided by all requested slots. Tag overlap is a diagnostic
proxy; neither it nor authored expectation pass rates are precision, recall, user
satisfaction or statistically validated quality. Empty/no-tag cases have null tag
diagnostics rather than artificial perfect scores. Eligibility reason counts can
overlap and do not enumerate every optional constraint.

## Current catalog coverage

The committed ten-record source contains ten tagged records, ten positive visit
durations, six coordinate pairs, two nonempty hour schedules, and **one known upper
cost**. Nine records cannot pass a finite budget ceiling under the approved strict
cost policy. Unknown setting/accessibility also prevents restrictive requests.

Separately, existing public GET-only audits were run against both staging
(development-backed) and production on November 1. The recorded timestamps are
07:08:34 UTC and 07:08:39 UTC (15:08:34 and 15:08:39 Asia/Manila). Both returned:

| Active destinations | Coordinate pairs | Nonempty hours | Both cost bounds | Field-complete records |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 6 | 2 | 1 | 1 |

Evidence: [dated live coverage](evidence/cold-start-live-coverage-2026-11-01.json).
These aggregates match source coverage counts but do not prove identical rows,
fresh prices, verified hours, valid image rights or feasible generated itineraries.
The offline rankings use committed data, not the live endpoints. No inactive/private
records or authenticated serving were inspected. Source research has already
[recorded conflicts requiring review](destination-enrichment-s4-06.md); this task
does not resolve them by inventing values.

Refresh live coverage separately from offline evaluation, from repository root:

```powershell
python scripts/destination_coverage_audit.py --environment development
python scripts/destination_coverage_audit.py --environment production
```

Live results and timestamps may change. Preserve the dated evidence; record new
observations separately. A live failure must be reported as unmeasured, not replaced
with the older counts.

## Content-first / hybrid roadmap decision

**Use content-first ranking for cold-start users.** It works without interaction
support or an artifact, respects explicit constraints, and is the intended path
for #103. The largest measured limitation is verified catalog coverage. Prioritize
reviewed cost/access/hours/location enrichment before treating scoring changes as
a solution to empty or irrelevant results. Preserve strict unknown-data handling.

**Keep the hybrid architecture and #94 serving work separate.** No-model parity
only proves fallback behavior. Existing synthetic held-out results (content
Recall@3 0.75 versus hybrid 1.00) and #94 seeded serving checks demonstrate behavior
under constructed inputs and delivery mechanics; they do **not** establish organic
traveler quality or justify making collaborative scores influential for a new user.
This is not a decision to remove the approved matrix-factorization feature or to
change currently deployed serving configuration.

Before choosing hybrid behavior on organic usage, evaluate consented real
interactions with chronological user/location-pair holdouts, comparable eligible
catalogs, explicit cold/sparse/warm cohorts, leakage checks, and content versus
hybrid ranking on the same cases. Report support, coverage, calibration and
uncertainty, with an independent relevance assessment. Keep content fallback for
unseen or insufficiently supported users/places. Retraining and deployment remain
separate #94/owner work, not changes in this issue.

Product decisions still needed: whether to suppress nonmatching places via a
relevance threshold, how to present partial/empty results, and how to handle a
verified expanded catalog. Do not silently change those policies to improve an
evaluation table. Fixture budgets are authored examples, not researched spending
statistics, and controlled costs/coordinates are never current venue claims.

## Delivery evidence

Final focused verification: **42 new evaluation tests passed**; the combined new
evaluation, existing content, hybrid and onboarding endpoint tests returned
**131 passed in 2.45 seconds**, and backend Ruff passed. These cover all 32 scenario/catalog combinations, exact
reproduction, catalog-order invariance, source coverage limitations, preference
sensitivity, empty source behavior, malformed fixture rejection and nonzero failure
exit. Existing pytest discovery includes the new tests without CI changes.

No collaborative training/deployment, profile/API infrastructure, provider calls,
catalog writes or Flutter changes were made. No organic quality result is claimed.
Teammate review, publication/CI, merge and issue linkage remain delivery follow-ups;
the local report and public coverage audit do not complete those review gates.
