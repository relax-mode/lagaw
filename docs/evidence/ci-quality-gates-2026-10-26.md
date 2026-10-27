# CI quality gates (issue #31), October 26, 2026

Verified with actual GitHub Actions runs. The probe PRs [#69](https://github.com/relax-mode/lagaw/pull/69)–[#72](https://github.com/relax-mode/lagaw/pull/72) were throwaway drafts based on the #31 branch. They were closed without merging after their runs were recorded.

## Branch protection on `main`

Read from `gh api repos/relax-mode/lagaw/branches/main/protection`:

| Setting | Value |
|---|---|
| Required status checks | `Backend - Python`, `Database - PostgreSQL migrations and smoke tests`, `Frontend - Flutter` |
| Require branches to be up to date (strict) | yes |
| Required approving reviews | 1 |
| Dismiss stale approvals | yes |
| Enforce for administrators | yes |
| Force pushes / deletions | blocked / blocked |

## Failing tests fail the pipeline

| Probe | Change | Result |
|---|---|---|
| [#71](https://github.com/relax-mode/lagaw/pull/71), run [40304691471](https://github.com/relax-mode/lagaw/actions/runs/40304691471) | `self.assertTrue(False, "deliberate CI gate failure")` in `backend/test_cors.py` | `Backend - Python` **failed** at "Test backend regressions (offline)" with `AssertionError: False is not true : deliberate CI gate failure`. The PR shows a failing required check. |
| [#72](https://github.com/relax-mode/lagaw/pull/72), run [40304704788](https://github.com/relax-mode/lagaw/actions/runs/40304704788) | `findsNothing` instead of `findsOneWidget` in `frontend/test/widget_test.dart` | `Frontend - Flutter` **failed** at "Test Flutter regressions" (`Lagaw app shell renders (failed)`). The web build step did not run. |

Every deploy job `needs` all three checks. A failed check therefore leaves staging and production deploys skipped, and a red PR cannot satisfy branch protection.

## Path filtering keeps required checks satisfied

| Probe | Changed | Checks run | Checks skipped |
|---|---|---|---|
| [#69](https://github.com/relax-mode/lagaw/pull/69) | `docs/scope-changes.md` | `Detect changed areas` | Backend, Database, Frontend |
| [#70](https://github.com/relax-mode/lagaw/pull/70) | `backend/app/__init__.py` | Detect, Backend, Database | Frontend |
| [#68](https://github.com/relax-mode/lagaw/pull/68) | `.github/workflows/ci.yml` (and others) | all | none |

GitHub reports a job skipped by its `if` condition as successful for branch protection. A failure of the classification job makes every check run.

## Test isolation

- **Backend job.** No database or provider credentials. Tests use mocked HTTP transports, dummy configuration and disabled dotenv loading.
- **Database job.** Only a `postgres:17` service container and a PostgREST container on the runner's loopback address, with test-only credentials (`local_ci_only`).
  - The relationship and association verifiers refuse non-loopback targets in `--ci` mode.
  - `pytest -m db` receives only the loopback URLs. In run [40304682540](https://github.com/relax-mode/lagaw/actions/runs/40304682540) it reported "No database-backed API tests are marked yet" until #29 adds tests.
- **Frontend job.** PR builds no longer receive the production demo token. Tests use injected `MockClient` responses.
- **Pull request runs** never read staging or production configuration. Staging secrets are scoped to the GitHub `staging` environment, which only `main` can use.

## Post-deployment verification

- **Staging** (automatic on `main`): read-only API smoke (`scripts/smoke_staging.py`) and a Pages HTTP check. Browser and isolation acceptance: [staging acceptance evidence](staging-acceptance-2026-10-26.md).
- **Production**: the API smoke requires at least one location from `/locations`, and the Pages check requires an HTTP 200. On October 26, `https://lagaw.pages.dev` loaded live locations from the production API in a headless browser (screenshot in the staging acceptance evidence).

## Pipeline optimization

Before/after measurements are in [the pipeline metrics log](../pipeline-metrics.md#sprint-3-path-filtered-pull-request-checks-31). Incidents are in [the incident log](../incident-log.md).
