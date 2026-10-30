# CI/CD Best Practices

Improvements to the Cloudflare Pages pipeline in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) that are known and deliberately **not done yet**. The pipeline works without them; each item says why it matters. Revisit during Sprint 2 and 3, and record anything adopted in the [sprint log](sprint-log.md).

## Security

- **Finish scoping secrets to GitHub Environments (highest priority).** Repository-level secrets can be read by any workflow on any branch, so anyone with push access could edit a workflow on a branch and print the token. The `staging` and `production` environments, both limited to protected branches, now hold each environment's demo token; the production one was added October 26 under #58. `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are still shared repository secrets. Create a second Cloudflare Pages token, store one in each environment (the token holder must do this in the Cloudflare dashboard), and then delete the repository copies and the unused repository `TRIP_DEMO_TOKEN`.
- **Scope deployer identities per environment.** Both deployer service accounts trust the whole `github` Workload Identity pool by repository. After the first successful environment-based production deploy, bind each deployer to `attribute.environment/<env>` only. The commands are in the [AI CI/CD evidence](evidence/ai-ci-cd-2026-10-26.md#post-merge-identity-scoping).
- **Pin third-party actions to commit SHAs.** The workflow uses version tags (`@v2`, `@v4`), which can be moved by the action's owner. Pin to full SHAs and let Dependabot propose updates. The pinning change is in review in a separate PR (not yet on `main`).
- **Keep the deploy token narrow.** Scope is already limited to Cloudflare Pages edit. Cloudflare cannot scope it to a single project, so rotate it when a team member leaves.
- **Keep secrets out of the Flutter web bundle.** Everything compiled into a web build is public. Pass the backend URL with `--dart-define`; never compile in the DeepSeek key or any other secret. **Known exception:** the Trip demo token is still compiled into both web builds (`ci.yml`, staging and production web build steps). Hosted backends no longer accept it, but it is still readable in the public bundle. See the open risk in [`PIPELINE.md`](../PIPELINE.md#open-risks).

## Reliability

- **Pin the Flutter version.** `channel: stable` lets a new Flutter release change or break the build with no change in this repository. Pin `flutter-version` in `ci.yml`.
- **Keep smoke checks representative.** `scripts/smoke_deployed.py` checks locations, Trip authentication and ownership, the extraction route, and exact CORS on staging and production after every deploy. It creates no trips or interaction events; the first sign-in can create the smoke profile. Browser-level writes were verified manually on staging ([staging acceptance](evidence/staging-acceptance-2026-10-26.md)).
- **Keep the rollback procedure current.** Cloud Run revision rollback and Cloudflare Pages promotion steps are documented in [`PIPELINE.md`](../PIPELINE.md). Rehearse both before Demo Day. The full rollback runbook and helper are in review in a separate PR (not yet on `main`). No rollback drill has been performed; it is pending explicit authorization.
- **Do not rely on the path filter to recover from failures.** If a deploy fails, or secrets are added later, nothing redeploys until the affected area changes again. Use the manual `workflow_dispatch` run on `main`, which redeploys staging and both production jobs (see [`PIPELINE.md`](../PIPELINE.md#continuous-deployment)). Rerunning the failed main push run is the other option.

## Pipeline efficiency

- **Record comparable measurements.** The [pipeline metrics log](pipeline-metrics.md) records the PostgreSQL job baseline and the pip-cache result after this workflow change. Keep future optimizations tied to actual run IDs and timings.
- **Cache more aggressively if builds slow down.** Flutter, pub, Docker, and pip caches are enabled. Measure later build time before adding more caching complexity.

## Platform risks

- **Cloudflare is merging Pages into Workers.** Wrangler 4.151 tried to create the project through Workers and only created classic Pages with `--force`. Classic Pages works today and is fine for this semester, but do not build long-term on it.
- **The `lagaw` Pages project lives on a personal Cloudflare account.** If that person is unavailable, the team cannot manage it. Move it to a shared account or add teammates as members.
