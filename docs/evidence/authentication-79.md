# #79 authentication verification evidence

## October 29, 2026 — implementation preparation

- Andrew requested backend issue #79 only; Flutter authentication stays in #80.
- Reread approved pitch/course requirements, backend ownership, database,
  integration-test and staging documentation. Fetched `origin`: local main and
  origin/main both `e630759`; zero commits ahead/behind. No pull was required.
- Created `feat/79-supabase-auth-ownership`; preserved the pre-existing untracked
  root `test-results/` directory. Private `.env` was not opened or edited.
- Prepared the [identity/session/environment contract](../authentication.md).
  Andrew requested a handoff for Roel and Kyle; their agreement is pending.
- Added Supabase Auth-server verification plus issuer/audience/lifetime/role/
  subject checks, explicit idempotent profile links and owner-scoped integration.
  Retained demo access requires explicit non-production process configuration.
- Added an additive migration: existing demo profiles, trips, items and events
  stay intact and unassigned. No hosted migration or environment setting has
  been changed. Development project is `vnpkyvtbupnquvirzlzp`; production is
  `zjnuqqtbapbpudsjbpif`.
- First full offline run after the new Auth tests: **693 passed, 106 database
  tests deselected**, 13.29 seconds. Subsequent smoke/verifier changes require a
  final validation run before commit. This is local/offline evidence only.
- Docker/PostgreSQL are unavailable on the current PATH. Disposable Database CI
  is required; no hosted database is used as a substitute. The available GitHub
  CLI currently has no authenticated host; Andrew was asked to log in privately
  so a draft PR and CI evidence can be prepared. No login code/token was requested.
- Final local validation: **719 passed, 106 database tests deselected**, 13.52
  seconds; `python -m pytest -q -c backend/pytest.ini backend -m "not db"`.
  `ruff check backend scripts/smoke_deployed.py`, Python compile checks and
  `git diff --check` passed. Actionlint **1.7.12** validated the scoped workflow
  change successfully. The AI evaluation passed 27/27 extraction cases, 10/10
  content cases and 84/84 extraction field checks; comparison reported no metric
  regression against the committed baseline. Reports remain in ignored
  `backend/test-results/`, not the user's existing root results directory.
- The existing Supabase CLI project-ref file names the development project;
  only that non-secret project reference was inspected. No CLI link, database
  migration, Auth setting, secret or hosted deployment was changed.
- Committed the implementation as [`91929f1`](https://github.com/relax-mode/lagaw/commit/91929f1)
  and pushed `feat/79-supabase-auth-ownership`. A draft PR can be prepared from
  [the published branch](https://github.com/relax-mode/lagaw/pull/new/feat/79-supabase-auth-ownership).
  Git push used the existing Git authentication; the GitHub CLI still needs a
  private login before it can create the PR and inspect Actions. No PR, CI run,
  review, merge or deployment is claimed by this branch publication.

## Required evidence before completion

| Requirement | Status |
| --- | --- |
| Final offline lint/regression/AI evaluation | Passed locally; 719 offline tests, no AI regression |
| Disposable migration + real PostgreSQL/PostgREST Auth mapping/isolation tests | Pending CI |
| Roel agrees #80 token/confirmation/refresh contract | Handoff prepared; agreement pending |
| Kyle agrees/configures development Auth + environment smoke accounts | Handoff prepared; confirmation pending |
| Development migration and two-account verified acceptance | Not run |
| Candidate deployed staging acceptance, with safe result links | Not run |
| Reviewed PR, required CI and merge | Pending |
| Production migration/configuration after development acceptance | Not performed |
| Deployed production acceptance and cleanup | Not run |

Do not mark #79 complete from offline tests alone. Add actual commit/PR/run links,
safe results, migration versions and provenance as these steps occur. Never add
passwords, access/refresh tokens, API keys or email confirmation links.
