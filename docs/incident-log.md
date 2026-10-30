# Incident Log

Every broken build or failed deploy that reached `main` or a deployed environment, with a short postmortem. Times are UTC. Owner: CyGray (DevOps).

| ID | Date | Environment | Impact | Detected by | Time to recover |
|---|---|---|---|---|---|
| [INC-1](#inc-1-staging-cloudflare-credential-rejected) | Oct 24–25, 2026 | Staging web | Staging Pages not updated; `staging.lagaw.pages.dev` returned 404 | `Deploy - Staging` failure | about 15.5 h (first failed deploy → recovered staging deploy; see INC-1) |
| [INC-2](#inc-2-main-runs-blocked-behind-a-staging-approval) | Oct 22–24, 2026 | `main` CI | Two `main` commits never received CI or a staging deploy | Run history review on Oct 26 | about 53.5 h of blocked `main` pipeline |
| [INC-3](#inc-3-production-drifted-behind-main) | Oct 22–27, 2026 | Production API and web | Production missed merged work: no AI extraction route, and no matching demo token in the web bundle | Smoke and bundle checks on Oct 26 | resolved by automatic promotion on Oct 27; independent live acceptance pending |
| [INC-4](#inc-4-scheduled-live-ai-check-returns-http-401) | Oct 29, 2026 | Staging API (scheduled live AI check) | Scheduled live extraction check failed with HTTP 401; merges and deploys were not blocked, by design | Scheduled run [40831834404](https://github.com/relax-mode/lagaw/actions/runs/40831834404) failure | Not recovered; fix in review (PR #100) |

## INC-1: Staging Cloudflare credential rejected

- **What happened.** Main runs [39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096) and [40098046876](https://github.com/relax-mode/lagaw/actions/runs/40098046876) (attempt 3) passed every check and deployed the staging API. Both then failed at "Deploy staging Flutter Web", where Cloudflare rejected the request with codes `10000`/`9109`. The staging web URL kept returning 404.
- **Root cause.** The repository secret `CLOUDFLARE_API_TOKEN` was no longer accepted for the `lagaw` Pages project. A local Wrangler OAuth session could still manage the project, which hid the problem from manual checks.
- **Fix.** Kyle replaced the GitHub secret with an account-scoped Cloudflare Pages Edit token. Main run [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) then deployed and smoke-tested staging web successfully. Full investigation: [staging incident evidence](evidence/staging-incident-2026-10-25.md).
- **Recovery time.** Measured from the `Deploy - Staging` job completion in run 39743812096 (13:31:18 UTC, Oct 24) to the next successful staging deploy job in run 40163792050 (05:02:12 UTC, Oct 25): about 15.5 h. Measured from the last failed attempt, run 40098046876 (15:25:45 UTC, Oct 24): about 13.6 h.
- **Prevention.**
  - Separate Cloudflare tokens per environment, stored as environment secrets, so one expiry cannot block both (#58). **Not done as of Oct 30:** `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are still repository secrets (names checked with `gh api`, see [PIPELINE.md](../PIPELINE.md#environments-and-secrets)).
  - A scheduled credential check that fails loudly before a deploy needs the token (#58). It exists as the `deploy-credentials` job in `scheduled-live-checks.yml`; it passed in run 40831834404 on Oct 29.
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

## INC-3: Production drifted behind main

- **What happened.** Production deploys became manual-dispatch only on Oct 22 (PR #44). No dispatch run followed. On Oct 26:
  - Production Pages still served the build from run `8aa469c` (07:36 UTC, Oct 22). That predates #49, which compiled the demo token into web builds, so the production web bundle does not contain the production demo token and its trip requests cannot authenticate. A check of the downloaded bundle found 0 occurrences of the production token; the same check on staging found its token.
  - The production API (`lagaw-api-00007-hfl`) returned **404** for `/api/v1/preferences/extract`. Meanwhile `main` and staging had shipped the extraction API (#64), the Week 3 evaluation (#66) and the association API (#60).
- **Root cause.** A manual production step conflicted with the course requirement and the approved pitch: every merge must deploy without manual steps. Nothing alerted anyone to the gap, because only staging deployed automatically and only staging was smoke-tested on each merge.
- **Fix.** #58 promotes every qualifying `main` push to production after staging passes. It reuses the staging-tested image, rebuilds the web app with the production token from the GitHub `production` environment, and runs the same smoke checks as staging, including the extraction route. [PR #77](https://github.com/relax-mode/lagaw/pull/77) landed the promotion on `main`; [run 40482703372](https://github.com/relax-mode/lagaw/actions/runs/40482703372) passed staging and both production jobs on October 27. The production web job completed at 09:47:45 UTC, 6 min 17 sec after the merge. Independent live extraction and browser acceptance remain pending.
- **Prevention.**
  - No manual step remains on the deploy path; manual dispatch is for recovery only.
  - The production smoke check fails if a route that `main` serves is missing.
  - The weekly metrics now report merge-to-live lead time, which exposes any merge that never reached production.

## INC-4: Scheduled live AI check returns HTTP 401

- **What happened.** The scheduled live check (`Scheduled live checks`, run [40831834404](https://github.com/relax-mode/lagaw/actions/runs/40831834404), a scheduled run created 06:52 UTC on Thursday, Oct 29) failed in the `Live AI extraction (staging)` job. The failed step, "Extract preferences through deployed staging", logged `HTTP 401`. The `Cloudflare deploy credential` job in the same run passed. A manual run on the PR #100 branch ([40833831042](https://github.com/relax-mode/lagaw/actions/runs/40833831042), 07:11 UTC) failed in both jobs before any step ran: the `staging` and `production` environments allow only protected branches, so GitHub rejected the branch. That run therefore did not test the fix.
- **Root cause.** The staging API runs with `TRIP_AUTH_MODE=supabase` (`.github/workflows/ci.yml`, line 448), which ignores the old demo token. `scheduled-live-checks.yml` (line 34) and `scripts/ai_live_smoke.py` (lines 39 and 65) still send `STAGING_TRIP_DEMO_TOKEN` as a bearer token, so the API rejects the request. `backend/test_auth.py` (`test_demo_values_do_not_enable_demo_access_by_default`) covers the rule that demo values do not grant access by default.
- **Fix.** [PR #100](https://github.com/relax-mode/lagaw/pull/100) (`fix/ai-live-smoke-supabase-auth`, open) changes the live check to sign in with the smoke account. Status: **fix in review**.
- **Impact.** The live check is off the merge and deploy path (see [PIPELINE.md](../PIPELINE.md#scheduled-live-checks)), so no deploy was blocked. The recorded workflow history contains only the two runs above; no passing live AI run is recorded.
- **Prevention.**
  - After PR #100 merges, run `scheduled-live-checks.yml` with `workflow_dispatch` on `main` and record the run here before closing this entry.
  - The demo token is still compiled into the web bundles; see the open risk in [PIPELINE.md](../PIPELINE.md#open-risks).

