# Trip create, list, and retrieve API — issue #23

> **Authentication update (#79):** [Verified Supabase ownership and the #80 handoff](authentication.md) supersede the demo authentication setup in this guide. Demo fixtures now require explicit non-production `TRIP_AUTH_MODE=demo`; normal access uses Supabase access tokens. API payloads are unchanged.

Scope: `POST /api/v1/trips`, `GET /api/v1/trips`, and
`GET /api/v1/trips/{trip_id}`. Update/delete, authentication integration,
itinerary generation, Flutter integration, and expanded CRUD/integration testing
belong to their separate issues.

Issue #24 adds PATCH and DELETE using the same demo context; see the
[update/delete guide](trip-mutations-api.md) for their contracts and verification.

FastAPI uses the existing server-only Supabase Data API connection to read/write
PostgreSQL, just as `/locations` does. It does not use in-memory storage, the
seed JSON, or SQLAlchemy table creation. The existing migrations already provide
the trip columns, defaults, constraints, and owner FK; no migration is needed.

## Controlled demo-user context

This issue explicitly permits a controlled demo user instead of implementing
authentication. Configure both settings in the backend process environment or
the private root `.env`:

- `TRIP_DEMO_USER_ID`: UUID of a dedicated existing `public.users` demo profile
  in the backend's target Supabase project.
- `TRIP_DEMO_TOKEN`: random, private ASCII bearer token of at least 32 characters,
  with no whitespace. Use different tokens for development and production.

Missing/invalid settings disable all trip routes with 503. All enabled
routes require `Authorization: Bearer <demo token>`; missing/incorrect credentials
return 401 with `WWW-Authenticate: Bearer`. `/docs` exposes an **Authorize** control
for `TripDemoToken`. Paste only the token into that control.

Every accepted caller acts as the **same dedicated demo user**. This is a shared
demo context, not per-person login. Use synthetic trip data only; possession of
the token grants full CRUD access to that demo user's trips, including permanent
deletion through issue #24. Do not configure it to an actual user's profile.
The current deployed Flutter Web build compiles the production token through
`--dart-define=TRIP_DEMO_TOKEN` from the `TRIP_DEMO_TOKEN` GitHub Actions secret,
so anyone can read it from the public bundle. Treat that token as exposed, keep
it scoped to the synthetic demo profile, and replace this build-time embedding
with authenticated identity or a server-side proxy before any real-user
deployment.

The owner is always supplied by the server. POST rejects `user_id`, `id`,
`status`, and other undeclared fields. Listing filters by the configured owner;
retrieval filters by **both** owner and trip UUID. Missing and other-owner trips
both return 404 without disclosing another user's data.

## Request and response contract

POST JSON example:

```json
{
  "title": "Bacolod afternoon",
  "start_date": "2026-11-01",
  "end_date": "2026-11-01",
  "budget_min": "100.00",
  "budget_max": "500.50",
  "transportation_mode": "walking",
  "group_type": "solo",
  "preferred_tags": ["heritage", "cafe"]
}
```

- Required: nonblank title (up to 200 characters), real `YYYY-MM-DD` dates, and
  both budgets. Same-day trips and zero budgets are valid.
- End date must be on/after start date. Budgets must be finite, nonnegative,
  ordered, and fit PostgreSQL `numeric(12,2)` without rounding: at most ten
  integer digits and two decimal places. Numeric JSON and decimal strings work.
- Transportation/group labels are optional (default null); when supplied they
  must be nonblank strings up to 50 characters. Preferred tags default to `[]`,
  with at most 30 nonblank strings of up to 50 characters each. Labels and title
  are trimmed. No enum/tag registry has been invented for this issue.
- POST returns 201 and the saved trip object, including database UUID, server
  owner UUID, `status: "draft"`, and `estimated_total_cost: null`.
- GET by UUID returns 200 and that same object. Monetary response values are
  decimal **strings**, preserving exact amounts; unknown estimated cost is null.
- GET list returns `{"items": [...], "limit": 10, "offset": 0}`. `limit` defaults
  to 10 (range 1–100); `offset` defaults to 0 (nonnegative). Ordering is ascending
  `start_date`, then UUID. There is no creation timestamp in the existing schema.
  An empty page returns 200 with `items: []`.
- Invalid input, unknown body fields, malformed JSON, invalid UUIDs, and invalid
  pagination return 422 with a `detail` array of `loc`, `msg`, and `type`.
  Submitted values and validator context are omitted from those errors.
- Database configuration/connectivity/response failures return 503 with
  `{"detail": "Trips are temporarily unavailable. Please try again later."}`.
  Provider details and credentials are not returned. A missing demo profile also
  causes POST to fail safely because PostgreSQL rejects the owner FK.

## Step 1: branch and offline checks

From PowerShell in the repository root, create the branch once:

```powershell
git switch -c feat/trip-create-list-retrieve
```

Use the existing virtual environment. If dependencies need installing:

```powershell
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\.venv\Scripts\python.exe -m pip install ruff
```

Then run:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -v
.\.venv\Scripts\python.exe -m ruff check backend
.\.venv\Scripts\python.exe -m compileall -q backend/app
git diff --check
```

`backend/test_trips.py` is discovered by the existing backend CI job. Its HTTP
transport is mocked and environment settings are dummy values; it makes no live
Supabase/LLM requests. These checks verify the API contract and owner filters;
they do not establish hosted PostgreSQL persistence. No CI workflow was changed.

## Step 2: development Supabase only

Use **development/test `vnpkyvtbupnquvirzlzp`**, not production
`zjnuqqtbapbpudsjbpif`. Privately confirm the root `.env` has that development
`SUPABASE_URL` and its matching backend key. Do not print or share the key.
Process environment variables override `.env`. CLI linkage and `DATABASE_URL`
do not select the database used by these endpoints.

In the **development project's SQL Editor**, create two synthetic profiles and
one other-owner fixture. These are intentional persistent development fixtures,
not a migration and not production setup. Run the SQL only after checking the
project ID in the dashboard:

```sql
insert into public.users (id, name, email)
values
  ('23000000-0000-4000-8000-000000000001', 'Trip API Demo', 'trip-api-demo@example.invalid'),
  ('23000000-0000-4000-8000-000000000002', 'Other Demo', 'trip-api-other@example.invalid')
on conflict (id) do nothing;

insert into public.trips
  (id, user_id, title, start_date, end_date, budget_min, budget_max)
values
  ('23000000-0000-4000-8000-000000000004',
   '23000000-0000-4000-8000-000000000002',
   'Other user fixture', '2026-11-01', '2026-11-01', 0, 100)
on conflict (id) do nothing;
```

In the PowerShell terminal that will run FastAPI, set the demo context and
generate a token without printing it. Copy it privately to the clipboard for
Swagger's Authorize control:

```powershell
$env:TRIP_DEMO_USER_ID = '23000000-0000-4000-8000-000000000001'
$tripDemoBytes = New-Object byte[] 32
$tripDemoRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$tripDemoRng.GetBytes($tripDemoBytes)
$tripDemoRng.Dispose()
$env:TRIP_DEMO_TOKEN = [Convert]::ToBase64String($tripDemoBytes)
Set-Clipboard -Value $env:TRIP_DEMO_TOKEN
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --reload
```

Open `http://127.0.0.1:8000/docs`. Authorize `TripDemoToken` using the clipboard;
never paste this token into chat. Clear the clipboard after authorization.
The token settings above last for this PowerShell process; restarting the backend
in that same terminal preserves them. A new terminal needs its own settings.

## Step 3: verify in Swagger and PostgreSQL

1. POST the example body. Expect **201**. Save the returned trip `id` and details.
2. GET the list. Expect **200** and your saved trip. The other-owner fixture
   `23000000-0000-4000-8000-000000000004` must be absent.
3. GET your saved ID. Expect **200** and matching values.
4. GET the other-owner fixture ID. Expect **404**. GET an unused UUID such as
   `23000000-0000-4000-8000-000000000099`; expect the same **404** response.
5. POST with the end date earlier than the start, a negative budget, reversed
   budgets, or a missing title. Expect **422** for each. Adding `user_id` must
   also return **422**. Verify no additional trip rows were created.
6. Remove Swagger authorization and repeat GET. Expect **401**. Reauthorize.
7. Refresh Swagger and authorize again if needed. GET the saved ID again.
   Stop FastAPI with Ctrl+C, restart it in the same terminal, then GET again.
   Both reads must return the same saved details.

Privately verify the database row in the development SQL Editor:

```sql
select id, user_id, title, start_date, end_date, budget_min, budget_max,
       transportation_mode, group_type, preferred_tags, status, estimated_total_cost
from public.trips
where user_id = '23000000-0000-4000-8000-000000000001'
order by start_date, id;
```

Record dates, safe response excerpts, IDs, and outcomes in
[issue #23 evidence](evidence/trip-api-dev.md). Do not include request headers,
Authorize screenshots, keys, environment dumps, or terminal token values.

## Step 4: reviewed PR and deployed verification

After development checks pass, review the diff, commit only the issue #23 files,
push the feature branch, and open a PR linked to issue #23. Wait for CI and a
teammate's review before merging to `main`.

Coordinate production demo-profile and backend configuration with the deployment
owner after development verification. Production needs its own synthetic profile,
`TRIP_DEMO_USER_ID`, and private `TRIP_DEMO_TOKEN` in Cloud Run's Secret Manager
settings. The deployed Flutter Web build also receives the same token at build
time from the `TRIP_DEMO_TOKEN` GitHub Actions secret; CI passes it with
`--dart-define` and the Pages deploy gate skips when the secret is missing.
Because that token is readable in the public bundle, rotate it if abused and
replace this with authenticated identity or a server-side proxy before real-user
use. Existing `/locations` behavior is unaffected.

After reviewed merge and deployment, repeat create/list/retrieve, ownership,
validation, and unauthorized-request checks against the deployed API. Read the
same saved trip after a subsequent deployment to establish persistence across
redeployments; a local restart alone does not prove that criterion. Record the
merged PR, successful CI/deployment runs, and safe deployed verification results
in the evidence file and link them to issue #23. Keep the issue open until its
Definition of Done is satisfied.
