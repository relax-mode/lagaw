# CI/CD Pipeline

Lagaw uses one GitHub Actions workflow for pull request checks and deployments. Every deployment waits for the backend, frontend, and disposable PostgreSQL checks for the same commit.

## Workflow

```mermaid
flowchart TD
  Trigger[Pull request, main push, or manual run] --> Backend[Backend: Ruff, compile, pytest]
  Trigger --> Frontend[Flutter: tests, analysis, web build]
  Trigger --> Database[Disposable PostgreSQL: migrations and relationship checks]
  Backend --> Gate{All checks pass?}
  Frontend --> Gate
  Database --> Gate
  Gate -->|Same-repository PR, frontend changes| Preview[Cloudflare Pages preview + HTTP smoke test]
  Gate -->|manual dispatch on main| ProductionWeb[Cloudflare Pages production + HTTP smoke test]
  Gate -->|manual dispatch on main| ProductionAPI[Cloud Run production + API smoke test]
  Gate -->|main push, staging enabled + reviewer approval| Staging[Staging Cloud Run + Pages + smoke checks]
```

## Pull requests and deployment gates

The `Lagaw CI` workflow runs on every pull request, push to `main`, and manual dispatch. Its PR checks are:

- `Backend - Python`: Ruff, Python compilation, and `python -m pytest -v`. Pytest discovers the current `unittest.TestCase` suite and future pytest tests. The current 69-test suite includes Trip HTTP CRUD checks using a mocked Supabase Data API.
- `Database - PostgreSQL migrations and smoke tests`: migrations and SQLAlchemy relationship checks against a disposable PostgreSQL service. The CI credentials are test-only.
- `Frontend - Flutter`: Flutter tests, analysis, and a web build.

Both production deployment jobs depend on all three checks, so a failed check prevents either deploy. Production API and Pages deployments run only after manually dispatching the workflow on `main`; each deploys the current `main` commit and performs its smoke check. Main pushes do not deploy production. Google Cloud authentication uses Workload Identity Federation restricted to `main`.

Pull requests run checks only; they do not publish Pages previews or production deployments. This prevents PR bundles from calling production and keeps production releases manual. The Cloud Run production deploy smoke check requests `/locations?limit=1` and requires at least one returned location.

Main branch protection now requires one approving review and the three CI checks above, with stale approvals dismissed and strict up-to-date checks enabled. Force pushes and branch deletion are disabled. Deploy jobs are not required checks because production deploys run only by manual dispatch and staging deploys follow a `main` push after required environment approval.

## Environment boundaries

Production Cloud Run reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from Google Secret Manager. GitHub Actions stores only non-secret GCP identifiers as repository variables; its Cloudflare deploy credentials are repository Actions secrets.

**PR previews are not yet data-isolated.** The Flutter web build currently uses the repository-level `API_BASE_URL`, which points to the production backend. A preview therefore calls production until the staging environment in [issue #30](https://github.com/relax-mode/lagaw/issues/30) is configured. Do not treat a Pages preview as a staging acceptance check before that work is complete.

The API tests use mocked HTTP transports and do not verify writes through a live Supabase Data API. The disposable PostgreSQL job verifies migrations and SQLAlchemy relationships separately. See [issue #29](https://github.com/relax-mode/lagaw/issues/29) for the remaining database-backed API test acceptance.

## Rollback

For Cloud Run, identify a known-good revision and route all traffic to it:

```sh
gcloud run revisions list --service lagaw-api --project relax-mode-lagaw --region asia-southeast1
gcloud run services update-traffic lagaw-api --project relax-mode-lagaw --region asia-southeast1 --to-revisions <known-good-revision>=100
```

For Cloudflare Pages, use the Cloudflare dashboard to promote a known-good deployment. Keep the failed deployment and commit IDs with the incident notes; do not delete deployment history.

## Metrics

The pipeline optimization measurements, run links, and before/after durations are recorded in [the pipeline metrics log](docs/pipeline-metrics.md).
