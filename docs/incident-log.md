# Incident Log

Every broken build or failed deploy that reached `main` or a deployed environment, with a short postmortem. Times are UTC. Owner: CyGray (DevOps).

| ID | Date | Environment | Impact | Detected by | Time to recover |
|---|---|---|---|---|---|
| [INC-1](#inc-1-staging-cloudflare-credential-rejected) | Oct 24–25, 2026 | Staging web | Staging Pages not updated; `staging.lagaw.pages.dev` returned 404 | `Deploy - Staging` failure | about 15.4 h (failed deploy → next successful staging deploy) |
| [INC-2](#inc-2-main-runs-blocked-behind-a-staging-approval) | Oct 22–24, 2026 | `main` CI | Two `main` commits never received CI or a staging deploy | Run history review on Oct 26 | about 53.5 h of blocked `main` pipeline |

## INC-1: Staging Cloudflare credential rejected

- **What happened.** Main runs [39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096) and [40098046876](https://github.com/relax-mode/lagaw/actions/runs/40098046876) (attempt 3) passed every check and deployed the staging API. Both then failed at "Deploy staging Flutter Web", where Cloudflare rejected the request with codes `10000`/`9109`. The staging web URL kept returning 404.
- **Root cause.** The repository secret `CLOUDFLARE_API_TOKEN` was no longer accepted for the `lagaw` Pages project. A local Wrangler OAuth session could still manage the project, which hid the problem from manual checks.
- **Fix.** Kyle replaced the GitHub secret with an account-scoped Cloudflare Pages Edit token. Main run [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) then deployed and smoke-tested staging web successfully. Full investigation: [staging incident evidence](evidence/staging-incident-2026-10-25.md).
- **Prevention.**
  - Separate Cloudflare tokens per environment, stored as environment secrets, so one expiry cannot block both (#58).
  - A scheduled credential check that fails loudly before a deploy needs the token (#58).
  - The staging deploy fails visibly on missing or invalid configuration instead of skipping.

## INC-2: Main runs blocked behind a staging approval

- **What happened.** Main run [39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096) (`2cde152`) finished its checks at 07:56 on Oct 22. Its `Deploy - Staging` job then waited for the `staging` environment's required-reviewer approval until 13:27 on Oct 24, about 53.5 hours.
  - Meanwhile, push run [39745804329](https://github.com/relax-mode/lagaw/actions/runs/39745804329) (`dcf0c1f`) queued behind it and was cancelled when a newer push arrived.
  - Push run [39746663078](https://github.com/relax-mode/lagaw/actions/runs/39746663078) (`2156388`) then queued for about 53 hours and was cancelled without running a job.
  - The approval was eventually given, and the deploy then failed on INC-1.
- **Root cause.** The workflow-level concurrency group was keyed by `github.ref` without cancellation for pushes, so every `main` run shared one group. A run waiting on a manual approval held the group: GitHub kept only one pending run and cancelled older pending runs. Combined with a required reviewer on the automatic staging path, this left `main` without CI feedback for two days.
- **Fix.** The staging required-reviewer rule was removed (the environment now allows protected branches only). In #31 the workflow concurrency group became per pull request for PRs and per run for pushes; the deploy jobs keep their own serializing groups. A deploy waiting in one run can no longer queue or cancel checks for later commits.
- **Prevention.**
  - Every job now has a `timeout-minutes` limit.
  - Manual approval gates are kept off the automatic deploy path.
  - The weekly metrics review (`scripts/pipeline_metrics.py`) shows outlier wall times, so a stuck run is noticed within a week.
