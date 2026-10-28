# Constraint-aware itinerary generation — issue #54

`POST /api/v1/trips/{trip_id}/generate-itinerary` schedules validated #53
recommendations and saves them through the existing `trips → itinerary_items →
locations` relationship. It uses the existing server-selected demo owner and
bearer authorization. Missing and other-owner trips both return 404. This shares
the controlled demo context's limitations; it does not introduce individual login.

**Frontend handoff:** this is the concrete proposed contract for Roel's review.
Andrew has not reported agreement with Roel; that coordination checkbox remains
open. No Flutter changes are included. Existing #53 canonical tag/group validation
still applies. Flutter currently offers some additional tags and `students` as a
group; those cannot be passed to recommendation/generation as approved preferences.
That existing mismatch is flagged here for the handoff, not expanded into #54 work.

## Request and response

```json
{
  "recommendations": {
    "party_size": 2,
    "planned_visits": 2,
    "limit": 10
  },
  "duration": "morning",
  "pace": "moderate",
  "replace_existing": false
}
```

`recommendations` is the exact [#53 options](trip-recommendations-api.md), including
optional origin, exclusions and accessibility/distance/duration constraints.
`planned_visits` is the **required total visit count across all trip days**;
generation requires `planned_visits <= limit <= 100`. The candidate limit defaults
to 10. Party size cannot be inferred from the saved group label. Saved dates,
budgets, transport, group and tags come from the owned database trip. Unknown
request fields, owner IDs and model-authored schedules are rejected.

Generation accepts trips of 1–31 inclusive calendar days. `duration` defaults to
`full_day`, `pace` to `moderate`. Both use the existing extraction vocabulary:

| Duration | Local planning window on each trip date |
| --- | --- |
| `morning` | 09:00–12:00 |
| `afternoon` | 13:00–18:00 |
| `evening` | 18:00–22:00 |
| `full_day`, `unspecified` | 09:00–18:00 |

| Pace | Visit duration | Break after a visit, before the next journey |
| --- | --- | --- |
| `slow` | ceil(typical duration × 1.5) minutes | 30 minutes |
| `moderate`, `unspecified` | typical duration | 15 minutes |
| `fast` | typical duration, never shortened | 0 minutes |

An explicit maximum visit duration also bounds the pace-adjusted duration. Breaks
are needed only between visits; the final visit need not reserve an unused break.
All visits and their incoming journeys fit within the daily window. Waiting for a
venue to open is allowed. Visits never cross midnight.

HTTP 200 returns `schema_version: "1"`, `trip_id`, `timezone: "Asia/Manila"`,
`estimated_total_cost` (decimal string), `revision`, and `items`. Every item uses
the existing association response plus these previously stored schema columns:

- `arrival_time`, `departure_time`: local `HH:MM:SS` strings;
- `estimated_travel_time`: whole incoming journey minutes;
- `estimated_cost`: total party venue cost plus the incoming journey estimate;
- `recommendation_score`, `recommendation_reason`: the validated #53 values.

`day_number` starts at 1 relative to saved `start_date`. `visit_order` starts at 1
on each used day. Items sort by day/order. The existing paginated
`GET /api/v1/trips/{trip_id}/items` now returns these fields too; manual items
have null generated fields. The trip GET returns the persisted total. Refreshes
and new backend processes read PostgreSQL, not process memory.

## Ordering, hours and budget assumptions

The planner uses **ranked first fit**. For each distinct validated recommendation
in descending score order, try each trip day and each opening interval from
earliest to latest. Append to the first feasible day; do not reorder earlier
visits. Skip an infeasible candidate and try the next one. Stop at the requested
total count. This is deliberately bounded and deterministic. It may reject a
request that a more complex routing or packing algorithm could solve; optimal
routing, turn-by-turn navigation and new paid dependencies are outside #54.

Hours must use lowercase English weekdays and arrays of exact
`{"open":"09:00","close":"18:00"}` intervals. Accept only zero-padded 24-hour
`HH:MM`, `open < close`, and nonoverlapping intervals. A missing weekday or empty
weekday list is closed. `{}` is unknown, and an unsupported key/format, overlapping
periods, overnight hours, 24:00, equal endpoints or holiday overrides makes the
venue unschedulable. There is no invented 24-hour/default schedule. Typical visit
duration, coordinates and upper venue cost must all be known. A visit must finish
at or before closing. Weekly schedules are assumed to apply on the saved dates;
exceptional holiday closures cannot be guaranteed by this weekly schema.

The seeded catalog currently has unknown hours. A clear conflict for those venues
is expected until verified administrator-managed hours are supplied. Tests use
explicitly synthetic fixtures with known hours, leaving shared catalog rows alone.

Budget is total trip PHP for the party. Retain #53's equal per-person/per-visit
eligibility ceiling, then enforce the saved total maximum over actual venue and
travel estimates. Use each known venue's **upper cost × party size**, plus its
incoming journey cost. Budget minimum is context, not a minimum-spend requirement.
Unused budget is allowed; lodging, meals outside selected venues, reservations
and the final return journey are outside this estimate. The trip total is the
exact sum of persisted item costs. Unknown costs never become zero.

## Travel estimates and start location

Use Haversine straight-line distance (Earth radius 6371.0088 km), multiplied by
1.3 as a simple detour allowance. These constants are documented planning
assumptions, not verified road routes, live traffic or quoted transport fares.

| Saved transportation mode | Speed km/h | PHP/km/person |
| --- | --- | --- |
| `walking` | 4 | 0 |
| `jeepney`, `public_transport` | 15 | 5 |
| `taxi` | 20 | 20 |
| `motorcycle` | 20 | 4 |
| `private_car`, `private_vehicle` | 20 | 8 |

Incoming travel time is `ceil(estimated km / speed × 60)`, plus five minutes for a
nonzero journey. Travel cost is rounded **up** to centavos after multiplying by
party size. Using party size for private modes is conservative and is not vehicle
occupancy optimization. Null/other transport labels return 422 rather than assume
a mode. With explicit `recommendations.origin`, each day starts at that coordinate
at the daily window's beginning. Without it, each day starts at its first venue
with zero incoming travel time/cost; this does not claim hotel-to-venue transport.
Later visits start from the preceding venue. No return-to-origin leg is scheduled.

## Confirmation, atomicity and errors

Generation creates a whole plan. It does not append to an existing itinerary or
silently discard manual items. If any items exist and `replace_existing` is false,
return 409 with `detail.code: "replacement_confirmation_required"`, a `revision`,
and a message explaining that **all existing items, including manual items**, would
be replaced. Roel should show the saved items and a confirmation dialog. Only after
the user confirms, resend the desired options with:

```json
{
  "replace_existing": true,
  "expected_revision": "THE_32_CHARACTER_REVISION_FROM_THE_CONFLICT"
}
```

Merge these two fields into the original request; they are required together.
The revision covers every saved trip and item field, including item UUIDs. Any
intervening edit/removal/addition/regeneration makes confirmation stale and returns
409. A successful response includes its new revision. Replaying an old confirmed
request cannot replace the newer plan. An ordinary repeat returns the confirmation
conflict. This is a confirmation/version check, not a cross-request idempotency key.

Before inference, a server-only `itinerary_state` RPC takes a consistent trip/items
snapshot. `save_generated_itinerary` locks that owned parent, checks the revision,
locks selected location rows and compares their complete validated snapshots,
rechecks persisted left swipes and validates positions, bounds, hours, minimum
duration, nonoverlap, scores and total. It deletes old items, inserts all new items
and updates the total **in one PostgreSQL transaction**. A validation error, insert
failure, constraint violation or deadlock rolls back the entire save. Concurrent
generations cannot both use the same confirmed revision successfully.

A trigger makes manual item writes take the same parent lock and clears
`estimated_total_cost`: an edited plan has not been fully revalidated. Remaining
items keep their IDs, times and explanations; remove does not reroute/renumber
them. Manual additions keep null scheduling fields. Regenerate with confirmation
to obtain another complete validated plan. Trip CRUD edits also change the revision;
this endpoint does not automatically regenerate existing items after a later trip
edit. Saved schedules describe the facts at generation time, not ongoing venue
availability. A rejection committed after the final database check is a later
event, not a retroactive rewrite of an already saved itinerary.

| Status | Meaning |
| --- | --- |
| 200 | Complete requested count saved; no underfilled/partial success |
| 401 | Missing/invalid existing demo credential |
| 404 | Missing/other-owner trip |
| 409 | Confirmation required, stale/concurrent change, no suitable candidates or requested visits do not fit |
| 422 | Invalid options or unsupported saved preferences, transport or trip length |
| 503 | Database/configuration/missing migration, model or malformed-output failure |

Infeasible 409 responses include a code, requested/scheduled counts and per-candidate
skip reasons when available. `scheduled_visits` is a count from an **unsaved**
attempt. Existing items/total stay intact. Model output goes through the unchanged
#53 adapter; no client-supplied ranked IDs or AI schedules bypass its validation.
Database/provider errors remain sanitized. A transport timeout may occur after
commit: reload the trip/items before retrying; an absent response does not prove
the save failed. Revision checks prevent blind overwrite on retry.

## Migration and verification sequence

The additive [migration](../supabase/migrations/20261028130000_atomic_itinerary_generation.sql)
creates functions and a trigger, not new tables/columns or a second database
connection. RPC execution is revoked from PUBLIC/anon/authenticated and granted
only to the backend `service_role`; functions use invoker permissions and a fixed
empty search path. Existing application RLS and table privileges remain in place.
The backend still uses the existing Supabase Data API settings. `.env` and
`.env.example` need no changes.

1. Run the offline planner/API suite, lint and unchanged Week 3 evaluation.
2. Required Database CI applies all migrations to disposable PostgreSQL 17 and
   runs the existing SQL smoke/ORM checks, the real API verifier, forced second
   insert rollback, malformed/stale/foreign replacements, role privileges and
   simultaneous confirmation tests. No hosted secrets are used.
3. Once isolation passes, apply the reviewed migration to **development** project
   `vnpkyvtbupnquvirzlzp`, using the existing Supabase migration workflow. Review
   CLI linkage and dry-run output before push. CLI linkage is independent of the
   backend target; never change `.env` to switch targets.
4. Run `.\.venv\Scripts\python.exe backend/verify_itinerary_generation.py`.
   This refuses every hosted target except the exact development Data API URL
   **before HTTP**. It uses new UUID fixtures and a temporary process-only demo
   credential. Cleanup attempts every registered exact UUID filter and independently
   checks absence, even on failure. Do not force-stop it; investigate printed IDs
   if cleanup fails. A new application/client reload is not a deployed restart.
5. Have Roel confirm the request/response and replacement UX; get teammate PR
   review and green required CI. Coordinate production migration with Kyle after
   development passes and before production deployment acceptance. Normal `main`
   merges deploy staging then automatically promote production; no workflow change
   or unrelated redeploy is part of #54.
6. Verify authenticated **staging against development first**, then production
   `zjnuqqtbapbpudsjbpif` with its separate demo credential and fresh synthetic
   trip/known-hours locations. Never edit shared catalog records just to pass a
   check. Capture commit/revision, successful generation, item/trip reloads,
   conflict/error preservation, manual edit compatibility and independent SQL.
   Keep an exact fixture manifest for cleanup.
7. Retain a saved synthetic plan through an actual subsequent deployment; compare
   item IDs, schedules, total, scores and reasons before/after. Coordinate with
   DevOps; a TestClient restart does not establish redeployment persistence.
   Publish evidence linked to #54; close it only after all acceptance/DoD gates.

Observed results and pending release gates: [#54 evidence](evidence/itinerary-generation.md).

Transaction and locking references: [PostgREST transaction semantics](https://docs.postgrest.org/en/v12/references/transactions.html),
[RPC schema-cache reload](https://docs.postgrest.org/en/v12/references/api/functions.html),
[PostgreSQL row locking](https://www.postgresql.org/docs/17/explicit-locking.html).
