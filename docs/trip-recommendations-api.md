# Saved-trip recommendations — issue #53

> **Authentication update (#79):** [Verified Supabase ownership and the #80 handoff](authentication.md) supersede the demo authentication setup in this guide. Demo fixtures now require explicit non-production `TRIP_AUTH_MODE=demo`; normal access uses Supabase access tokens. API payloads are unchanged.

`POST /api/v1/trips/{trip_id}/recommendations` ranks actual active database
locations for an owner-scoped saved trip. The backend loads the trip, complete
candidate catalog and this owner's persisted interactions. It calls the unchanged
[S3-01](recommendation-contract.md) Python interface using the
[content baseline](content-based-recommender.md) and
[hybrid engine](hybrid-recommender.md). DeepSeek is never involved in this route.

This is a read-only operation despite using POST for structured constraints.
It never creates recommendations in storage, alters a trip or its itinerary,
trains a model, or schedules visits. Automatic persistence/scheduling belongs to
#54; Flutter integration belongs to #56. No database migration is required.

## Access and request

Use the existing `TripDemoToken` bearer authorization and server-selected owner
described in [Trip access](trips-api.md#controlled-demo-user-context).
Every enabled caller shares that synthetic demo owner; this is not individual
login. The request cannot override `user_id`, saved tags, budgets or group type.
Missing and other-owner trips return the same 404. Supplying `user_id` in the
query string does not select an owner.

```json
{
  "party_size": 2,
  "planned_visits": 3,
  "limit": 10
}
```

`party_size` (1–100) and `planned_visits` (1–1000) are required integer counts.
Visits means the total number of planned destination visits over the entire
saved trip, not visits per day or the number of candidate suggestions requested.
`limit` defaults to 10, range 1–100. Booleans are rejected for these counts.

Saved Trip CRUD budgets are **total trip PHP**. Allocate each saved bound using:

```text
per-person/per-visit PHP = floor_to_centavos(saved trip PHP / party_size / planned_visits)
```

For saved bounds 100.01–600.01, party size 2 and three planned visits, the response
bounds are 16.66–100.00. This explicit equal allocation is a recommendation ceiling,
not an itinerary cost guarantee. Counts cannot be inferred from a group label,
trip dates or `limit`. The current schema has no lodging/transit reservation;
this operation allocates the entered total to destination visits only. The caller
must account for those other costs when choosing the saved budget/counts.
Budget minimum is context, never a required minimum spend. Unknown upper venue
cost fails closed; an upper cost above the allocated maximum is excluded.

The saved group must be `solo`, `couple`, `family`, `friends` or `group`.
Saved tags must use the approved vocabulary (`cafe`, `photography`, `relaxing`,
`heritage`, `food`, `nature`); they are deduplicated and sorted. Trip CRUD permits
broader labels, so legacy unsupported tags or a missing/unsupported group produce
422 without changing that trip. Correct the manual form using existing Trip CRUD.
An empty saved tag list is valid. No user-profile defaults replace explicit saved
preferences, including empty tags or zero budgets.

Optional fields:

| Field | Contract |
| --- | --- |
| `preferred_categories` | Up to 30 canonical category tokens present in the active candidate catalog; default `[]`; soft ranking preferences |
| `excluded_location_ids` | Up to 100 UUIDs; default `[]`; exclusions need not still exist |
| `setting` | `indoor`, `outdoor` or null; default null |
| `requires_step_free_access` | Boolean, default false |
| `max_visit_duration_minutes` | Positive integer per destination or null |
| `origin` | `{ "latitude": 10.67, "longitude": 122.95 }` or null |
| `max_distance_km` | Positive finite kilometers or null; requires an explicit origin |

Coordinates must be finite and within latitude ±90 and longitude ±180. Unknown
body fields are rejected. There is no free-text prompt or preference extraction
in this request. A successful manual trip remains recommendable when DeepSeek is
missing, unavailable or failing.

## Eligibility and unavailable facts

The backend projects database IDs, costs, groups, category/tags, active state,
duration and coordinates into S3-01. Both latitude and longitude are required to
construct coordinates. Inactive, explicitly excluded and any-left-swiped places
are removed. Later saves/right swipes/ratings do not reverse an earlier rejection.
Only this owner's history enters inference, projected onto the candidate IDs,
using [the #52 adapter](interactions-api.md). Persisted history is marked `real`;
offline synthetic fixtures are never loaded into this request.

Group, upper cost, setting, confirmed accessibility, duration and distance are hard
constraints. Missing facts needed by a constraint fail closed. The locations table
has **no setting or step-free-access columns**: both remain null. Therefore an
exclusive setting request or required step-free access currently yields a valid
empty result, rather than claiming an unverified property. No facts are inferred
from venue names, tags or descriptions.

Distance uses S3-01's Haversine straight-line distance from the supplied origin,
Earth mean radius 6371.0088 km. It is not road distance, walking distance, travel
time or an itinerary route; transportation mode does not change this calculation.
Opening hours and scheduling are not eligibility guarantees in #53.

## Backend output processing and response

The adapter validates the complete input before calling the local engine with a
copy. It parses output as `RecommendationResponse`, rejecting invalid UUIDs,
nonfinite/out-of-range scores, missing/blank/oversized reasons, unknown schema
versions and unexpected fields with a safe 503. Output exceeding `limit` or
ascending scores also fails. Validly shaped duplicate IDs (first occurrence kept),
unknown/inactive/rejected/incompatible candidates are removed, then S3-01's
`validate_response` checks the cleaned response. Malformed score rows cause a
service failure, not a misleading empty success.

Before delivery, it rereads selected active locations and owner history. Deleted,
retired, newly rejected or edited venues are removed without refilling; edits
invalidate the old score/reason even if the updated venue would remain eligible.
The response contains the verified database location object, never model-authored
location details. It also rereads the owned trip: deletion/ownership loss returns
404; any edit during computation returns 409. Separate PostgREST reads are not a
transaction snapshot; changes after the final read cannot be serialized by this
existing schema.

The HTTP wrapper adds location details, trip and allocation metadata around the
unchanged internal S3-01 recommendation fields. Example fragment (use actual
returned UUIDs/details rather than these illustrative values):

```json
{
  "schema_version": "1",
  "trip_id": "53000000-0000-4000-8000-000000000001",
  "budget": {
    "scope": "per_person_per_visit",
    "party_size": 2,
    "planned_visits": 3,
    "budget_min": "16.66",
    "budget_max": "100.00"
  },
  "items": [],
  "empty_reason": "no_compatible_locations"
}
```

Each nonempty item has `location_id`, `recommendation_score` (finite number in
`[0,1]`), `recommendation_reason` (1–500 nonblank characters), and `location`
(the full existing `/locations` object, including matching `id`). The list is
ranked in descending score order; scores are not probabilities. Nonempty results
set `empty_reason` to null. Underfilled and empty results are successful 200s.
The executable HTTP schema is available in FastAPI `/docs` and `/openapi.json`.

## Model fallback and errors

No artifact/configuration is needed for baseline recommendations. The existing
pitch's optional `MODEL_FILE_PATH` can name a team-controlled real-provenance JSON
artifact already accessible inside the backend process. It loads once per process
on first authorized inference; restart the service after changing the artifact or
path. Client requests cannot select it. Training/retraining and artifact delivery
are separate AI/DevOps work; the current container only copies `app/`, so a local
`backend/model_artifacts/` file is not automatically deployed.

An absent, unreadable, corrupt, unsupported-version or synthetic-provenance artifact
uses the exact content baseline. A loaded model blends supported candidates 60%
content / 40% collaborative; unseen users/items and insufficient history use the
existing per-candidate content fallback and explanations. No request-time training
or cross-user training feed is added. A failing engine or malformed output returns
503 rather than silently treating invalid output as trustworthy fallback data.

| Status | Meaning |
| --- | --- |
| 200 | Ranked recommendations, or a valid empty result |
| 401 | Existing demo bearer credential missing/invalid |
| 404 | Trip missing or inaccessible, including a final ownership recheck |
| 409 | Saved trip changed during inference; reload and retry |
| 422 | Invalid options or unsupported saved preferences/category |
| 503 | Disabled demo context, database failure, unsafe model output or engine failure |

Model/database failure detail is `Recommendations are temporarily unavailable.
Please try again later.` Validation errors use the existing sanitized Trip handler
(`loc`, `msg`, `type`, no submitted values/context). No backend diagnostics or
artifact contents reach Flutter. The endpoint issues no writes, including on errors.

Catalog/history readers page through all rows and fail closed on inconsistent or
duplicate pages or more than 10,000 candidates/owner events. They never silently
truncate exclusions to an initial database page. CPU inference and database I/O
run in FastAPI's synchronous worker thread, outside the async event loop.

## Verification and release

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend -q -m "not db"
.\.venv\Scripts\python.exe -m ruff check backend
.\.venv\Scripts\python.exe backend/evaluate_week3.py --output backend/test-results/issue53-week3-evaluation.json
.\.venv\Scripts\python.exe backend/compare_evaluation.py docs/evidence/week3-evaluation.json backend/test-results/issue53-week3-evaluation.json
.\.venv\Scripts\python.exe backend/verify_trip_recommendations.py
git diff --check
```

The last Python command loads existing private app configuration and refuses every
hosted target except development `vnpkyvtbupnquvirzlzp` before HTTP. Production
`zjnuqqtbapbpudsjbpif` is refused. It never rewrites `.env`, Supabase CLI linkage
or credentials; its synthetic demo owner/token exist only inside its process.
The same verifier runs under the existing disposable PostgreSQL/PostgREST CI
fixture via `tests/integration/test_recommendation_persistence.py`, without hosted
credentials. Existing Backend and Database jobs discover all new tests; no workflow
change is needed.

Verification checks real saved preferences/catalog, cold start without DeepSeek,
persisted owner rejection/isolation, auth, restrictive filters, malformed/failing
models and exact preservation of an existing trip/itinerary item. It creates new
UUID fixtures, registers cleanup before writes, attempts every cleanup stage in
`finally`, and independently verifies absence. Investigate the printed exact IDs
if interrupted; never broadly delete by name/prefix or reset a database.

After required CI and teammate review, merge through the normal pipeline. It
deploys staging against development before automatic production promotion. Verify
the new endpoint in staging first with its private existing demo credential and a
saved synthetic trip, then verify production with its separate demo context.
Capture revision/commit, request counts/constraints, safe response fields/statuses,
ranked real IDs, a restrictive empty result, 401/404/422 behavior and unchanged
trip/itinerary before/after. Existing smoke checks do not prove this new endpoint's
authenticated acceptance. Do not claim deployment based on local TestClient runs.

Observed checks and outstanding release gates: [#53 evidence](evidence/trip-recommendations.md).
