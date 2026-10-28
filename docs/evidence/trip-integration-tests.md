# Issue #29 — Trip CRUD database test evidence

- Issue: [#29](https://github.com/relax-mode/lagaw/issues/29).
- Prepared October 28, 2026, from main `95b3ad5`.
- Branch: `test/issue-29-trip-crud`.
- Scope: Trip CRUD, validation and user-trip relationships. Association tests excluded.
- Target: disposable PostgreSQL 17 `lagaw_test` and loopback PostgREST v12.2.3.
- Both hosted Supabase projects are refused. `.env` is unchanged.
- Earlier #29 tests were recovered from the preserved stash and adapted to current
  CI and disposable-only execution. Historical hosted results are not evidence
  of this revised suite; the stash was left intact.

| Check | Observed result |
| --- | --- |
| Offline backend regressions and target guards | 327 passed, 89 database tests deselected in 7.25 seconds; includes 22 disposable-target guard checks |
| Ruff and whitespace checks | `All checks passed!`; `git diff --check` passed |
| PR and teammate review | Pending |
| Database tests in GitHub Actions | Pending |
| Repeat Database run on same commit | Pending |
| JUnit artifact and logs | Pending |
| Merge and post-merge CI | Pending |
| Deployment | Test-only change; no application deployment required |

Local Docker/PostgreSQL/PostgREST executables are unavailable, so real database
execution will be verified through the existing disposable GitHub Actions job.
No hosted database is used as a substitute.

Commands and fixture behavior: [test guide](../trip-integration-tests.md).
