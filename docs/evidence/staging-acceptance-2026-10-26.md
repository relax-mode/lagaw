# Staging acceptance (issue #30), October 26, 2026

These checks were performed by CyGray's agent session against the deployed environments. No credential values were printed. The staging demo token and Supabase credentials were read from Secret Manager into shell variables and passed to the checks through the environment.

## Automated staging deployment

| Run | Commit | Result |
|---|---|---|
| [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) | `4c844c4` | Staging backend deploy, API smoke, **staging Flutter Web deploy and web smoke** all succeeded. |
| [40207393473](https://github.com/relax-mode/lagaw/actions/runs/40207393473) | `7c86a50` (latest `main`) | Staging backend deploy and API smoke succeeded. The web was skipped because no frontend files changed. |

Both runs started automatically on a push to `main`, after the three required checks passed. The current staging revision is `lagaw-api-staging-00011-hth`.

## Browser acceptance

The checks used headless Chromium (Playwright) at a 412×915 phone viewport.

### Staging: `https://staging.lagaw.pages.dev`

- The page loaded (title `Lagaw Bacolod`). The app requested `GET /locations` from `lagaw-api-staging-i5kvldluga-as.a.run.app` and received 200 in the browser, so the staging CORS policy admits the staging origin.
- Screenshot: [staging-acceptance-2026-10-26.png](img/staging-acceptance-2026-10-26.png).
- **Write from the staging origin.** A `fetch` executed inside the page, so with origin `https://staging.lagaw.pages.dev`:
  - `POST /api/v1/trips` with the staging demo token returned **201**, creating trip `98a20e25-4c4d-464e-a9d0-020334a1f02d` titled `staging-isolation-20261026`.
  - `GET` of the same trip returned **200**.

### Production: `https://lagaw.pages.dev`

- The page loaded. It requested `GET /locations` from `lagaw-api-663710289405.asia-southeast1.run.app` (production) and received 200.
- Screenshot: [production-check-2026-10-26.png](img/production-check-2026-10-26.png).
- This check was read-only; nothing was written to production.

## Database isolation

| Database | Rows with id `98a20e25-…` after the staging write |
|---|---|
| Development Supabase project (staging secrets `STAGING_SUPABASE_*:2`) | **1** |
| Production Supabase project (secrets `SUPABASE_*`) | **0** |

The staging write reached only the development database.

**Cleanup.** A `DELETE` from the staging origin returned **204**. The follow-up `GET` returned **404**, and the development query then returned **0** rows.

## Production unchanged

The production Cloud Run service still serves revision `lagaw-api-00007-hfl` at 100% traffic, the same revision recorded before the staging work. The production page loads its data from the production API.

## Configuration separation (names only)

| Service | Env names | Secret references |
|---|---|---|
| `lagaw-api` | `CORS_ALLOWED_ORIGINS`, `TRIP_DEMO_USER_ID`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `TRIP_DEMO_TOKEN` | `SUPABASE_URL:latest`, `SUPABASE_SERVICE_ROLE_KEY:latest`, `TRIP_DEMO_TOKEN:1` |
| `lagaw-api-staging` | the same names | `STAGING_SUPABASE_URL:2`, `STAGING_SUPABASE_SERVICE_ROLE_KEY:2`, `STAGING_TRIP_DEMO_TOKEN:1` |

The services use separate runtime service accounts (`lagaw-api` and `lagaw-api-staging-runtime`) and separate Workload Identity providers (`github` and `github-staging`; the latter is restricted to the `staging` environment).

## Credential exposure check

Logs of runs 40163792050 and 40207393473 were searched for Supabase secret-key prefixes, JWT prefixes and bearer tokens. The only matches were Secret Manager **references** (for example `SUPABASE_SERVICE_ROLE_KEY=STAGING_SUPABASE_SERVICE_ROLE_KEY:2`), not values. GitHub masking (`***`) appears where secrets are used.

The Flutter bundle's demo token is public by design (see [`docs/staging.md`](../staging.md)). The staging token is distinct from production's and is scoped to a synthetic profile.

## Findings for follow-up

- **Deployer trust is pool-wide.** Both deployer service accounts (`gh-deployer` and `lagaw-api-staging-deployer`) grant `roles/iam.workloadIdentityUser` to `principalSet://…/workloadIdentityPools/github/attribute.repository/relax-mode/lagaw`, which matches tokens from *either* provider in the pool. Both providers still require `refs/heads/main`. However, a staging-environment job could impersonate the production deployer, and any `main` job could impersonate the staging deployer.
  - Tighten this by binding the staging deployer to `attribute.environment/staging` only.
  - After a GitHub `production` environment exists (#58), bind the production deployer to `attribute.environment/production`. This needs `attribute.environment` added to the `github` provider's mapping.
  - Tracked in #58 because it must be rolled out together with the workflow change; an IAM change alone would break the current deploy path.
- **Missing remote image.** A remote card image (`/photo-1548625361-16800b352a94`) returns 404 on both staging and production. This is a frontend content issue, not an environment one; reported for the frontend owner.
