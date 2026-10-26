# CI/CD Pipeline

Lagaw uses one GitHub Actions workflow for pull request checks and deployments. Every deployment waits for the backend, frontend, and disposable PostgreSQL checks for the same commit.

## Workflow

```mermaid
flowchart TD
  Trigger[Pull request, main push, or manual run] --> Changes[Detect changed areas]
  Changes -->|backend changed, or not a PR| Backend[Backend: Ruff, compile, pytest -m 'not db']
  Changes -->|frontend changed, or not a PR| Frontend[Flutter: analysis, tests, web build]
  Changes -->|backend/database changed, or not a PR| Database[Disposable PostgreSQL + PostgREST: migrations, relationships, association API, pytest -m db]
  Backend --> Gate{All checks pass?}
  Frontend --> Gate
  Database --> Gate
  Gate -->|manual dispatch on main| ProductionWeb[Cloudflare Pages production + HTTP smoke test]
  Gate -->|manual dispatch on main| ProductionAPI[Cloud Run production + API smoke test]
  Gate -->|main push, staging enabled + environment rules| Staging[Staging Cloud Run + Pages + smoke checks]
```

## Pull requests and deployment gates

The `Lagaw CI` workflow runs on every pull request, push to `main`, and manual dispatch. It starts with `Detect changed areas`, which classifies the changed paths. On pull requests each check runs only when its area changed; pushes and manual runs always run every check. A check skipped this way still satisfies its required status check, and if classification itself fails, every check runs. Any change to `.github/workflows/ci.yml` runs all checks.

| Check | Runs on a PR when these change | What it does | Why it exists |
|---|---|---|---|
| `Backend - Python` | `backend/**`, the committed AI evaluation baseline | Ruff (pinned in `requirements-dev.txt`, with inline PR annotations), `compileall`, `pytest -m "not db"`: every offline regression, including mocked Trip CRUD, mocked DeepSeek extraction and the evaluation fixtures | Fast correctness feedback. No network services, databases or paid provider calls. |
| `Database - PostgreSQL migrations and smoke tests` | `backend/**`, `supabase/**`, `scripts/check_database.py` | Disposable PostgreSQL 17: migrations and schema smoke, SQLAlchemy relationship checks, the itinerary association API against a disposable PostgREST, and `pytest -m db` database-backed API tests | Proves schema and persistence behavior against a real database that no other environment shares. Credentials are test-only. |
| `Frontend - Flutter` | `frontend/**`, `package.json`, `package-lock.json` | `flutter analyze` (cheap, first), `flutter test`, release web build | Catches Dart errors and UI regressions, and proves the web bundle builds. PR builds receive no production token. |

Every job has a `timeout-minutes` limit. A new commit cancels an outdated PR run. Main and manual runs each get their own concurrency group, so a deploy waiting in one run cannot queue or cancel checks for later commits (see [INC-2](docs/incident-log.md#inc-2-main-runs-blocked-behind-a-staging-approval)). The deploy jobs serialize through their own concurrency groups.

Both production deployment jobs depend on all three checks, so a failed check prevents either deploy. Production API and Pages deployments run only after manually dispatching the workflow on `main`; each deploys the current `main` commit and performs its smoke check. Main pushes do not deploy production. Google Cloud authentication uses Workload Identity Federation restricted to `main`. **Known conflict:** manual production deployment contradicts the approved pitch and the course requirement that every merge to `main` deploy without manual steps. [#58](https://github.com/relax-mode/lagaw/issues/58) replaces it with automatic promotion after staging.

Pull requests run checks only; they do not publish Pages previews or production deployments. Main pushes automatically deploy staging for relevant backend, frontend, or deployment workflow changes after all three checks and the current `staging` environment protection rules. The staging web app is built separately against the staging Cloud Run URL with its own demo token and deployed to the Cloudflare Pages `staging` branch. Its read-only API smoke check covers locations, Trip authentication/ownership, and staging CORS; the Pages check verifies an HTTP response. Manual dispatch on `main` is reserved for production deployment. The Cloud Run production smoke check requests `/locations?limit=1` and requires at least one returned location.

Main branch protection requires one approving review and the three CI checks above, with stale approvals dismissed and strict up-to-date checks enabled. The rules also apply to administrators. Force pushes and branch deletion are disabled. Deployment jobs are not required checks: staging follows qualifying pushes to `main` and production runs only after manual dispatch.

## Environment boundaries

Production Cloud Run reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from Google Secret Manager. GitHub Actions stores only non-secret GCP identifiers as repository variables; its Cloudflare deploy credentials are repository Actions secrets.

Staging uses the existing development Supabase project and separate Cloud Run service credentials, synthetic demo profile, and Trip demo token. The workflow pins staging Secret Manager versions and a separate runtime service account can access only the staging secrets. The matching demo token is a GitHub `staging` environment secret, distinct from the production token. A separate Workload Identity provider is restricted to this repository's `main` branch and the GitHub `staging` environment; production identity configuration is unchanged. Automatic staging deployments are enabled; as checked October 25, the environment restricts deployments to protected branches without a required-reviewer rule. See [the staging runbook](docs/staging.md) for service boundaries and remaining verification.

The backend job's API tests use mocked HTTP transports and do not verify writes through a live Supabase Data API. The Database job covers persistence: tests marked `db` run there against disposable PostgreSQL and PostgREST, and never against development, staging or production. [`docs/regression-tests.md`](docs/regression-tests.md) describes the marker contract. Database-backed Trip CRUD fixtures are tracked in [issue #29](https://github.com/relax-mode/lagaw/issues/29).

## Rollback

For Cloud Run, identify a known-good revision and route all traffic to it:

```sh
gcloud run revisions list --service lagaw-api --project relax-mode-lagaw --region asia-southeast1
gcloud run services update-traffic lagaw-api --project relax-mode-lagaw --region asia-southeast1 --to-revisions <known-good-revision>=100
```

For Cloudflare Pages, use the Cloudflare dashboard to promote a known-good deployment. Keep the failed deployment and commit IDs with the incident notes; do not delete deployment history.

## Metrics and incidents

The weekly metrics, optimization measurements, run links, and before/after durations are recorded in [the pipeline metrics log](docs/pipeline-metrics.md). Regenerate a week's figures with `python scripts/pipeline_metrics.py --since <YYYY-MM-DD> --until <YYYY-MM-DD> --jobs`. Broken builds and failed deploys on `main` or deployed environments are recorded, with postmortems, in [the incident log](docs/incident-log.md).
