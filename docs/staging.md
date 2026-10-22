# Staging Environment

Lagaw staging runs the FastAPI service and Flutter Web against the existing development Supabase project. It uses separate Cloud Run service identity, deployment identity, Secret Manager secrets, and a Flutter bundle built with the staging API URL. Production service configuration and production Workload Identity Federation remain separate.

## Services and configuration

| Component | Staging configuration |
|---|---|
| GCP project and region | `relax-mode-lagaw`, `asia-southeast1` |
| API | Cloud Run service `lagaw-api-staging`; `https://lagaw-api-staging-i5kvldluga-as.a.run.app` |
| Runtime identity | `lagaw-api-staging-runtime@relax-mode-lagaw.iam.gserviceaccount.com` |
| Database | Development Supabase project `vnpkyvtbupnquvirzlzp` |
| API secrets | Secret Manager `STAGING_SUPABASE_URL` and `STAGING_SUPABASE_SERVICE_ROLE_KEY` |
| Web | Cloudflare Pages project `lagaw`, branch `staging`; expected branch URL `https://staging.lagaw.pages.dev` |
| Browser origin | `https://staging.lagaw.pages.dev` |

The staging runtime service account has Secret Accessor on the two staging secrets only. The automated deployment uses its own service account and a separate Workload Identity provider constrained to `relax-mode/lagaw`, `refs/heads/main`, and the GitHub `staging` environment. The workflow currently pins both staging secrets to version `2`; it never prints secret values.

The database project is the development project, separate from production project `zjnuqqtbapbpudsjbpif`. Staging writes therefore target development data. CI's disposable PostgreSQL service remains independent and CI tests do not use either Supabase project.

## Deployment controls and status

The workflow in `.github/workflows/ci.yml` deploys staging only after the Backend, Database, and Frontend checks pass. Main pushes deploy the API and/or web app when their source paths change; a manual dispatch on `main` redeploys both. Staging web is built separately with the staging Cloud Run URL. Pull requests run checks without publishing Pages previews.

Staging deployment is guarded by repository variable `STAGING_DEPLOY_ENABLED`. It is currently `false`. Before enabling it, create the GitHub `staging` environment and set at least one required reviewer; the reviewer identity is still awaiting the team's choice. Keep the variable false until that environment protection is in place. The job then pauses for environment approval before using deploy credentials.

The Cloud Run staging API has been deployed and its `/locations?limit=1` smoke check returned one development location. The Pages staging branch has not yet been deployed, so `https://staging.lagaw.pages.dev` is not available until the protected workflow runs successfully. Issue #30 remains open until web availability, database isolation, and reviewed CI deployment are verified.

## Verification

After enabling the protected environment and merging the reviewed workflow to `main`:

1. Confirm a successful `Deploy - Staging` job after the three required CI jobs.
2. Confirm the API smoke step returns at least one location from development data.
3. Open `https://staging.lagaw.pages.dev`, confirm the page loads, then exercise a staging write and verify the record in the development database only.
4. Confirm production service `lagaw-api` and `https://lagaw.pages.dev` remain healthy.

The GitHub Actions run URL, staging browser/API results, and the development-only write verification should be linked from issue #30 before closing it.

## Secret rotation

Add a new Secret Manager version for each rotated staging credential, update the pinned version numbers in the `Deploy backend to staging Cloud Run` step of `.github/workflows/ci.yml`, and deploy staging through the protected workflow. Verify the API smoke check before disabling an older version. Do not paste values into the repository, issue, or sprint log.

## Rollback

For the API, list staging revisions and route traffic to a known-good revision:

```sh
gcloud run revisions list --service lagaw-api-staging --project relax-mode-lagaw --region asia-southeast1
gcloud run services update-traffic lagaw-api-staging --project relax-mode-lagaw --region asia-southeast1 --to-revisions <known-good-revision>=100
```

For the web app, promote a known-good staging deployment in the Cloudflare Pages dashboard. Keep the failed deployment and commit IDs with the incident notes.
