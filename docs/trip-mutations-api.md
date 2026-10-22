# Trip partial update and deletion — issue #24

Scope: `PATCH /api/v1/trips/{trip_id}` and `DELETE /api/v1/trips/{trip_id}`.
Both reuse the [existing controlled demo context](trips-api.md), database client,
and schema. No migration is needed. Authentication integration, itinerary
generation/editing, Flutter work, and the broader database integration suite
remain separate issues.

## API contract

PATCH changes only supplied fields and returns **200** with the saved trip in
the same format as POST/GET. Supported fields are `title`, `start_date`,
`end_date`, `budget_min`, `budget_max`, `transportation_mode`, `group_type`,
and `preferred_tags`. Omitted fields, owner, status, estimated cost, and existing
itinerary items remain unchanged. PATCH does not regenerate/reschedule an
itinerary; that behavior belongs to the itinerary planner.

Example partial body:

```json
{"title": "Updated Bacolod afternoon", "budget_max": "800.00"}
```

- At least one editable field is required; `{}` is rejected with 422.
- Supplied fields use the same trimming, length, calendar-date, decimal, and tag
  rules as POST. Budgets must be finite, nonnegative `numeric(12,2)` values;
  fractional cents are rejected. Money is returned as decimal strings.
- Supplied dates/budgets are merged with their saved counterparts for validation.
  For example, changing only `budget_min` above the saved maximum returns 422.
  Submit both bounds together when moving an entire range.
- `null` clears `transportation_mode` or `group_type`. `[]` clears preferred
  tags. Null is rejected for title, dates, budgets, and preferred tags.
- Unknown/server-owned fields, including `user_id`, `id`, `status`, and
  `estimated_total_cost`, return 422. No write occurs for invalid input.
- Only supplied columns are sent to PostgreSQL. Concurrent edits to the same
  column use the last successful write; there is no version/ETag contract.
  PostgreSQL checks protect final date/budget ranges even if another request
  changes a counterpart after validation. A database check conflict returns 409
  with a safe reload/retry message; the rejected SQL statement changes no rows.

DELETE **permanently deletes** the owner-scoped trip and returns **204 with no
body**. PostgreSQL's existing `itinerary_items.trip_id ON DELETE CASCADE` removes
associated itinerary items atomically with the trip. User profiles, locations,
and unrelated trips/items remain. The application does not delete children in a
separate request. Deleted trips disappear from list and retrieve queries.

For both methods:

| Status | Meaning |
| --- | --- |
| 401 | Missing/incorrect demo bearer token |
| 404 | Missing trip or trip owned by another user; identical `Trip not found.` response |
| 422 | Malformed UUID/body or invalid update; sanitized `detail` array |
| 503 | Demo configuration or database unavailable; no provider/credential details |

Both reads and writes filter by **trip ID and server-selected owner**. An empty
write result returns 404, including deletion between PATCH's read and write.
DELETE of an already deleted trip returns 404. The demo token now grants write
and delete access as well as create/read; keep it private and backend-only.

## 1. Branch and offline checks

The developer confirmed creating `feat/trip-update-delete` from updated `main`.
Run from the repository root in PowerShell, using the existing environment:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -v
.\.venv\Scripts\python.exe -m ruff check backend
.\.venv\Scripts\python.exe -m compileall -q backend/app backend/test_trips.py
git diff --check
```

These tests use mocked HTTP and dummy credentials. They cover mutation contracts,
ownership filters, validation against retained fields, failed writes, and a
stateful full-CRUD sequence. They do not establish hosted persistence/cascades.
The existing backend CI job discovers them without workflow changes.

## 2. Development configuration and startup

Use development **`vnpkyvtbupnquvirzlzp`** first. Privately check `SUPABASE_URL`
and its matching backend key in the root `.env`, plus any process environment
overrides. Do not print secrets. CLI linkage and `DATABASE_URL` select their
targets independently and do not configure these Data API routes.

Reuse the dedicated synthetic demo profile from issue #23, UUID
`23000000-0000-4000-8000-000000000001`, and a private development demo token.
If the profile/demo context is absent, follow the existing guide's development
setup before starting. Do not rotate an existing valid token merely for this
issue, and never reuse the production token for development.

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --reload
```

Open `http://127.0.0.1:8000/docs`, authorize `TripDemoToken` privately, and use
only synthetic verification trips. Record safe response bodies/statuses, never
Swagger Curl/request headers or authorization screenshots.

## 3. Development acceptance checks

1. **Create/read:** POST the existing example body with title
   `Issue 24 development verification`, dates `2026-11-01` through `2026-11-02`,
   budgets `100.00`–`500.50`, walking/solo, and tags `["heritage", "cafe"]`.
   Expect 201. Save its returned UUID. GET list and GET that UUID must return 200.
2. **Partial update:** PATCH only `{"title":"Issue 24 updated verification"}`.
   Expect 200. Compare all other fields with the create response; they must match.
   GET it again to confirm the saved change.
3. **All editable fields:** PATCH the following body. Expect 200 and a matching
   subsequent GET:

   ```json
   {
     "title": "Issue 24 full update",
     "start_date": "2026-11-03",
     "end_date": "2026-11-04",
     "budget_min": "200.00",
     "budget_max": "800.00",
     "transportation_mode": "taxi",
     "group_type": "friends",
     "preferred_tags": ["food", "heritage"]
   }
   ```

4. **Reject invalid edits:** separately PATCH `{"budget_min":"801"}`,
   `{"end_date":"2026-11-02"}`, `{"budget_min":-1}`, `{"title":null}`, `{}`,
   and `{"user_id":"23000000-0000-4000-8000-000000000002"}`. Each must
   return 422. GET the trip after these attempts; all saved details must match
   step 3. Refresh Swagger/reauthorize and restart FastAPI in the same configured
   terminal, then read again to confirm persistence.
5. **Clear optional values:** PATCH
   `{"transportation_mode":null,"group_type":null,"preferred_tags":[]}`.
   Expect 200; all other saved fields must remain intact.
6. **Ownership/missing/auth:** PATCH a valid title and DELETE the issue #23
   other-owner fixture `23000000-0000-4000-8000-000000000004`; expect 404 for
   both. Confirm that fixture still exists in SQL. Repeat both methods with
   unused UUID `24000000-0000-4000-8000-000000000099`; expect 404. Logout from
   Swagger and repeat both methods on the new owned trip; expect 401. Reauthorize.
   Invalid UUIDs must return 422 (if Swagger blocks submission, record that as
   client validation only; backend UUID rejection is checked offline).
7. **Cascade:** before DELETE, use the following SQL in the **development**
   SQL Editor. Replace `YOUR_NEW_TRIP_UUID` with only the UUID from step 1.
   This intentionally inserts one persistent synthetic child to test API deletion.

   ```sql
   insert into public.itinerary_items (trip_id, location_id, day_number, visit_order)
   select t.id, l.id, 1, 1
   from public.trips t
   cross join public.locations l
   where t.id = 'YOUR_NEW_TRIP_UUID'::uuid
     and t.user_id = '23000000-0000-4000-8000-000000000001'::uuid
     and l.name = 'San Sebastian Cathedral';

   select id, trip_id, location_id from public.itinerary_items
   where trip_id = 'YOUR_NEW_TRIP_UUID'::uuid;
   select * from public.trips where id = 'YOUR_NEW_TRIP_UUID'::uuid;
   ```

   Confirm exactly one child exists and record its ID/location ID before deletion.
   Run the insert once on this new verification trip; if it fails, diagnose before
   continuing. DELETE the trip through FastAPI; expect 204 and an empty body.
   GET the trip and repeat DELETE; both must now return 404. GET list must exclude
   it. Rerun the SELECT statements: both must return zero rows. Confirm the recorded
   location and demo user still exist, and the other-owner trip is unchanged.
   These SQL checks establish persistence and actual database cascade behavior;
   a successful mocked test alone does not.

Record actual results in [issue #24 evidence](evidence/trip-mutations-dev.md).
Do not delete or modify the earlier issue #23 verification trips.

## 4. Reviewed deployment and production verification

After development passes, commit only the issue files and open a PR targeting
`main`, linked with `Refs #24` so merge does not close the issue before deployed
verification is recorded. Require passing CI and teammate review before
merge. Backend changes merged to `main` trigger the existing Cloud Run deployment.
Do not close #24 until deployed acceptance and evidence linkage are complete.

Production is **`zjnuqqtbapbpudsjbpif`**. Use the public deployed Swagger page and
the existing **separate production** demo profile/token. No migration or new
hosting setting is required. Coordinate deployed verification with the deployment
owner after development passes; do not repoint the development backend just to
run production checks.

Repeat steps 1–7 with a **new synthetic production verification trip**, keeping
the title prefix `Issue 24 production` and using production SQL Editor for the
child fixture and persistence checks. Provision a separate synthetic other-owner
fixture in production only if none exists; absence alone does not prove owner
isolation. Verify both mutations reject that existing other-owner trip and that
its row remains unchanged. Never reuse development trip UUIDs as production
evidence. Record the PR, CI/deployment links, safe HTTP results, SQL child-before/
after checks, and final evidence link on issue #24.
