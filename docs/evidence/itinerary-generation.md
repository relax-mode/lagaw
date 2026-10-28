# Issue #54 — itinerary generation verification

Backend implementation, deployment, acceptance and cleanup are complete. Roel's
API-contract acknowledgment remains unverified, and this final evidence update
still needs the normal documentation PR review/merge. Keep #54 open for that
coordination item; do not claim the Flutter integration is implemented.

Only #54 backend/planner/database work and its documentation were changed. The
private `.env` and Supabase CLI development linkage are unchanged. Root untracked
`test-results/` was preserved. Production credentials were never displayed or
read by the agent; Andrew performed the reported production SQL/Swagger/Cloud
Shell steps privately.

## Implementation, review and deployment

- [Implementation PR #89](https://github.com/relax-mode/lagaw/pull/89), approved by
  CyGray on head `92536e7`, merged October 28, 2026 at 14:39:27 UTC as
  `e2f830c40f43180791671fca1c51e36629b47188`.
- [Main CI/deployment run 40708112116](https://github.com/relax-mode/lagaw/actions/runs/40708112116)
  passed Backend, Database and Flutter, deployed staging and then promoted the
  same image to production. Production web correctly skipped for this backend change.
- [API contract and assumptions](../itinerary-generation-api.md): bounded ranked
  first-fit ordering, Asia/Manila dates/times, known operating hours/durations,
  documented travel/pace estimates, party budget, explicit replacement confirmation
  and atomic persistence using the existing schema.
- Migration `20261028130000_atomic_itinerary_generation` passed isolation and
  development before production. Development DDL/history registration committed
  together, and CLI migration list confirmed all versions aligned. Andrew's guarded
  production SQL returned migration/history/backend-privilege/trigger PASS before merge.

## Automated checks

| Check | Observed result |
| --- | --- |
| Offline regression suite | 560 passed; Ruff clean |
| Week 3 evaluation | 27/27 extraction cases, 84/84 fields, 10/10 content cases; no baseline/hybrid metric regression |
| Isolated PostgreSQL 17/PostgREST | 102 tests; zero failures, errors or skips |
| Existing schema/role/ORM/association checks | Passed |
| Forced failure on second replacement insert | Original deletion, new rows and trip estimate all roll back |
| Concurrent confirmed replacements | Exactly one complete winner; final saved state equals its response |
| Stale/catalog/rejection/overlap/closed/budget/foreign replacements | Rejected with saved state preserved |
| Production-refusal and exact-cleanup verifier checks | Passed |

Independently downloaded and parsed:

- [PR JUnit artifact 12815085483](https://github.com/relax-mode/lagaw/actions/runs/40685456574/artifacts/12815085483),
  tested code `2228f96`: 102 tests, zero failures/errors/skips, 4.419 seconds.
- [Main JUnit artifact 12823649025](https://github.com/relax-mode/lagaw/actions/runs/40708112116/artifacts/12823649025):
  102 tests, zero failures/errors/skips, 4.865 seconds; new persistence test 0.392s,
  forced rollback 0.022s, simultaneous confirmation 0.037s.
- [Main evaluation artifact 12824252773](https://github.com/relax-mode/lagaw/actions/runs/40708112116/artifacts/12824252773).

The first isolated runs caught an FK-error compatibility regression and inconsistent
cost formatting between RPC and item reads. Both were fixed before hosted migration.
No workflow, new paid dependency, new table or environment setting was introduced.

## Development verification before production

The guarded `backend/verify_itinerary_generation.py` passed against development
`vnpkyvtbupnquvirzlzp` after isolation. Its temporary process-only demo credential
was never displayed. It exercises real saved trips/catalog and the #53 validation
adapter using deterministic ranked fixtures, without DeepSeek. All four PASS groups:

```text
PASS: Real ordered multi-day generation, party total, times, score/reason and association reload.
PASS: Confirmation, stale/replayed revisions, closed/empty/malformed failures and exact preservation.
PASS: Fresh application persistence, manual removal/addition, estimate invalidation and preserved locations.
PASS: Exact #54 fixture cleanup and independent absence checks.
```

The initial verifier's two synthetic users, two trips, two venues and related rows
were removed. A separate guarded SQL connection independently checked their exact
absence and that migration history matched the tested file. Their manifest remains
in the sprint history; later deployed acceptance used separate fixtures below.

## Deployed acceptance

Full safe requests, responses, baselines and cleanup manifests:
[staging JSON](itinerary-generation-staging.json) and
[production JSON](itinerary-generation-production.json).

| Environment | Database | Exact synthetic trip |
| --- | --- | --- |
| Staging | `vnpkyvtbupnquvirzlzp` | `03b7f114-9b91-4985-9bf5-3efdb3a54d76` |
| Production | `zjnuqqtbapbpudsjbpif` | `5b4497d1-a946-4845-bed5-441fbb563180` |

Each environment used three newly created, clearly marked synthetic venues with
explicit weekly hours, a new trip for its existing separate demo owner, and dates
November 2–3. Shared users/catalog/trips were preserved. For two travelers and three
morning/moderate visits, both deployed APIs returned:

| Day/order | Arrival–departure | Incoming travel | Party item cost |
| --- | --- | --- | --- |
| 1/1 | 09:00–09:30 | 0 minutes | PHP 20.00 |
| 1/2 | 09:53–10:23 | 8 minutes, after a 15-minute pace break | PHP 40.00 |
| 2/1 | 09:00–10:00 | 0 minutes, new-day venue start | PHP 60.00 |

Total **PHP 120.00**, within saved PHP 180 budget. All visits fit the fixture's
actual saved hours/day, meet visit duration and avoid overlap. Scores
`0.9333333333333332`, `0.8666666666666667`, `0.7999999999999999` and nonblank reasons
persisted and reloaded exactly. Every returned location field independently matched
the relevant public catalog or guarded development database record.

Verified in staging before repeating production acceptance:

- HTTP 200 complete generation linked to real trip/location database rows.
- HTTP 409 ordinary repeat requires explicit confirmation and reports the saved revision.
- HTTP 409 explicitly confirmed afternoon replacement schedules zero visits because
  all three selected venues are morning-only; the original plan is preserved.
- HTTP 200 item reload after browser refresh retains every original item and field.
- Staging additionally exercised deployed manual add (201), exact manual remove
  (204), invalidated complete-plan estimate and confirmed regeneration (200) restoring
  a valid schedule/total with new IDs. These paths also passed isolated/live development tests.
- Both deployed endpoints reject missing credentials with 401 and correct CORS.
- Production's complete read-only SQL state agrees with its API responses after
  generation/conflicts/refresh, including owner, dates, budgets, preferences, total and revision.

## Persistence through actual later deployments

Andrew used Cloud Shell to redeploy each currently serving immutable image digest
with its existing service configuration and a new revision suffix. Staging was
completed and checked before production. No environment/secret flags or local
`.env` edits were used. These are explicit #54 persistence deployments, following
the normal reviewed merge/CI deployment above.

| Environment | Before revision | New revision, ready and 100% traffic | Retained itinerary revision |
| --- | --- | --- | --- |
| Staging | `lagaw-api-staging-00022-pk2` | `lagaw-api-staging-issue54-persist` | `710c2399e657678caae1bf63cd82b5bc` |
| Production | `lagaw-api-00012-z6p` | `lagaw-api-issue54-persist` | `c906b3caf89e3fa668ba434c8c7f3df4` |

After each actual new revision, authenticated GET items retained every pre-deployment
item ID, nested location, schedule, travel/cost, score and reason. Guarded development
reads independently confirmed complete staging state/total/revision equality.
Andrew's complete production SQL response after redeployment was parsed and compared:
all trip/items/locations, revision and PHP 120.00 total equal its pre-deployment baseline.
Both original and canonical Cloud Run URLs independently retained generation OpenAPI;
original URLs retained the expected 401 and exact environment CORS.

Evidence provenance: authenticated Swagger responses, production SQL and Cloud Shell
revision/traffic metadata were supplied by Andrew. The agent independently checked
GitHub review/merge/CI/artifacts, guarded development SQL/Data API state, public
catalog/OpenAPI/CORS and parsed comparisons. No direct agent protected production
DB or Cloud Run Admin API query is claimed.

## Exact cleanup — complete

Single-use completed SQL records: [staging cleanup](itinerary-generation-staging-cleanup.sql)
and [production cleanup](itinerary-generation-production-cleanup.sql). Both compare
the complete verified saved state and guard exact UUIDs, acquired outside references,
row counts and unchanged existing demo profile before committing.

- Development cleanup ran first as a rollback rehearsal, restoring the exact state,
  then committed. A separate guarded SQL session verified the exact trip/items/venues
  absent, demo profile unchanged, migration and generation function retained.
- Andrew supplied production SQL PASS: one exact trip, three itinerary items and
  three synthetic locations removed; existing demo profile preserved.
- Independent public production catalog reads confirm all three production fixture
  IDs absent. Final guarded development reads confirm its fixtures absent, production
  fixture IDs absent there, and existing staging demo profile retained.
- SQL/API evidence and manifests remain in these docs. Test records are removed;
  migrations, functions, existing demo users and other application data remain.

Current catalog limitation: after cleanup, the public production catalog has ten
active destinations, eight without supplied opening hours. Unknown hours deliberately
fail closed. Acceptance used explicit temporary fixture hours; no real venue hours
were invented or shared catalog facts edited for this issue.

## Remaining coordination and publication

On October 28, checked Roel's assigned [issue #56](https://github.com/relax-mode/lagaw/issues/56),
PR #89 discussion/reviews and his published frontend PRs/branches. #56 remains open
with no comments. His latest merged [PR #87](https://github.com/relax-mode/lagaw/pull/87)
is the manual #34 itinerary UI. Current Flutter `TripService` has manual item
methods but no generation call; `TripItem` does not parse arrival/departure,
travel/cost or score/reason fields. No published #56 implementation or explicit
Roel contract acknowledgment was found. Private/unpushed work cannot be assessed.

Backend technical acceptance is complete. Leave the #54 coordination checkbox open
until Roel acknowledges the documented contract; Flutter implementation remains
his separate #56 scope. This final documentation/evidence update still follows the
normal teammate-reviewed PR/CI/merge workflow. Published it as
[PR #90](https://github.com/relax-mode/lagaw/pull/90). Its
[documentation CI run 40721526465](https://github.com/relax-mode/lagaw/actions/runs/40721526465)
passed changed-area detection; app/database/Flutter checks and deployments correctly
skipped because the PR changes only these evidence/docs files. The actual application
checks and archived artifacts are linked above. Updated #54's completed technical
checklist and evidence links; left its coordination checkbox and issue open. Keep
#54 open while that acknowledgment and final evidence review/merge are pending.
