# Manual trip-itinerary location associations — issue #26

Scope: add, list and remove manual destination associations. Existing Trip CRUD,
the controlled demo-user context, and the existing PostgreSQL tables/relationships
remain the foundation. Recommendation ranking (#53), generated schedules and
persistence (#54), Flutter integration (#34), and route optimization are separate.

## API contract

All three endpoints require the existing `TripDemoToken` bearer credential.
The server selects the owner; the client cannot submit a user or parent trip ID.
Each operation first retrieves the parent using both its UUID and configured
owner. A missing or other-owner parent returns the same 404.

| Endpoint | Success | Behavior |
| --- | --- | --- |
| POST /api/v1/trips/{trip_id}/items | 201 | Insert an item referencing an existing active location |
| GET /api/v1/trips/{trip_id}/items | 200 | Read PostgreSQL items with nested location details |
| DELETE /api/v1/trips/{trip_id}/items/{item_id} | 204, empty body | Delete only the item under the specified owned trip |

POST body, using the seeded Cathedral UUID:

```json
{
  "location_id": "1a3bca09-5532-5de6-8587-2440c4e5830d",
  "day_number": 1,
  "visit_order": 1
}
```

All fields are required. Day and order must be JSON integers from 1 through
2147483647; booleans, fractions, numeric strings, zero and negatives are rejected.
The day must fit the trip's inclusive dates. Unknown fields, including owner IDs,
item IDs, trip IDs, recommendation scores and arrival times, are rejected.
Invalid UUIDs, bodies and pagination return sanitized 422 details.

An item response contains `id`, `trip_id`, `location_id`, `day_number`,
`visit_order`, and `location`. The nested location uses the same public fields
as `/locations`; it is read through the existing PostgreSQL FK. No arrival
times, routing estimates or recommendation scores are generated or changed.

GET returns `{"items": [...], "limit": 10, "offset": 0}`; limit defaults to 10
(range 1–100), offset defaults to zero (nonnegative). Items are ordered by
day, visit order, then UUID. An empty owned trip returns an empty page.
Follow pagination to retrieve all items. Existing items retain their location
details even if a location is subsequently marked inactive; new additions
require an active location.

The existing unique `(trip_id, day_number, visit_order)` constraint defines
duplicates. Repeating a successful POST returns 409 and leaves one saved item;
a different location at that same position also returns 409. The same location
may be visited at another position/day. Orders need not be contiguous, and
deletion does not renumber other items. No global location uniqueness rule
or migration is introduced. PostgreSQL enforces position conflicts atomically,
including simultaneous insertions.

A missing/inactive location returns 404. Missing, removed, other-trip and
other-owner items cannot be deleted through the requested parent and return 404.
A parent FK changing between validation and insert returns a safe 409; reload
before retrying. Provider/configuration/network/invalid-response failures return
the existing generic Trip 503. Missing credentials return 401; an unconfigured
demo context returns 503. Provider details and submitted secrets are not exposed.

## Implementation

The existing `trips`, `itinerary_items` and `locations` tables and SQLAlchemy
relationship mappings from #22 are reused; they are not recreated or altered.
Like #23/#24, runtime API access uses the existing backend-only Supabase
Data API connection. `TripDatabase` performs the owner check, and the new
`TripItemDatabase` reads/writes the same mapped itinerary/location records.
The unique position, non-null FKs and delete restrictions already exist.
No new database driver, migration or environment setting is required.

## 1. Offline checks

From the repository root, using the existing virtual environment:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -v
.\.venv\Scripts\python.exe -m ruff check backend
git diff --check
```

The backend CI job also discovers these tests with pytest. Offline HTTP tests
use a mock transport and dummy settings, never a hosted database or AI provider.
They cover parent scoping, authentication, request validation, day bounds,
nested responses, pagination, deletion filters, conflicts, invalid provider
responses, sanitized failures, target guards and handled-error CORS headers.

## 2. Explicit development database tests

Development is `vnpkyvtbupnquvirzlzp`; production is
`zjnuqqtbapbpudsjbpif`. Preserve the existing private `.env`.
Use the same development configuration as the existing backend; process
environment overrides still take priority. CLI linkage does not select the
Data API target.

Run:

```powershell
.\.venv\Scripts\python.exe backend/verify_trip_items.py
```

Before any request this verifier requires the exact development Data API URL.
Production and other projects are refused. If refused, stop and share only
the safe failure message; do not repoint the backend to production.

The verifier creates unique synthetic users, trips, active/inactive locations
and items. It runs the real FastAPI routes, authorization and Data API client
against PostgreSQL. It supplies its own temporary process-only demo context;
no running Uvicorn server, pre-existing demo token or `.env` edit is needed.

It checks multiple additions, location details, ordering/pagination, exact
repeats and occupied positions, revisits, invalid associations, real PostgreSQL
FK rejection, owner isolation, cross-trip removal, unauthenticated requests,
preservation of other items/locations, reuse of a removed position, and reads
through a new application/client. The latter proves independently committed
state, not persistence across an actual hosted redeployment.

HTTP writes commit separately. A finally block attempts cleanup for every
registered fixture, even after an assertion/setup failure, and verifies absence.
Deletes use exact generated UUIDs; no table reset, truncate, seed modification
or shared demo-user deletion is permitted. Synthetic owner IDs are printed to
help investigate a failed cleanup. Do not force-stop the process. If interrupted
or cleanup fails, investigate only that run's fixtures before retrying.
Successful output ends with `PASS: Exact synthetic fixtures cleaned and absence verified.`
A failed setup/check/cleanup exits nonzero; it is never counted as a passing skip.

Database CI starts a pinned PostgREST container on loopback alongside its
existing disposable PostgreSQL service after migrations and #22 checks. It runs
`python backend/verify_trip_items.py --ci`, which uses only that fixed loopback
service and does not load `.env` or hosted credentials. Readiness/check failures
fail the required Database job; an unconditional step removes the container.
The workflow change adds issue #26 tests without changing deployment policy.

## 3. Guided development Swagger verification

After the automatic development verifier passes, use the existing development
demo profile/token from #23. Supply missing demo context temporarily through
PowerShell as described in [the Trip API guide](trips-api.md); do not rewrite
`.env` or disclose credentials.

Start the backend in that configured PowerShell process:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --reload
```

Open `http://127.0.0.1:8000/docs`, authorize privately, and:

1. Create a new synthetic trip titled `Issue 26 development verification`,
   dates `2026-11-01` through `2026-11-02`, budgets `0.00`–`500.00`.
   Keep its returned UUID; leave earlier issues' verification trips untouched.
2. GET its items; expect 200 and an empty list.
3. POST the Cathedral body above; expect 201. Save the returned item UUID.
4. Add The Negros Museum, location `61bf94ab-6ec0-5ec3-8451-b575ee06169e`,
   at day 1/order 2. Expect 201 and a different item UUID.
5. GET items; expect 200 and both saved records with matching nested locations.
6. Repeat the first POST; expect 409. GET again: exactly two items remain.
7. Try an unused location UUID (404), malformed UUID/zero order/day 3 (422),
   and a known other-owner trip (404). With authorization removed, all three
   methods return 401. Reauthorize and verify no saved items changed.
8. Refresh Swagger and reauthorize, then GET again. Restart FastAPI in the same
   configured terminal and GET again; saved item IDs/details must match.
9. DELETE only the Cathedral item through its saved parent. Expect 204.
   A repeated DELETE returns 404; GET now contains only the Museum item.
   Refresh/restart and GET again to confirm the removal persists.

Independently inspect development PostgreSQL, replacing only the trip UUID:

```sql
select i.id, i.trip_id, i.location_id, i.day_number, i.visit_order, l.name
from public.itinerary_items i
join public.locations l on l.id = i.location_id
where i.trip_id = 'YOUR_NEW_TRIP_UUID'::uuid
order by i.day_number, i.visit_order, i.id;

select id, name from public.locations
where id in (
  '1a3bca09-5532-5de6-8587-2440c4e5830d'::uuid,
  '61bf94ab-6ec0-5ec3-8451-b575ee06169e'::uuid
);
```

Both catalog locations must remain after item removal. Preserve the remaining
synthetic association until the relevant persistence checks are complete.

## 4. Review, deployment and hosted evidence

Submit only #26 files through a reviewed PR with `Refs #26`. Keep the issue
open until CI, review/merge, deployed checks and evidence are complete.
Keep the existing issue #29 stash separate; its test suite is not required
to run this issue's verifier.

After development passes and the PR merges with green CI, verify the deployed
staging API against development Supabase. Current main automatically deploys
staging for application changes, then promotes production after staging checks
pass; manual workflow dispatch is for production recovery. See the current
[pipeline](../PIPELINE.md) and [staging guide](staging.md).

Staging has a dedicated synthetic demo profile
`16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c` and a separate staging token. Obtain
that token privately from Secret Manager or its authorized holder and use a new staging-owned
verification trip; the old local demo owner's trip will not be visible in this
context. Keep `.env` unchanged and record staging writes in development only.
Record the serving revision before beginning persistence verification. If the
controlled demo context is unavailable, coordinate with its owner rather than
weakening authorization or switching the local backend to production.

Once authorized production deployment is ready, use the deployed API and its
existing separate production demo context. Repeat the manual acceptance checks
with a new synthetic production trip, keeping production and development IDs/
evidence separate. Confirm items and preserved locations in the correct
database project's SQL Editor.

Record a serving revision and the saved items. After a subsequent deployment,
retrieve the same trip and confirm identical saved association IDs/details.
Delete one item, confirm its absence and the retained location, then verify
that absence after a further redeployment. Coordinate these deployments with
the owner; do not redeploy unrelated work solely from this branch.

Record actual results in [issue #26 evidence](evidence/trip-items-dev.md),
including the reviewed PR, passing CI run, deployment/revision links, safe HTTP
results, independent SQL checks and redeployment persistence. Link the evidence
to #26 before closure. Never paste Swagger Curl sections, authorization headers,
tokens, keys, environment dumps or credential-bearing URLs into evidence.
