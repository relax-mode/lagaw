# Issue #52 — interaction persistence evidence

- Issue: [#52](https://github.com/relax-mode/lagaw/issues/52).
- Prepared October 28, 2026, from main `17d93d9`.
- Branch: `feat/s3-07-user-interactions`.
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
| PR, teammate review and merged commit | [PR #84](https://github.com/relax-mode/lagaw/pull/84) opened; teammate review and merge pending |
| Deployed staging acceptance | Pending new endpoint deployment; local app against development DB is not deployed acceptance |
| Production/deployed acceptance | Pending development/staging acceptance and reviewed release |

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
