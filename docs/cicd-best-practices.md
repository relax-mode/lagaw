# CI/CD Best Practices

Improvements to the Cloudflare Pages pipeline in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) that are known and deliberately **not done yet**. The pipeline works without them; each item says why it matters. Revisit during Sprint 2 and 3, and record anything adopted in the [sprint log](sprint-log.md).

## Security

- **Scope secrets to GitHub Environments (highest priority).** Repository-level secrets can be read by any workflow on any branch, so anyone with push access could edit a workflow on a branch and print the token. Create a `production` Environment restricted to the `main` branch and move `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` there; add a `preview` Environment for pull-request deploys. This also satisfies the rubric's "secrets scoped per environment" criterion ([official instructions](official-instructions.md), Section 8).
- **Pin third-party actions to commit SHAs.** The workflow uses version tags (`@v2`, `@v4`), which can be moved by the action's owner. Pin to full SHAs and let Dependabot propose updates.
- **Keep the deploy token narrow.** Scope is already limited to Cloudflare Pages edit. Cloudflare cannot scope it to a single project, so rotate it when a team member leaves.
- **Keep secrets out of the Flutter web bundle.** Everything compiled into a web build is public. Pass the backend URL with `--dart-define`; never compile in the DeepSeek key or any other secret.

## Reliability

- **Pin the Flutter version.** `channel: stable` lets a new Flutter release change or break the build with no change in this repository. Pin `flutter-version` in `ci.yml`.
- **Add a post-deploy smoke test.** After `wrangler pages deploy`, `curl -fsS` the deployed URL and fail the job on a bad response. The course lists smoke tests against the deployed environment as part of the pipeline.
- **Define a rollback path.** Cloudflare keeps every deployment. Add a `workflow_dispatch` input that takes a git ref so a known-good commit can be redeployed, and document it in the deploy and rollback runbook.
- **Do not rely on the path filter to recover from failures.** If a deploy fails, or secrets are added later, nothing redeploys until the frontend changes again. Use the manual `workflow_dispatch` run in that case.

## Pipeline efficiency

- **Measure the regression-test pipeline.** The `frontend` job now runs `flutter test` before the web build, and the Android APK build and its Java setup have been removed. The [first PR workflow run](https://github.com/relax-mode/lagaw/actions/runs/39426238886) passed backend and Flutter tests, analysis, the web build, and preview deployment. Compare equivalent runs before claiming a speed improvement; see [PR #36](https://github.com/relax-mode/lagaw/pull/36) for the sprint-log decision and existing baseline.
- **Cache more aggressively if builds slow down.** Flutter and pub caching is already on; measure build times before optimizing further, since the DevOps rubric rewards measured improvement.

## Platform risks

- **Cloudflare is merging Pages into Workers.** Wrangler 4.151 tried to create the project through Workers and only created classic Pages with `--force`. Classic Pages works today and is fine for this semester, but do not build long-term on it.
- **The `lagaw` Pages project lives on a personal Cloudflare account.** If that person is unavailable, the team cannot manage it. Move it to a shared account or add teammates as members.
