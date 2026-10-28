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
| PR and teammate review | [PR #82](https://github.com/relax-mode/lagaw/pull/82) approved by CyGray on final commit `cdffd1f` and merged October 28, 2026, at 08:36:38 UTC as `ea436ab` |
| Database tests in GitHub Actions | [Run 40655158376, attempt 1](https://github.com/relax-mode/lagaw/actions/runs/40655158376/attempts/1): all required checks passed; **89 passed, 327 deselected in 5.19 seconds** |
| Repeat Database run on same commit | [Attempt 2](https://github.com/relax-mode/lagaw/actions/runs/40655158376/attempts/2), still commit `4c51dd8`: **89 passed, 327 deselected in 3.46 seconds**; all required checks passed |
| JUnit artifact and logs | [First JUnit artifact](https://github.com/relax-mode/lagaw/actions/runs/40655158376/artifacts/12801990449), [repeat artifact](https://github.com/relax-mode/lagaw/actions/runs/40655158376/artifacts/12800958028); [first Database log](https://github.com/relax-mode/lagaw/actions/runs/40655158376/job/122704346596), [repeat log](https://github.com/relax-mode/lagaw/actions/runs/40655158376/job/122704978696) |
| Merge and post-merge CI | [Main run 40658036214](https://github.com/relax-mode/lagaw/actions/runs/40658036214) completed successfully: required Backend, Database and Frontend checks passed; **89 database tests passed, 327 deselected in 2.77 seconds** |
| Post-merge JUnit and database log | [JUnit artifact](https://github.com/relax-mode/lagaw/actions/runs/40658036214/artifacts/12802900913), [Database log](https://github.com/relax-mode/lagaw/actions/runs/40658036214/job/122713817694) |
| Deployment | Automatic [staging](https://github.com/relax-mode/lagaw/actions/runs/40658036214/job/122714439484), [production API](https://github.com/relax-mode/lagaw/actions/runs/40658036214/job/122715702558) and [production web](https://github.com/relax-mode/lagaw/actions/runs/40658036214/job/122716123357) deployment jobs, including their smoke checks, all passed |

Local Docker/PostgreSQL/PostgREST executables are unavailable, so real database
execution will be verified through the existing disposable GitHub Actions job.
No hosted database is used as a substitute.

The first downloaded JUnit report confirms 89 tests, zero failures, zero errors
and zero skips. Both real runs completed all per-test cleanup checks. A separate
local probe with both disposable-service settings removed exited 1 with the safe
hosted-target refusal message, confirming missing configuration cannot pass as a
skip. CI runs pytest directly with no exit-code suppression, so test/setup/cleanup
failures fail the required Database check. Both PR attempts skipped staging and
production deployment. CyGray subsequently approved the final PR commit, #82
merged, and the post-merge required checks passed. The earlier statement that
this merge would skip deployment was incorrect: changing `ci.yml` triggers both
deployment paths under the existing classifier. The automatic staging/production
run subsequently completed successfully, including deployment smoke checks. A
documentation-only follow-up records the observed results and corrects that
statement without changing application code, tests, schema or deployment policy.

Commands and fixture behavior: [test guide](../trip-integration-tests.md).
