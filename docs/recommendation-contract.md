# Recommendation foundation (v1)

The executable source of truth is
[`contracts.py`](../backend/app/recommendations/contracts.py). These Pydantic v2
models can be used by FastAPI without importing the running app, Trip CRUD,
Supabase, environment loading or DeepSeek. This issue supplies contracts and
evaluation inputs; no ranking, matrix factorization, extraction or itinerary
generation is implemented. `satisfies_constraints` is an output eligibility check,
not a recommender.

## Types and naming

JSON keys use `snake_case`, UUIDs are strings, timestamps are ISO 8601 with an
explicit offset, durations are positive integer minutes, distance is kilometers,
coordinates are decimal degrees, and money is nonnegative PHP `Decimal(12,2)`.
Pydantic serializes decimals as JSON strings, matching the trip contracts; accept
JSON numbers at ingestion but prefer decimal strings to avoid rounding. Scores
are finite JSON numbers in `[0,1]`, higher is better; they are ranking scores,
not calibrated probabilities. Unknown fields and nonfinite numbers are rejected.
Labels are lowercase ASCII tokens (`cafe`, `heritage`, `photography`), up to 50
characters; tag/category lists have at most 30 items. Backend normalization (#50)
must resolve labels against the approved catalog before constructing a request.
These contracts validate token shape, not membership in a future database tag table.

Required means the key must be supplied. Nullable means explicit `null` is accepted;
it does not mean omission is accepted. Every optional key below has a default.

## Inputs

| Model | Required fields | Optional fields and defaults |
| --- | --- | --- |
| `Preferences` | `user_id: UUID`, `preferred_tags: list[token]` (empty allowed), `budget_min`, `budget_max: Money`, `group_type` | `preferred_categories=[]`, `setting=null`, `requires_step_free_access=false`, `max_visit_duration_minutes=null`, `origin=null`, `max_distance_km=null`, `excluded_location_ids=[]` |
| `LocationAttributes` | `id: UUID`, `name: nonempty string`, `category: token`, `vibe_tags: list[token]`, `estimated_cost_min`, `estimated_cost_max: Money or null`, `suitable_group_types: list[group]`, `typical_visit_duration: positive integer or null`, `is_active: boolean` | `coordinates=null`, `setting=null`, `step_free_access=null` |
| `Coordinates` | `latitude: number [-90,90]`, `longitude: number [-180,180]` | None |
| `Interaction` | `id`, `user_id`, `location_id: UUID`, `interaction_type`, `interaction_value: finite Decimal`, `created_at: offset timestamp`, `provenance: synthetic or real` | `rating_value=null` (required non-null for rating events) |
| `RecommendationRequest` | `preferences: Preferences`, `locations: list[LocationAttributes]` | `schema_version="1"`, `interactions=[]`, `limit=10` (integer 1–100) |

Groups are `solo`, `couple`, `family`, `friends`, `group`. Preference setting is
`indoor` or `outdoor`; locations additionally allow `mixed`. Accessibility is
tri-state: true is confirmed, false is explicitly unsuitable, null is unknown.
Location cost bounds may independently be unknown; known bounds must be ordered.
Preference budgets must be ordered. A distance limit requires an origin.

Interaction types match the existing database: `left_swipe`, `right_swipe`, `save`,
`rating`. Ratings use the proposed v1 scale 1–5 inclusive (decimals allowed).
Only rating events may contain a rating value. `interaction_value` is an event
signal, not a recommendation score. Fixtures use -1 for left swipes and +1 for
positive events, with the rating carried separately; production weights and
aggregation of repeated events belong to #51/#52. The database permits broader
rating values today: this contract narrows the module boundary without a migration.
`provenance` is module/fixture metadata, not an existing database column. Andrew's
adapter must label genuine persisted events `real`; never mix synthetic events
into production or silently treat this metadata as persisted.

Requests contain only the target user's events referencing this candidate snapshot;
location IDs and event IDs must be unique. Repeated user/location events with
different IDs remain valid. Cross-user training data belongs to a separate future
training interface, not this inference request. An empty interaction list is a
supported cold start. Empty candidate lists are valid.

## Outputs and policy

`RecommendationResponse` requires `items: list[Recommendation]` and defaults
`schema_version` to `"1"`. Every recommendation requires `location_id: UUID`,
`recommendation_score: float [0,1]`, and a nonblank `recommendation_reason` of
1–500 characters. Reasons should name supported matches or constraints, without
inventing venue facts or claims about similar users. Ties may retain engine order;
the engine must make ties deterministic for reproducible evaluation.

`validate_response(request, response)` revalidates result fields and rejects the
whole result on duplicates, excess results, ascending scores, nonexistent/inactive
IDs, explicit exclusions, any left-swiped place, or incompatible hard constraints.
Hard filters in v1 are group suitability, known upper estimated cost within the
per-person destination `budget_max`, setting, confirmed step-free access when
required, visit-duration ceiling, and straight-line distance ceiling (Haversine,
Earth mean radius 6371.0088 km). Missing facts needed by a hard filter fail closed.
`mixed` does not satisfy an exclusive indoor/outdoor request. Budget minimum is
context for future ranking, never a minimum spend requirement. Tags/categories
are soft ranking preferences. Cost is per person per visit, excludes transit and
lodging, and is not a total itinerary budget. A trip-level budget must be explicitly
allocated before mapping it here; do not copy total-trip PHP into a per-visit cap.

Empty `items` is a successful no-match outcome. Underfilled results are allowed.
This contract deliberately does not define scores or an exact top-N ordering.
The conservative left-swipe rule excludes any left event in this snapshot;
changing to latest-event semantics requires an agreed contract update.

## Andrew's backend integration (#53)

1. Authenticate the caller and derive `user_id` server-side. Resolve validated trip
   or form preferences, normalize approved tags/categories, and allocate budgets.
   The inference interface itself does not need a trip ID or HTTP call.
2. Load a catalog snapshot and this user's matching events through backend data
   access. Map `locations.id`, `category`, `vibe_tags`, costs, duration, groups and
   active state directly; combine database latitude/longitude into `coordinates`
   only when both are known. Omit description/address/hours/images from this model.
   Setting/accessibility have no database columns today: retain null unless a
   separately verified source supplies them. Opening hours and routing belong to
   later itinerary planning. Map user `preferred_tags` and default budgets only
   when no explicit request overrides them; `traveler_type` is not `group_type`.
3. Build `RecommendationRequest.model_validate(payload)` before calling the engine.
   Pass the Pydantic instance through the Python protocol below. No API client,
   provider credentials or running Trip service is passed into the AI module.
4. Parse engine output as `RecommendationResponse`, call `validate_response`, then
   recheck existence/active status and constraints against current database rows
   before storing selected results or invoking the itinerary planner. This second
   check handles records changed since the input snapshot. Do not return raw engine
   output or validation diagnostics to Flutter.
5. Expose a future FastAPI route with `response_model=RecommendationResponse` and
   serialize via `model_dump(mode="json")`. Client input errors should use the
   existing sanitized 422 handling; invalid engine output is an internal service
   failure with a safe error and retry/manual-selection UI, not a client 422.
   No route or new HTTP status contract is introduced by this foundation.

```python
from app.recommendations.contracts import (
    RecommendationRequest, RecommendationResponse, Recommender, validate_response,
)

def request_recommendations(engine: Recommender, payload: dict) -> RecommendationResponse:
    request = RecommendationRequest.model_validate(payload)
    raw = engine.recommend(request)  # synchronous, local inference; implementation is future work
    response = RecommendationResponse.model_validate(raw)
    return validate_response(request, response)
```

The expected engine signature is
`recommend(request: RecommendationRequest) -> RecommendationResponse`.
CPU-heavy inference should be dispatched outside the async event loop by the
future route. A test double can return a fixed validated response; no placeholder
algorithm or fake production endpoint is installed here.

## Fixtures and evaluation

[`backend/fixtures/recommendations`](../backend/fixtures/recommendations) contains
14 locations, six traveler profiles, 16 synthetic events and ten evaluation inputs.
The first ten locations project the existing `supabase/data/locations.json` fields
without inventing missing facts; four separate synthetic variants provide known
costs, indoor/outdoor/accessibility attributes and an inactive candidate.
`manifest.json` lists synthetic IDs and traveler labels. All user/event IDs are
synthetic UUIDv5 values; even source-derived location IDs are fixture IDs, never
live database IDs. No personal data, real interactions or current venue research
is included. Source catalog details remain development snapshots, not current
visitor advice. Synthetic facts must never be seeded into production.

`evaluation_cases.json` embeds complete input requests and expected behaviors for
cafe, heritage, family nature, premium dining, two cold starts (one without tags),
accessibility/setting, distance/duration, empty results and exclusions. Eligible
examples illustrate permissible choices, not mandatory results or exact score
labels. Hard invariants are checked now; relevance statements are future scoring
acceptance targets for #33/#51/#57, not evidence of measured model quality.

Run from `backend` with the project's Python environment:

```powershell
python -m pip install -r requirements-dev.txt
python -m app.recommendations.fixtures
python -m pytest test_recommendation_contracts.py -q
ruff check .
```

The builder uses fixed UUID namespaces, explicit timestamps, source ordering and
no randomness. Rebuilding must reproduce the committed JSON; tests compare it to
the pure builder and validate references, cold starts, round trips, evaluation
inputs, hard-filter eligibility, malformed inputs and unsafe outputs. Existing CI
discovers these tests in the backend offline pytest job. Imports do not load `.env`
or call the network. For independent development:

```python
from app.recommendations.fixtures import load_request
request = load_request("cold_start")
assert request.interactions == []
```

For machine-readable JSON Schema, call
`RecommendationRequest.model_json_schema()` and
`RecommendationResponse.model_json_schema()`; Pydantic emits required/nullable
fields and nested definitions directly from the executable contracts.

PR review, required CI, merge and integrated artifact verification remain release
gates. There is no endpoint/UI to deploy or provider call to verify in this issue.
After merge, confirm these files and the offline checks at the integrated commit;
record any applicable deployment artifact checks without claiming model behavior.
