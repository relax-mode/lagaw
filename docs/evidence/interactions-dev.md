# Issue #52 — interaction persistence evidence

- Issue: [#52](https://github.com/relax-mode/lagaw/issues/52).
- Prepared October 28, 2026, from main `17d93d9`.
- Branch: `feat/s3-07-user-interactions`.
- Final deployed evidence: [PR #85](https://github.com/relax-mode/lagaw/pull/85),
  branch `docs/issue-52-deployed-evidence`.
- Scope: interaction API/persistence, owner history and S3-01 input adaptation.
- Jayperson/Roel agreement to v1 semantics confirmed by Andrew in this session.
- `.env`, schema migrations, model training/ranking and Flutter controls unchanged.

| Check | Observed result |
| --- | --- |
| Initial focused offline API checks | 71 passed in 1.80 seconds |
| Full backend offline regressions | 403 passed, 90 database tests deselected in 13.42 seconds, including verifier target/cleanup regressions |
| Ruff, dependency and whitespace checks | All passed; `pip check` found no broken requirements |
| Offline Week 3 evaluation | 27/27 extraction scenarios, 84/84 field checks, 10/10 content cases, zero failures; baseline comparison reports no regression |
| Development Supabase | Guarded verifier passed all five PASS groups against `vnpkyvtbupnquvirzlzp` |
| Repeat development run | Passed all five groups again after preserving the real route's database-failure handler; new owners `bf841379-9185-4e55-abb2-9e0bdc6fe1f4`, `3bdb804d-3492-4c1e-af2e-dff1a4ed089e`; all fixtures cleaned |
| Exact fixture cleanup | Passed; all generated events, users and locations removed and absence independently checked |
| CI disposable PostgreSQL/PostgREST | [Run 40663142091](https://github.com/relax-mode/lagaw/actions/runs/40663142091), code commit `ca9ef21`: Backend and Database passed; **90 database tests passed, 403 deselected in 3.04 seconds** |
| Downloaded JUnit artifact | [trip-integration-results](https://github.com/relax-mode/lagaw/actions/runs/40663142091/artifacts/12803849469): 90 tests, zero failures/errors/skips; new interaction persistence/owner test passed in 0.225 seconds |
| Database job log | [Job 122730945064](https://github.com/relax-mode/lagaw/actions/runs/40663142091/job/122730945064); migrated isolated PostgreSQL/PostgREST, no hosted credentials |
| PR, teammate review and merged commit | [PR #84](https://github.com/relax-mode/lagaw/pull/84) approved by CyGray on final commit `ae5357d`, then merged October 28, 2026 at 09:24:27 UTC as `53a90e2` |
| Post-merge CI | [Main run 40663989070](https://github.com/relax-mode/lagaw/actions/runs/40663989070) passed Backend, Database and Frontend checks; downloaded [JUnit artifact 12805500510](https://github.com/relax-mode/lagaw/actions/runs/40663989070/artifacts/12805500510) confirms 90 database tests, zero failures/errors/skips, 3.676 seconds |
| Deployment | [Staging job](https://github.com/relax-mode/lagaw/actions/runs/40663989070/job/122734486513) passed the existing locations/Trip/auth/extraction/CORS smoke check, then [production API promotion](https://github.com/relax-mode/lagaw/actions/runs/40663989070/job/122735090751) passed its smoke check; production web correctly skipped for this backend-only merge |
| New staging route visibility and unauthorized access | OpenAPI returned 200 with all three interaction paths; unauthenticated history and recommendation-input returned 401, both with the expected staging CORS origin |
| Deployed staging interaction writes and database acceptance | Passed: four types, repeat saves/ratings, schema-v1 owner history and left-swipe exclusion; exact events independently confirmed in development PostgreSQL; invalid requests added no rows; exact cleanup preserved the user/location |
| Staging write baseline | Before testing, development confirmed active Cathedral location `1a3bca09-5532-5de6-8587-2440c4e5830d` and empty history for staging demo owner `16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c`. Subsequent accepted API writes established credential acceptance |
| First deployed staging save | Andrew reported HTTP 201 for event `7cbc150b-8bd0-41d5-96b9-aac46527180c`, timestamp `2026-10-28T09:37:49.255535Z`, correct staging owner/Cathedral, signal `"1"`, null rating and `provenance: real`. A guarded development database read independently confirmed the exact saved row |
| Repeated deployed staging save | Andrew reported HTTP 201 with new event `1cbd058a-6d5d-4633-a34d-cfdf171757b2`, timestamp `2026-10-28T09:38:50.099397Z`, for the identical save request. A guarded database read confirmed both original and repeated events remain as separate rows with the correct owner, location and values |
| Deployed staging swipes and rating | Andrew reported HTTP 201 for left swipe `5e1c928f-0d0b-4864-ae52-0283a9428495` (signal -1), later right swipe `4d30503b-aa4e-4a07-afbd-bcb2c933e05d` (signal +1), and rating `95a46ea2-0117-4944-bc18-c4ac4d9ee370` (signal +1, rating 3.75). A guarded development database read independently confirmed all five exact event IDs, types, ownership and values, including the two saves |
| Deployed staging recommendation input | Andrew supplied HTTP 200 with schema v1, all six owner events and Cathedral in `excluded_location_ids`, despite its later right swipe and ratings. The response also revealed another rating `ea0a8bd3-5749-49d5-b20d-786178214738` at `2026-10-28T09:40:19.004635Z`. A guarded PostgreSQL read confirmed all six events and the extra rating, preserving append-only semantics; all six IDs were subsequently cleaned |
| Deployed staging invalid requests | Andrew reported rating 6 returned 422 with only `loc`/`msg`/`type`, and missing location `52000000-0000-4000-8000-000000000099` returned 404 `Active location not found.` A guarded development read confirmed the same six exact events, with no added rows |
| Staging acceptance cleanup | Deleted only the six recorded IDs, additionally scoped to the staging owner and Cathedral location. Delete representation confirmed exactly those six IDs; independent reads verified empty owner history and unchanged existing user/active location |
| Production public route checks | OpenAPI contains all interaction routes; anonymous history returns 401 with the expected production CORS origin; `/locations` confirms the Cathedral UUID is active |
| Production interaction acceptance | Passed: all four event types, schema-v1 owner history/exclusion, invalid-rating rejection, exact production database verification/cleanup, parent preservation and final empty-history API read |
| Production authorization setup | Read-only GitHub production environment configuration confirms demo owner `23000000-0000-4000-8000-000000000001`; Andrew authorized privately and the subsequent successful history request established credential acceptance |
| Production pre-write baseline | Andrew supplied HTTP 200 from deployed recommendation-input with `schema_version: "1"`, empty interactions and empty excluded IDs. This confirms production credential acceptance and an empty baseline before test writes |
| Production event writes | Andrew supplied four HTTP 201 responses: save `1d20e029-a544-4619-b047-792b4a4763e8`, left swipe `acdc4adf-05cb-47de-8259-ae070245a3fe`, right swipe `ffe32188-3b95-4f6e-9485-fe16766cec85`, and rating `faba69d4-961b-4431-bea7-2262db70878a` (3.75). All have the configured production owner, active Cathedral UUID, correct -1/+1 signals and real provenance. Four responses were supplied; no production repeat-save result is claimed |
| Development/production isolation | A guarded development read confirmed all four reported production event IDs are absent from development; the staging demo history remains empty after cleanup |
| Production recommendation input and invalid rating | Andrew supplied HTTP 200 with exactly the four reported owner events, schema v1 and the Cathedral excluded despite its later right swipe/rating. Rating 6 returned 422 with only `loc`/`msg`/`type`. The subsequent SQL verification confirmed exactly four owner events, so invalid input added no row |
| Production cleanup SQL development verification | Ran the [cleanup SQL template](interactions-production-cleanup.sql) against four newly generated development events with separate synthetic user/location IDs inside an outer transaction. The script verified values/relationships, removed exactly four events and preserved both parents; the outer rollback removed all verification fixtures. Production event IDs were never inserted into development |
| SQL Editor warning clarification | Andrew reported Supabase's destructive-operation/RLS warning before executing cleanup. Reviewed the exact SQL and [PostgreSQL documentation](https://www.postgresql.org/docs/current/sql-createtable.html): `issue52_expected_events` is a session-temporary helper with `ON COMMIT DROP`, so `Run without RLS` applies to this script. The deliberate deletion is restricted to four verified test IDs; application-table RLS is unchanged |
| Production database verification and cleanup | Andrew supplied the production SQL Editor result: `PASS`, `verified_and_deleted_events: 4`, `remaining_owner_events: 0`, `user_preserved: true`, `active_location_preserved: true`. The transaction checks exact event values and owner/location relationships before deletion, then verifies absence and parent preservation |
| Final production API state | After SQL cleanup, Andrew supplied HTTP 200 with `schema_version: "1"`, `interactions: []` and `excluded_location_ids: []`, confirming the deployed API reflects the empty database history |

Development command:

```powershell
.\.venv\Scripts\python.exe backend/verify_interactions.py
```

Observed output:

```text
Fixture owners (synthetic): 7014ebed-966b-4aba-b7c0-f42f5901f4e4, 976ab583-99dc-45cf-8beb-8e9e585e14e9
Fixture locations (synthetic): b6f572c9-ff8c-43fe-908a-106be2d0fc08, 01ce4f6b-fdea-4956-a00f-12015236415d
PASS: Four event types, rating bounds/decimals and append-only repeats persist.
PASS: Invalid input creates no rows; auth, owner history and S3-01 exclusions hold.
PASS: Fresh-client persistence, sanitized failures and both foreign keys verified.
PASS: Interaction changes preserve parent records; user cascade stays owner-scoped.
PASS: Exact synthetic fixtures cleaned and absence verified.
```

Both user/location foreign keys rejected missing parents with PostgreSQL 23503.
Deleting a referenced location was rejected. Deleting an interaction preserved
its user/location; deleting the synthetic owner cascaded only its interactions,
preserving the other owner/event and location. These checks used temporary
fixtures and no existing demo profile or catalog row was changed.

The verifier used the backend's existing environment loading, never printed
credentials and made no environment-file edits. Fresh-client reads establish
committed database persistence, not survival across a hosted revision change.
The original schema permits broader ratings; the versioned API/handoff enforces
S3-01's 1–5 boundary without changing production DDL.

Contracts, safe cleanup and deployed verification steps:
[API guide](../interactions-api.md).

Staging Swagger is `https://lagaw-api-staging-i5kvldluga-as.a.run.app/docs`,
connected to development Supabase `vnpkyvtbupnquvirzlzp`. Production is a
separate API/database and uses a separate token. No staging demo token or saved
Google Cloud credentials were available in the agent session. Andrew executed
the authenticated deployed API checks privately in Swagger and supplied safe
responses; the agent independently read and cleaned development events using
the existing guarded backend configuration. Production database verification
and exact cleanup were executed by Andrew in production SQL Editor, with the
reported result recorded above. No credential value was requested in chat,
printed or added to `.env`.

The production cleanup SQL is a record of this completed, single-use cleanup.
Its four expected events no longer exist; rerunning it intentionally fails
verification before deleting anything. No new permanent table or migration was
created: the expected-events helper is temporary and drops at commit.

Implementation and deployed acceptance are complete. This evidence is published
in [PR #85](https://github.com/relax-mode/lagaw/pull/85); teammate review and merge
remain before issue closure. The implementation
is already reviewed, merged, CI-tested and deployed; this documentation follow-up
changes no application behavior, migration, workflow or environment file.
