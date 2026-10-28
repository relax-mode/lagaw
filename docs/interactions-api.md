# Swipes, saves and ratings — issue #52

This API persists events in the existing `user_location_interactions` table via
the backend's Supabase Data API connection. It reuses the existing `users` and
`locations` foreign keys, RLS/service-role access model and controlled demo-user
context. No migration, new configuration, ranking/model training or Flutter
controls are introduced. `.env` does not need changing for this feature.

Andrew confirmed on October 28, 2026 that Jayperson and Roel agreed to the
S3-01 semantics below. The executable event type is shared with
[`Interaction`](../backend/app/recommendations/contracts.py), rather than a
second recommendation schema. See the [S3-01 contract](recommendation-contract.md).

## Access and ownership

Use the existing private bearer token and server-selected `TRIP_DEMO_USER_ID`,
as described in [Trip access](trips-api.md#controlled-demo-user-context).
The same `TripDemoToken` Authorize control appears in FastAPI `/docs`.
Missing or incorrect authorization returns 401; disabled demo configuration
returns 503. Every enabled caller acts as the configured synthetic demo profile;
this is shared demo access, not individual user authentication.

The client cannot choose an owner. Writes reject `user_id`, event `id`, timestamp,
signal and provenance. Reads filter by the server owner; individual reads filter
by both owner and event UUID. Supplying a `user_id` query parameter does not
change the owner. Missing and other-owner event IDs both return 404.
The public Flutter demo token remains suitable only for synthetic demo data.

## Write contract

`POST /api/v1/interactions` accepts:

```json
{
  "location_id": "26000000-0000-4000-8000-000000000001",
  "interaction_type": "rating",
  "rating_value": "3.75"
}
```

The sample UUID illustrates the schema; use an existing active location from
the target database. The body forbids unknown fields. `location_id` must be a
UUID and `interaction_type` must exactly match one of the following values.

| Type | Server `interaction_value` | `rating_value` |
| --- | --- | --- |
| `left_swipe` | `"-1"` | Omitted or null |
| `right_swipe` | `"1"` | Omitted or null |
| `save` | `"1"` | Omitted or null |
| `rating` | `"1"` | Required, finite decimal from 1 through 5 inclusive |

Ratings accept JSON numbers or decimal strings; booleans are rejected. Decimal
strings preserve precision. Any fractional rating within the bounds is valid.
The signal is an event encoding; #51 retains responsibility for training weights
and latest-channel aggregation (including its separate save weight).

Each accepted POST appends one new event and returns 201 with the database's ID
and creation timestamp. Repeated swipes, saves and ratings—including identical
requests—create distinct rows. There is no upsert, overwrite or idempotency key.
An uncertain network outcome followed by a retry can therefore create another
event. Clients should avoid automatic write retries without acknowledging this.
No event update/delete or unsave/reversal API is included in #52.

The backend checks existence and active status immediately before insertion.
Missing or inactive locations return 404 without insertion. PostgreSQL enforces
the existing owner/location FKs; deletion between validation and insertion fails
safely with 503. An administrator changing active status concurrently with the
write is not serialized by the existing schema: active status is a pre-write
check, not a database transaction lock. Historical events remain readable after
a destination is retired.

Successful response, using the S3-01 `Interaction` model:

```json
{
  "id": "52000000-0000-4000-8000-000000000001",
  "user_id": "52000000-0000-4000-8000-000000000002",
  "location_id": "26000000-0000-4000-8000-000000000001",
  "interaction_type": "rating",
  "interaction_value": "1",
  "rating_value": "3.75",
  "created_at": "2026-10-28T00:00:00+00:00",
  "provenance": "real"
}
```

Numeric response fields are decimal strings. `provenance: real` is added by the
adapter for database events; it is not stored in a new column. Synthetic offline
fixtures remain separate and must not be imported into production. The isolated
verifier's temporary database fixtures exercise this same adapter and are removed.

## Read and recommendation contracts

| Endpoint | Successful result |
| --- | --- |
| `GET /api/v1/interactions?limit=10&offset=0` | `{"schema_version":"1","items":[Interaction],"limit":10,"offset":0}` |
| `GET /api/v1/interactions/{event_id}` | One `Interaction` |
| `GET /api/v1/interactions/recommendation-input` | `{"schema_version":"1","interactions":[Interaction],"excluded_location_ids":[UUID]}` |

History is ordered by `created_at ASC, id ASC`; limit defaults to 10, range 1–100,
and offset defaults to zero and must be nonnegative. Empty history is successful.
Ties use UUID ordering, matching #51's deterministic latest-channel aggregation.
HTTP paths version all contracts; the collection and handoff also identify v1.
FastAPI `/openapi.json` supplies executable request/response JSON Schemas.

The handoff reads all pages rather than only the first 10/100 events. Any left
swipe excludes that location, even if a later right swipe, save or rating exists.
This conservative policy matches S3-01's output validator and both engines;
latest-channel training behavior does not override inference exclusions.

For #53, call the server-side adapter with the candidate snapshot's IDs:

```python
history = InteractionDatabase(client).recommendation_input(
    server_user_id, {location.id for location in candidates},
)
request = RecommendationRequest(
    preferences=validated_preferences,  # user_id derived from the server context
    locations=candidates,
    interactions=history.interactions,
)
```

The optional candidate filter keeps retired/out-of-snapshot events out of
`RecommendationRequest`, whose references must belong to its catalog. The
returned excluded IDs cover that same projection. The public handoff returns all
owner events; consumers using a smaller catalog must filter accordingly.
No cross-user training feed or recommendation endpoint is added here.

The handoff fails closed above 10,000 owner events and on duplicate/inconsistent
pages; it never returns a truncated exclusion list. Paginated HTTP reads are not
a transaction snapshot under concurrent writes. Explicit history pagination
remains available for larger histories. Rows written outside this API that
violate S3-01 (for example ratings outside 1–5) produce a sanitized 503 rather
than silently modifying or omitting data.

## Error contract

| Status | Meaning |
| --- | --- |
| 401 | Missing/invalid existing demo bearer credential |
| 404 | Active location missing on write, or owned event missing on read |
| 422 | Invalid JSON, ID, type, rating, body field or pagination |
| 503 | Demo context unavailable, database/network/FK/response failure, or unsafe handoff |

Validation errors expose only `loc`, `msg` and `type`, omitting submitted values
and validator context. Database failures return
`{"detail":"Interactions are temporarily unavailable. Please try again later."}`.
Neither database diagnostics nor credentials reach clients. A failed write
response after a committed insert cannot guarantee the insert was rolled back.

## Verification: isolated CI, then development, then deployed acceptance

From the repository root, using the existing virtual environment:

```powershell
.\.venv\Scripts\python.exe -m pytest backend -q -m "not db"
.\.venv\Scripts\python.exe -m ruff check backend
.\.venv\Scripts\python.exe backend/evaluate_week3.py --output backend/test-results/issue52-week3-evaluation.json
git diff --check
```

`test_interactions.py` mocks HTTP only, exercising real API validation and data
access. `test_interaction_verification.py` checks production refusal and cleanup
after partial setup. No real provider credentials or network are required.

The existing Database CI job discovers
`tests/integration/test_interaction_persistence.py` through `pytest -m db`. It
uses that job's migrated disposable PostgreSQL 17 and loopback PostgREST, with
the existing hosted-target refusal fixture. The full API/relationship verifier
shares those services with the other database tests and requires no workflow
change. Its result appears in the existing `trip-integration-results` JUnit
artifact alongside the Trip tests. No hosted data or provider credentials are
supplied to this job.

For actual development Supabase verification, run:

```powershell
.\.venv\Scripts\python.exe backend/verify_interactions.py
```

The app loads its existing private configuration without printing values. The
script refuses every target except development project
`vnpkyvtbupnquvirzlzp`, before making any HTTP request. It refuses production
`zjnuqqtbapbpudsjbpif` and does not rewrite `.env`, CLI linkage or deployment
settings. It generates a private temporary demo token in memory and switches
the controlled owner only inside its own process. No new `.env` value is needed.

The verifier checks all four event types, ratings, repeated submissions, owner
isolation, rejected input without rows, independent database persistence, fresh
application/client reads, both FKs, location-delete restriction, user cascade and
preservation of parents when deleting an interaction. It creates only new UUIDs.
An application/client restart check is not a hosted deployment/redeployment.

Cleanup runs in `finally`, removes only events belonging to this run's generated
owners and exact generated IDs, then removes its newly created users/locations.
It attempts every cleanup after failures and independently verifies absence.
It never resets/truncates tables or removes existing users/catalog locations.
If interrupted or cleanup fails, investigate the fixture IDs printed at startup.
In the development SQL Editor, first select those exact IDs and verify their
`issue52-<UUID>@example.invalid` fixture emails/names. Delete only those owners'
interactions, then their fixture users, then the exact fixture locations; verify
their absence. Never run a broad name-prefix delete or use production for cleanup.

After teammate-reviewed merge and required CI, the existing pipeline deploys
staging against development and then promotes to production automatically.
Check the new routes on staging first using its existing synthetic demo owner
and private staging token. Create a synthetic event against an active location,
GET it by ID/history and verify that exact ID in development PostgreSQL. Check
unauthorized/invalid writes and handoff exclusions, then clean only the exact
test event IDs through the database; the API intentionally exposes no deletion.
Keep the existing user/location rows. Repeat deployed acceptance in production
only after development/staging checks pass, using its separate demo context.
Record the serving revision, statuses, safe IDs and exact cleanup evidence.
Do not use the development-only verifier against production.

Observed results and outstanding release gates: [evidence](evidence/interactions-dev.md).
