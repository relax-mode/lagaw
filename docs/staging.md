# Staging Environment

Lagaw staging runs the FastAPI service and Flutter Web against the existing development Supabase project. It uses separate Cloud Run service identity, deployment identity, Secret Manager secrets, and a Flutter bundle built with the staging API URL. Production service configuration and production Workload Identity Federation remain separate.

## Services and configuration

| Component | Staging configuration |
|---|---|
| GCP project and region | `relax-mode-lagaw`, `asia-southeast1` |
| API | Cloud Run service `lagaw-api-staging`; `https://lagaw-api-staging-i5kvldluga-as.a.run.app` |
| Runtime identity | `lagaw-api-staging-runtime@relax-mode-lagaw.iam.gserviceaccount.com` |
| Database | Development Supabase project `vnpkyvtbupnquvirzlzp` |
| API secrets | Secret Manager `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY` and `STAGING_DEEPSEEK_API_KEY` (DeepSeek key holder: Kyle) |
| Trip demo | Dedicated synthetic profile `16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c`; Secret Manager `STAGING_TRIP_DEMO_TOKEN:1` |
| GitHub staging environment | Secret `STAGING_TRIP_DEMO_TOKEN`; variable `STAGING_TRIP_DEMO_USER_ID` |
| Web | Cloudflare Pages project `lagaw`, branch `staging`; expected branch URL `https://staging.lagaw.pages.dev` |
| Browser origin | `https://staging.lagaw.pages.dev` |

The staging runtime service account has Secret Accessor on its two Supabase secrets, its separate Trip demo token and the staging DeepSeek key. The automated deployment uses its own service account and a separate Workload Identity provider constrained to `relax-mode/lagaw`, `refs/heads/main`, and the GitHub `staging` environment. The workflow pins the Supabase secrets to version `2` and the Trip token to version `1`; it never prints secret values. The matching token is stored in the GitHub `staging` environment and supplied only to the staging build and checks. The compiled Flutter token is public, as in the existing demo design; the profile contains synthetic data only. Production's demo token is separate.

The database project is the development project, separate from production project `zjnuqqtbapbpudsjbpif`. Staging writes therefore target development data. CI's disposable PostgreSQL service remains independent and CI tests do not use either Supabase project.

## Deployment controls and status

The workflow in `.github/workflows/ci.yml` starts staging deployment after the Backend, Database, and Frontend checks pass for relevant pushes to `main`. Backend changes deploy the staging API; frontend or deployment workflow changes build and deploy the staging web app. After staging and its smoke checks pass, the same commit is promoted to production automatically (see [`PIPELINE.md`](../PIPELINE.md#continuous-deployment)). Manual dispatch on `main` is a production recovery redeploy and does not touch staging. Pull requests run checks only and do not publish Pages previews.

Staging deployment is enabled by repository variable `STAGING_DEPLOY_ENABLED=true`. As checked October 25, 2026, the GitHub `staging` environment is restricted to protected branches and has no required-reviewer rule. Earlier setup required `aranxshx` approval; that historical configuration is recorded in the sprint log. Qualifying main pushes run CI and then apply the current environment protection rules. The recovery did not change these rules.

On October 25, the staging API was configured with its dedicated demo settings on revision `lagaw-api-staging-00005-pkz`. Authenticated Trip create/list/retrieve/update/delete passed, and a direct development-database read confirmed the temporary trip persisted there before exact cleanup. Production revision `lagaw-api-00007-hfl` stayed unchanged. The latest Pages CI attempts failed authentication; Kyle subsequently replaced the GitHub Cloudflare token, with secret metadata confirming the update. Reviewed main run [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) then deployed and smoke-tested both the staging API and staging Pages with the replacement token. See the [investigation and recovery evidence](evidence/staging-incident-2026-10-25.md). On October 26, browser acceptance passed: a write from the staging origin reached only the development database, and production stayed on `lagaw-api-00007-hfl`. See the [staging acceptance evidence](evidence/staging-acceptance-2026-10-26.md).

Wrangler's saved OAuth session can manage Pages, but a local `.env` Cloudflare token can override it. To check the saved login without loading repository dotenv files, run `npx --no-install wrangler whoami --cwd "$env:TEMP"` from PowerShell. The saved OAuth session does not have API-token management permission and must not be copied into GitHub as a durable CI credential. Replace `CLOUDFLARE_API_TOKEN` directly in GitHub with an account-scoped Cloudflare Pages Edit token; verify the existing account ID matches the project owner. Both production and staging currently use that repository secret.

## Deploying the recovery and retrying staging

Merge the reviewed recovery PR after its required CI checks pass. Its workflow change qualifies both the staging API and web app for deployment on the resulting `main` push. This applies the new staging token settings, builds Flutter with the matching token, and checks both locations and Trip authentication/CORS before publishing Pages.

If that new main push run fails after the Cloudflare token has been replaced, identify the run for the recovery merge commit and retry its failed jobs:

```powershell
gh run list --repo relax-mode/lagaw --workflow ci.yml --branch main --event push --limit 5
gh run rerun <recovery-main-push-run-id> --failed --repo relax-mode/lagaw
gh run watch <recovery-main-push-run-id> --exit-status --repo relax-mode/lagaw
```

A rerun uses the original run's commit and workflow. Rerunning `40098046876` would still use the older staging build that omits the Trip token, so it cannot deliver this workflow fix. Do not use `gh workflow run ci.yml` for staging recovery: manual dispatch redeploys production only.

## Verification

After merging the reviewed workflow to `main` and satisfying any current staging environment protection rules:

1. Confirm a successful `Deploy - Staging` job after the three required CI jobs.
2. Confirm `scripts/smoke_deployed.py staging` passes. It requires:
   - a nonempty location response;
   - unauthenticated Trips returning 401 and authenticated Trips returning 200, with owner filtering;
   - an extraction request with a blank prompt returning 422 (rejected before any provider call);
   - exact staging CORS headers.

   It never writes data, and it rejects URLs outside the staging allowlist before sending credentials.
3. Open `https://staging.lagaw.pages.dev`, confirm the page loads, then exercise a staging write and verify the record in the development database only.
4. Confirm production service `lagaw-api` and `https://lagaw.pages.dev` remain healthy.

The October 26 results for these steps, including the run URLs, browser screenshots, the development-only write and its cleanup, are recorded in the [staging acceptance evidence](evidence/staging-acceptance-2026-10-26.md). Repeat the steps after any change to staging identities, secrets or hosting.

## Secret rotation

Add a new Secret Manager version for each rotated staging credential, update the pinned version numbers in the `Deploy backend to staging Cloud Run` step of `.github/workflows/ci.yml`, and deploy staging through a protected push to `main`. For the Trip demo token, also update the matching `STAGING_TRIP_DEMO_TOKEN` secret in the GitHub `staging` environment so the backend, Flutter bundle, and smoke check agree. Verify the API smoke check before disabling an older version. Do not paste values into the repository, issue, or sprint log.

## Rollback

For the API, list staging revisions and route traffic to a known-good revision:

```sh
gcloud run revisions list --service lagaw-api-staging --project relax-mode-lagaw --region asia-southeast1
gcloud run services update-traffic lagaw-api-staging --project relax-mode-lagaw --region asia-southeast1 --to-revisions <known-good-revision>=100
```

For the web app, promote a known-good staging deployment in the Cloudflare Pages dashboard. Keep the failed deployment and commit IDs with the incident notes.
