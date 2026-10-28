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
and its existing smoke checks. Production promotion is running automatically;
authenticated acceptance still proceeds in staging first.

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
be cleaned by exact IDs afterward. Authenticated generation is not yet observed.

- Roel's agreement on the documented API/confirmation contract (Andrew reports no
  confirmed prior agreement).
- Completed production promotion and authenticated deployed acceptance.
- Authenticated staging/development-before-production acceptance and independent SQL.
- Persistence across an actual hosted redeployment, then exact fixture cleanup.
- Final issue-linked evidence and closure after the Definition of Done is satisfied.

The [API guide](../itinerary-generation-api.md) gives the safe release/verification
sequence. Local mock results do not establish atomic PostgreSQL persistence or
hosted deployment. Keep #54 open until those gates are complete.
