# Issue #54 verification evidence

Implementation: [PR #89](https://github.com/relax-mode/lagaw/pull/89), branch
`feat/s3-09-itinerary-generation`, based on main `af5d580`. Tested code: `2228f96`.
Only #54 backend/planner/database tests, migration and associated documentation
are in scope. Private `.env` is unchanged and has not been displayed. Untracked
root `test-results/` is preserved. No production request or write has been made.

## Observed locally — October 28, 2026

- Final full local offline suite: **560 passed**, 102 database tests deselected,
  18.55 seconds; subsequent cost-serialization change passed all 50 relevant
  API/association tests locally and the complete suite in CI.
- Ruff clean.
- Week 3 evaluation: 27/27 extraction cases, 84/84 fields, 10/10 content cases;
  baseline comparison reports no regression (including hybrid metrics).
- Planner tests cover hours/closures/split intervals, missing facts, exact closing
  boundaries, insufficient time/budget, party cost, travel/origin, pace and sorted
  multi-day first-fit scheduling. API tests cover confirmation, malformed output,
  validation/auth and persistence error mapping.

## Isolated PostgreSQL/PostgREST CI — passed

[Run 40685456574](https://github.com/relax-mode/lagaw/actions/runs/40685456574)
passed at code commit `2228f96`:

- Backend: **560 passed**, 102 database tests deselected, 10.95 seconds, Ruff clean,
  extraction 27/27, fields 84/84, content 10/10, unchanged baseline/hybrid metrics.
- Database: PostgreSQL 17 migrations, SQL smoke/client-role/server-role checks,
  ORM relationships and the existing association verifier all passed.
- Downloaded and independently parsed
  [JUnit artifact 12815085483](https://github.com/relax-mode/lagaw/actions/runs/40685456574/artifacts/12815085483):
  **102 tests, zero failures/errors/skips, 4.419 seconds**.
- New real API persistence/confirmation/manual-edit test: 0.286 seconds.
- Forced failure on the second replacement insert rolls back original deletion,
  any new rows and the trip total: 0.020 seconds.
- Overlap, closed hours, budget overflow, changed catalog, new owner rejection,
  stale revision and foreign-owner replacement all preserve the saved state.
- RPC execution denied to client roles; service-role access verified.
- Two concurrent replacements using the same confirmed revision produce exactly
  one complete winner: 0.033 seconds; final database state equals that response.
- [AI evaluation artifact 12815160069](https://github.com/relax-mode/lagaw/actions/runs/40685456574/artifacts/12815160069)
  is attached to the same successful run.

Earlier isolated runs caught and resolved an existing-FK error compatibility
regression in the locking trigger and inconsistent decimal formatting between
JSONB RPC and item-list responses. These were corrected before hosted migration.
Frontend and deployment correctly skipped for this backend PR. CI is isolated;
these results do not establish hosted deployment.

## Development Supabase — passed after isolation

Target: **`vnpkyvtbupnquvirzlzp`**, independently checked through both the Data API
guard and the existing SQLAlchemy development-target guard. Production was refused
by the offline verifier safety test. Neither `.env` nor CLI linkage was changed.

Applied only migration `20261028130000_atomic_itinerary_generation` using the
existing private SQL connection after checking the exact two preceding migration
versions. DDL and `supabase_migrations.schema_migrations` registration committed
in one guarded transaction. A subsequent SQL comparison confirms the registered
statements equal the tested migration file exactly. Supabase CLI
`migration list --linked` independently reports all three local/remote versions
aligned. No existing catalog/trip/user records were edited for setup.

Ran `backend/verify_itinerary_generation.py` successfully. It used its own temporary
process-only owner/token and deterministic ranked fixtures through the real #53
adapter and PostgreSQL API, never DeepSeek. Observed:

```text
PASS: Real ordered multi-day generation, party total, times, score/reason and association reload.
PASS: Confirmation, stale/replayed revisions, closed/empty/malformed failures and exact preservation.
PASS: Fresh application persistence, manual removal/addition, estimate invalidation and preserved locations.
PASS: Exact #54 fixture cleanup and independent absence checks.
```

The synthetic two-person trip on November 2–3 schedules one 09:00–10:00 visit on
each known-open day. Total PHP 80.00, persisted scores 0.9/0.8 and nonblank reasons
reload through GET items. Missing/foreign-owner trips return 404, unauthenticated
generation returns 401, ordinary repetition requires confirmation, stale/replayed
revisions conflict, and confirmed replacement succeeds. Closed-afternoon, empty
and malformed-model attempts preserve original trip/items exactly. A new app/client
reload succeeds; manual remove/add clears the complete-plan estimate and preserves
the other item and both locations.

Exact disposable fixture manifest (all removed):

| Type | UUID |
| --- | --- |
| Owner | `14b3b779-882f-424a-8aa4-8e48a3c6f330` |
| Other owner | `ae36f707-d869-4885-892b-434d24654810` |
| Trip | `ab3ab81c-df34-4470-9096-7fe02abcebba` |
| Other-owner trip | `14f9b574-697a-4465-86d4-266aa7631052` |
| Monday venue | `2a0642f2-b865-4deb-9fad-23a125d06a3d` |
| Tuesday venue | `e4b419b5-6149-4908-af67-50c09666d32a` |

After the verifier's exact HTTP cleanup, a separate direct development SQL
connection independently confirmed all six IDs and their itinerary items are
absent. The migration/functions/trigger remain intentionally installed. No
production call/write, shared demo fixture modification or environment-file edit
was made. This local FastAPI-to-development check is **not deployed staging**.

## Review and production migration readiness

On October 28, independently confirmed CyGray **approved** the current PR #89
head `92536e7039c35d6032be783d24dbf9ba86b2e1fa` at 12:21:21 UTC. GitHub reports
the PR clean/mergeable; latest [CI run 40686293474](https://github.com/relax-mode/lagaw/actions/runs/40686293474)
passed Backend and Database (Flutter/deployments correctly skipped). Approval is
complete, and the reviewed implementation head remains unchanged.
Prepared a single-use transaction wrapper in ignored local
`backend/test-results/issue54-production-migration.sql`, embedding the exact
approved migration, guarding the expected preceding migration history, registering
the new version and checking function/role/trigger state before commit. Andrew
must select production project `zjnuqqtbapbpudsjbpif` in SQL Editor before running
it; the SQL has no reliable independent project-ID assertion. Existing development
already contains the migration and fails the preceding-history guard. The approved
implementation branch is unchanged; this follow-up is on a separate documentation
branch.

Andrew subsequently supplied the production SQL Editor result:

```json
[
  {
    "result": "PASS: Issue 54 migration installed; history, backend privileges and trigger verified.",
    "migration_version": "20261028130000"
  }
]
```

This is developer-reported execution in the instructed production context, not
an independent agent production query. It confirms the wrapper committed after
its migration-history, service/client privilege and trigger checks. The reviewed
SQL source matches the development-tested migration. The agent did not change
`.env`, CLI linkage or use production credentials. Rechecked PR #89: CyGray's
approval still matches head `92536e7`, required applicable checks remain green,
and GitHub reports clean/mergeable. The production migration prerequisite is
satisfied; Andrew can merge through the normal reviewed PR flow. This result
does not establish deployment or authenticated generated-itinerary acceptance.

## Pending — do not infer completion

PR #89 merged at **14:39:27 UTC on October 28, 2026** as
`e2f830c40f43180791671fca1c51e36629b47188`. Independently confirmed the merge,
fast-forwarded local main and merged it into the separate documentation branch,
preserving untracked root `test-results/`. Main
[run 40708112116](https://github.com/relax-mode/lagaw/actions/runs/40708112116)
passed Backend, Database and Flutter, followed by successful staging deployment
and its existing smoke checks. The same run subsequently completed production API
promotion and existing smoke checks successfully; production web correctly skipped.
Authenticated acceptance still proceeds in staging first.

Downloaded and independently parsed main
[JUnit artifact 12823649025](https://github.com/relax-mode/lagaw/actions/runs/40708112116/artifacts/12823649025):
**102 database tests, zero failures/errors/skips, 4.865 seconds**, including the
new persistence test (0.392 seconds), forced rollback (0.022 seconds) and concurrent
confirmation (0.037 seconds). Main
[evaluation artifact 12824252773](https://github.com/relax-mode/lagaw/actions/runs/40708112116/artifacts/12824252773)
is attached to the same run.

Andrew reported private authorization in staging Swagger. Independently confirmed
the deployed staging OpenAPI contains the generation route and unauthenticated
POST returns 401 with exact staging CORS. Created only three new marked synthetic
development locations with explicit weekly hours and a new staging-owned synthetic
trip `03b7f114-9b91-4985-9bf5-3efdb3a54d76`, November 2–3, friends/walking, budget
PHP 0–180. Existing records and the shared owner profile were not edited. Expected
generation: party size 2, three visits, morning/moderate, total PHP 120.00 with two
Monday visits and one Tuesday visit. A guarded independent development read
confirmed the trip starts with no items and null total. Exact fixture manifest,
request and baseline are in [staging evidence](itinerary-generation-staging.json);
fixtures are retained deliberately for deployed/redeployment acceptance and must
be cleaned by exact IDs afterward.

Andrew supplied the authenticated staging generation **HTTP 200** response:
three saved items, revision `295151016df684c49343b6834454a279`, total PHP 120.00.
The full safe response is recorded in [staging evidence](itinerary-generation-staging.json).
It validates against the executable generation schema. Independent arithmetic and
guarded development reads verified:

- Day 1/order 1, Monday A: 09:00–09:30, zero first-leg travel, party cost PHP 20.00,
  item `ffaed327-ed3a-48e5-8984-34beec8776bd`, score `0.9333333333333332`.
- Day 1/order 2, Monday B: 09:53–10:23, eight travel minutes after a 15-minute
  moderate-pace break, party cost PHP 40.00, item
  `7dd04d5e-6208-4eb3-b51e-0015bb21737a`, score `0.8666666666666667`.
- Day 2/order 1, Tuesday: 09:00–10:00, zero first-leg travel, party cost PHP 60.00,
  item `f5ff4c3b-4772-4c43-af92-fb6267af1329`, score `0.7999999999999999`.
- All visits fit their real fixture hours on the saved dates, respect typical
  durations and have no overlaps. Costs equal venue upper costs × two travelers,
  total exactly PHP 120.00, below saved PHP 180 maximum.
- Every persisted item field, nested location, score/reason, revision and trip total
  matches the supplied response. Original trip fields are unchanged except the
  newly saved estimate. Authenticated generation is developer-reported; the
  database comparison is an independent agent check with the development guard.

Andrew then supplied the unchanged request's staging **HTTP 409** response,
`replacement_confirmation_required`, with the same revision
`295151016df684c49343b6834454a279` and explicit warning that replacement includes
manual items. A new guarded development read confirms the entire trip, all three
item IDs/fields, nested locations, scores/reasons, total and revision equal the
after-generation baseline exactly. Repeated generation did not replace any saved
record. The full safe request/response and comparison are in staging JSON evidence.

Andrew supplied the confirmed afternoon replacement's staging **HTTP 409**:
`requested_visits_do_not_fit`, zero scheduled of three requested, and each exact
fixture ID skipped as `insufficient_time_or_closed`. The request used the current
revision and explicit replacement confirmation, so this exercises planning failure
after confirmation rather than the initial confirmation guard. Independent guarded
development reads show the complete trip and all saved item/location fields,
scores/reasons, revision and PHP 120.00 total still equal the original generation
baseline exactly. No old item was erased or replaced and no partial itinerary was
saved. Full safe request/response and comparison are in staging JSON evidence.

After refreshing staging Swagger, Andrew supplied authenticated **GET items HTTP
200**, limit 100/offset 0. The full body retains the original three item IDs,
locations, day/order, times, travel estimates, costs, scores and reasons exactly.
It validates against the existing association page schema. A fresh guarded
development read confirms the complete original trip/items/revision and PHP
120.00 total are still unchanged. Browser-refresh persistence is verified; this
does not establish persistence through an actual later deployment.

Andrew supplied manual-add staging **HTTP 201** for existing Monday A at day
1/order 3: item `fc4fd318-403e-4ed9-a907-ad262a5e5c1c`, all generated schedule,
travel/cost and recommendation fields null. A guarded development read independently
matches that exact new row, confirms the original three generated visits and all
their metadata unchanged, and confirms the trip's complete-plan estimate is now
null while other trip fields are preserved. The revision changed as expected.
This establishes manual-add compatibility with the saved generated plan.

Andrew supplied manual-remove staging **HTTP 204**, no response body, for only
`fc4fd318-403e-4ed9-a907-ad262a5e5c1c`. An independent guarded development read
confirms its absence and exact preservation of all original generated item IDs and
metadata. All three fixture destinations remain active. The total stays null,
as documented after manual editing; other trip fields are unchanged. The current
revision is `668270157b649de9dce86d2c042b365c`, distinct from both the initial saved
plan and the four-item manually edited state.

Andrew supplied confirmed morning regeneration's staging **HTTP 200**: revision
`710c2399e657678caae1bf63cd82b5bc`, total PHP 120.00, new item IDs
`7b99d4e1-853f-41db-8c26-6ff660ac89b9`,
`f7c0a84f-0e17-4f47-b86c-bcfe463f84fc`, and
`582e663d-052a-45db-88ab-beee1d905084`. All location/order/time/travel/cost and
score/reason fields match the original valid plan. The response validates against
the generation schema. Independent guarded development reads match every new saved
item and revision, confirm all three old generated IDs plus the removed manual ID
are absent, and confirm the original trip/total is restored exactly. This proves
the successful confirmed-replacement path after manual editing.

Staging functional acceptance now covers generation, repeat confirmation,
infeasible replacement preservation, browser-refresh reload, manual add/remove
and successful confirmed regeneration. The exact regenerated state is retained
in staging JSON as the **actual redeployment baseline**; that later-deployment
check and exact fixture cleanup are still pending.

After these staging checks, independently confirmed production OpenAPI contains
the generation route and unauthenticated POST returns 401 with exact production
CORS. Prepared only a separate production fixture manifest in
[production evidence](itinerary-generation-production.json) and a local ignored
`backend/test-results/issue54-production-fixtures.sql`: three new marked synthetic
venues and trip `5b4497d1-a946-4845-bed5-441fbb563180`, owned by the existing
separate production demo profile. The SQL guards migration/profile presence and
exact-ID absence, creates records transactionally, and returns an exact cleanup
manifest. Andrew must select production project `zjnuqqtbapbpudsjbpif` in SQL
Editor; there is no reliable project-ID assertion inside this SQL. Production
setup execution was subsequently reported by Andrew as **PASS**, with exact new
trip `5b4497d1-a946-4845-bed5-441fbb563180`, owner
`23000000-0000-4000-8000-000000000001`, and location IDs
`6fe3ecfb-2435-4ef5-bd15-4fc5a4803227`,
`035843d7-c6c8-498e-9c0a-86dc0d60527e`,
`010d414e-50ce-4be3-82e3-8e30ab8207be`. The result matches the prepared manifest.
An independent public production catalog read confirms every new venue's exact
ID/name, active state, hours, coordinates, costs, duration and group/tags. Guarded
development reads confirm those production trip/location IDs are absent there
and the entire regenerated staging plan remains unchanged. Setup is developer-
reported SQL execution; no agent production write or credential access occurred.
The known setup script creates a new empty trip with null estimate, but a protected
production trip/database baseline has not been independently read by the agent.
Preparing authenticated production generation with its separate demo credential;
full safe setup result and checks are in the production JSON evidence.

Andrew supplied production generation **HTTP 200**, trip
`5b4497d1-a946-4845-bed5-441fbb563180`, timezone Asia/Manila, total PHP 120.00,
revision `c906b3caf89e3fa668ba434c8c7f3df4`. Items:

- Day 1/order 1, 09:00–09:30: `83386a42-04f3-45c8-9218-7cd1819a12ec`,
  production Monday A, travel 0, cost PHP 20.00, score `0.9333333333333332`.
- Day 1/order 2, 09:53–10:23: `83327ba8-f3fd-4efd-8372-3e608be0cc7b`,
  production Monday B, travel eight minutes, cost PHP 40.00, score `0.8666666666666667`.
- Day 2/order 1, 09:00–10:00: `8ff6b063-c621-41af-9c7c-76f303919992`,
  production Tuesday, travel 0, cost PHP 60.00, score `0.7999999999999999`.

Validated the executable generation schema, date/day/order, weekly opening hours,
typical durations, 15-minute break plus eight-minute incoming journey, nonoverlap,
party costs and total against saved setup budget PHP 180. Every nested location
field independently matches the current public production catalog. All supplied
scores are finite/normalized and reasons nonblank. The exact safe response is
recorded in production JSON evidence. Protected reload/direct production SQL
comparison, conflict preservation and actual redeployment persistence remain
pending; this supplied API success is not an independent agent production database
query. No production credential or write was used by the agent.

Andrew supplied the same production request's **HTTP 409** response:
`replacement_confirmation_required`, revision
`c906b3caf89e3fa668ba434c8c7f3df4`, with the explicit message covering replacement
of existing/manual items. The reported revision matches initial generation.
Recorded the exact safe request/response in production JSON. Item-level preservation
will be checked through the next authenticated reload and production SQL evidence;
the agent has not performed a protected production database read.

Andrew supplied confirmed-afternoon production **HTTP 409**:
`requested_visits_do_not_fit`, zero scheduled of three requested, each exact
production fixture ID skipped as `insufficient_time_or_closed`. The request used
the current generation revision with explicit replacement confirmation; the result
therefore exercises infeasible planning after confirmation. Recorded the full safe
request/response. Production authenticated item reload after refresh and direct
SQL evidence are next to compare the saved rows; the conflict message alone is
not treated as independent proof of item-level preservation.

After refreshing production Swagger, Andrew supplied authenticated **GET items
HTTP 200**, limit 100/offset 0. The entire three-item list equals the initial
generation response: same item/location IDs, day/order, times, travel estimates,
costs, scores and reasons. It validates against the association page schema.
Thus the supplied deployed reload confirms browser-refresh persistence and no
item-level change after ordinary-repeat and infeasible-replacement requests.
Prepared ignored local `backend/test-results/issue54-production-verify.sql` for
the production SQL Editor to verify the exact owner/trip, current revision,
PHP 120.00 total and three-item count, and return its complete saved state.
The read-only script was parsed/exercised against guarded development and correctly
refused it because the exact production trip is absent.

Andrew supplied the read-only production SQL **PASS** and full `saved_state`.
Parsed it as the executable `ItineraryState` schema: every saved item field,
score/reason and revision equals the initial production API response. The expected
owner, dates, budgets, title/status, group/tags and transport match setup exactly;
saved total and sum of item costs both equal PHP 120.00. Thus SQL and refreshed API
evidence agree on preservation after the two conflict cases. Production SQL is
developer-reported execution, compared by the agent; no direct agent production
database query or credential access is claimed. Recorded the complete SQL result
and exact state as production's actual-redeployment baseline.

Checked subsequent main CI/deployments: latest main is still merge `e2f830c` and
there has been no later deployment suitable for the persistence check. Andrew
confirmed Cloud Run access. Preparing guided redeployment of the currently serving
staging image/configuration first, with before/after revision evidence, followed
by saved-state comparison; production follows only after staging persistence passes.
No Cloud Run settings or deployments have yet been changed for this check.

Andrew reported Cloud Shell's staging `latestReadyRevisionName` as
`lagaw-api-staging-00022-pk2`. Recorded that before revision alongside the retained
generated-state baseline. Prepared and Bash-syntax-checked a staging-only redeploy
command which refuses an intervening revision change, reads that revision's exact
immutable Artifact Registry image digest, and deploys it as
`lagaw-api-staging-issue54-persist`. It supplies no environment/secret configuration
flags and leaves the local `.env` intact. The final read returns ready revision and
traffic metadata only. This is prepared guidance, not an observed deployment;
actual execution and subsequent saved-state comparison remain pending.

- Roel's agreement on the documented API/confirmation contract (Andrew reports no
  confirmed prior agreement).
- Cloud Run staging-before-production actual redeployment persistence.
- Persistence across an actual hosted redeployment, then exact fixture cleanup.
- Final issue-linked evidence and closure after the Definition of Done is satisfied.

The [API guide](../itinerary-generation-api.md) gives the safe release/verification
sequence. Local mock results do not establish atomic PostgreSQL persistence or
hosted deployment. Keep #54 open until those gates are complete.
