# Content-based recommendation baseline (#33)

`content-v1` ranks eligible Bacolod destinations using the #32 contracts and
fixtures. It is synchronous local Python: no database, Trip CRUD API, trained
model, credentials, LLM or network is needed. This is the first working cold-start
baseline and future fallback, not the complete hybrid recommendation system.

## Scoring and filters

| Feature | Base weight | Component score |
| --- | --- | --- |
| Travel tags | 0.60 | Number of distinct requested tags present in destination tags / number of distinct requested tags |
| Category | 0.25 | 1 when the destination category is among requested categories, otherwise 0 |
| Budget headroom | 0.15 | `1 - estimated_cost_max / budget_max`; confirmed free places under a zero ceiling score 1 |

Each used component is in `[0,1]`. The final score is the weighted sum divided
by the sum of used weights. Empty tag/category preferences omit those features;
they do not count as mismatches. A provided preference with no matches scores 0.
With tags but no category, effective weights are 0.8 tags and 0.2 budget. With
neither, budget headroom alone ranks compatible places. Distinct-tag recall avoids
penalizing a destination for additional attributes the user did not request.

Weights are named constants in
[`content_based.py`](../backend/app/recommendations/content_based.py). They are
initial design choices favoring explicit interests, not fitted parameters or
user-validated optimal weights. Standard library arithmetic is sufficient for this
small content baseline; planned matrix libraries remain future hybrid work.

Before scoring, use the existing `satisfies_constraints` boundary: active status,
known upper cost within the per-person/per-visit budget ceiling, group suitability,
explicit exclusions, and any requested setting, accessibility, duration or distance
constraints. Unknown facts required by a hard constraint fail closed. Group is a
hard gate, not a constant score that would inflate every result. Distance is
straight-line, not travel time. Budget minimum does not force spending; upper cost
is conservative and excludes transport/lodging. `estimated_cost_min` remains part
of the contract but does not affect this conservative upper-bound score.

All left-swiped candidates in the supplied snapshot are excluded. Saves, right
swipes and ratings do not alter content scores; this avoids quietly introducing
collaborative or interaction-based scoring. No interaction history is required.

Sort by descending unrounded score, then ascending UUID string for ties. This
makes identical inputs and reordered catalogs reproducible. The request's `limit`
(1–100, default 10) selects top N after filtering. Duplicate candidate IDs are
rejected by the agreed input contract, including model instances mutated after
validation. Outputs are validated again before returning. Inputs are not modified.
Underfilled and empty responses are valid. No relevance threshold is applied:
compatible zero-score candidates can appear after better matches if N permits.
These scores measure configured compatibility, not probabilities of satisfaction.

## Python interface and explanations

Run from `backend`, using the project environment:

```python
from app.recommendations.content_based import ContentBasedRecommender, recommend, score_location
from app.recommendations.fixtures import load_request

request = load_request("cold_start")
request.limit = 3
response = recommend(request)
print(response.model_dump_json(indent=2))

# Also satisfies the existing Recommender protocol for backend dependency injection:
engine = ContentBasedRecommender()
assert engine.recommend(request) == response
```

`recommend(RecommendationRequest) -> RecommendationResponse` preserves schema v1.
Each item has its location UUID, normalized score and bounded deterministic reason
string naming matched tags, category status, budget headroom and suitable group.
Reasons describe verified input facts; they never claim popularity or similar-user
behavior. For structured internal diagnostics,
`score_location(preferences, location)` returns a frozen `ContentExplanation`
with tag/category/budget components, sorted matched tags, category/group match and
final score, or `None` for an incompatible place. This helper does not see
interaction history; use `recommend` to apply left-swipe exclusions. Explanations
remain internal unless a later API contract explicitly exposes them.

Andrew's future adapter follows [the existing integration contract](recommendation-contract.md):
authenticate/normalize inputs, use database IDs (fixture IDs are synthetic),
construct the request, call this engine, validate the response and recheck current
database state before persistence or Flutter delivery. No endpoint is introduced
here. Backend imports remain independent of application startup and `.env`.

## Evaluation and reproduction

```powershell
python -m pytest test_content_based.py -v
python -m pytest -q
ruff check .
python -m app.recommendations.evaluate_content --benchmark
```

To save machine-readable evidence from the repository's `backend` directory:

```powershell
python -m app.recommendations.evaluate_content --benchmark --output ../docs/evidence/content-based-evaluation.json
```

The ten S3-01 scenarios are exercised against actual recommendations, with expected
top choices, constraints, output validation and reproducibility checked. Additional
tests change tags and categories at a fixed budget, test budget boundaries/zero
budgets, feature arithmetic, duplicate tags, missing optional preferences, empty
catalogs, missing location facts, group mismatch, inactive locations, exclusions,
top N, tied scores, catalog order, input mutation, cold starts, positive-event
independence and long explanations. Existing backend CI discovers these tests
automatically; no live provider call or new CI workflow is necessary.

The report's eligible-example coverage is a fixture check, not precision/recall
against independently labeled real-world relevance. Its top-choice expectations
live in the automated tests. Local timings include request snapshot validation,
filtering, scoring, sorting and output validation; they exclude fixture loading,
HTTP/database access and process startup. They are observations, not CI thresholds
or production latency guarantees. See [initial results](evidence/content-based-results.md)
and [machine-readable evidence](evidence/content-based-evaluation.json).

## Future hybrid/fallback use and limitations

#51 can blend normalized content and collaborative scores as
`alpha * collaborative + (1 - alpha) * content` once both are calibrated to a
comparable `[0,1]` scale on a common eligible candidate set. Candidate alignment,
calibration, alpha and sufficient-history thresholds must be evaluated there;
they are not implemented here. Preserve full eligible candidate scores before
hybrid top-N selection rather than combining two separately truncated lists.
`score_location` exposes a per-location content score for that future work.

When no collaborative model/history exists, or its confidence is inadequate,
the future coordinator can use this engine alone (equivalent to alpha zero).
The same hard constraints and output checks must apply to both branches. Any
collaborative failure fallback should be explicit and observable; do not silently
change these weights or bypass constraints.

The fixture catalog has 14 destinations: ten source-derived records and four
explicitly synthetic variants. Nine of the original ten have unknown upper costs
and are excluded by the agreed strict budget policy. Only one original destination
can currently pass that filter. Accessibility/setting coverage is also incomplete.
Improving verified catalog completeness is necessary before judging broad Bacolod
recommendation quality. Fixture values must never be presented as current prices.

No semantic tag matching, diversity optimization, learned weights, real-user
satisfaction evaluation, collaborative filtering, extraction, routing, itinerary
generation or Flutter integration is included. Scores without optional features
use different effective weights, so compare scores primarily within one request;
future hybrid calibration must account for this. Conservative cost filtering can
reduce recall, and cheaper places win otherwise equal matches even for high-budget
travelers. Relevance thresholds and alternative unknown-data policies need later
product/evaluation decisions, not undocumented changes to #32.
