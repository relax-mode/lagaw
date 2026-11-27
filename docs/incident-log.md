# Incident Log

Every broken build or failed deploy that reached `main` or a deployed environment, with a short postmortem. Times are UTC. Owner: CyGray (DevOps).

| ID | Date | Environment | Impact | Detected by | Time to recover |
|---|---|---|---|---|---|
| [INC-1](#inc-1-staging-cloudflare-credential-rejected) | Oct 24–25, 2026 | Staging web | Staging Pages not updated; `staging.lagaw.pages.dev` returned 404 | `Deploy - Staging` failure | about 15.5 h (first failed deploy → recovered staging deploy; see INC-1) |
| [INC-2](#inc-2-main-runs-blocked-behind-a-staging-approval) | Oct 22–24, 2026 | `main` CI | Two `main` commits never received CI or a staging deploy | Run history review on Oct 26 | about 53.5 h of blocked `main` pipeline |
| [INC-3](#inc-3-production-drifted-behind-main) | Oct 22–27, 2026 | Production API and web | Production missed merged work: no AI extraction route, and no matching demo token in the web bundle | Smoke and bundle checks on Oct 26 | resolved by automatic promotion on Oct 27; independent live acceptance pending |
| [INC-4](#inc-4-scheduled-live-ai-check-returns-http-401) | Oct 29 – Nov 3, 2026 | Staging API (scheduled live AI check) | Scheduled live extraction check failed with HTTP 401 in two scheduled runs; merges and deploys were not blocked, by design | Scheduled run [40831834404](https://github.com/relax-mode/lagaw/actions/runs/40831834404) failure | about 119 h (first failed scheduled run → first passing run [41586194489](https://github.com/relax-mode/lagaw/actions/runs/41586194489)) |
| [INC-5](#inc-5-staging-api-traffic-pinned-to-an-old-revision) | Nov 3–27, 2026 | Staging API (Cloud Run `lagaw-api-staging`) | Every CI staging deploy created a revision that received 0% traffic, so staging kept serving Nov 3 code. The staging smoke check passed anyway, and two production promotions went through without a real staging test of the new backend code | Pre-panel audit on Nov 27, reading the service traffic with `gcloud run services describe` | about 23 d 18 h (pin created 10:03 UTC, Nov 3 → `--to-latest` at 04:14 UTC, Nov 27) |
| [INC-6](#inc-6-cloudflare-pages-token-rejected-again) | Nov 26–27, 2026 | Staging and production web (Cloudflare Pages) | The merge of PR #206 did not reach staging or production web; production kept the previous build (no user impact) | `Deploy - Staging` failure in run [45963052878](https://github.com/relax-mode/lagaw/actions/runs/45963052878); the scheduled credential check had failed about 23 h earlier | about 43 min (failed deploy → recovered deploy); 47 min from merge to live |

## INC-1: Staging Cloudflare credential rejected

- **What happened.** Main runs [39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096) and [40098046876](https://github.com/relax-mode/lagaw/actions/runs/40098046876) (attempt 3) passed every check and deployed the staging API. Both then failed at "Deploy staging Flutter Web", where Cloudflare rejected the request with codes `10000`/`9109`. The staging web URL kept returning 404.
- **Root cause.** The repository secret `CLOUDFLARE_API_TOKEN` was no longer accepted for the `lagaw` Pages project. A local Wrangler OAuth session could still manage the project, which hid the problem from manual checks.
- **Fix.** Kyle replaced the GitHub secret with an account-scoped Cloudflare Pages Edit token. Main run [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) then deployed and smoke-tested staging web successfully. Full investigation: [staging incident evidence](evidence/staging-incident-2026-10-25.md).
- **Recovery time.** Measured from the `Deploy - Staging` job completion in run 39743812096 (13:31:18 UTC, Oct 24) to the next successful staging deploy job in run 40163792050 (05:02:12 UTC, Oct 25): about 15.5 h. Measured from the last failed attempt, run 40098046876 (15:25:45 UTC, Oct 24): about 13.6 h.
- **Prevention.**
  - Separate Cloudflare tokens per environment, stored as environment secrets, so one expiry cannot block both (#58). **Not done as of Oct 30:** `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are still repository secrets (names checked with `gh api`, see [PIPELINE.md](../PIPELINE.md#environments-and-secrets)). Still open on Nov 27; the failure recurred as [INC-6](#inc-6-cloudflare-pages-token-rejected-again).
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

- **What happened.** The scheduled live check (`Scheduled live checks`, run [40831834404](https://github.com/relax-mode/lagaw/actions/runs/40831834404), a scheduled run created 06:52 UTC on Thursday, Oct 29) failed in the `Live AI extraction (staging)` job. The failed step, "Extract preferences through deployed staging", logged `HTTP 401`. The `Cloudflare deploy credential` job in the same run passed. A manual run on the PR #100 branch ([40833831042](https://github.com/relax-mode/lagaw/actions/runs/40833831042), 07:11 UTC) failed in both jobs before any step ran: the `staging` and `production` environments allow only protected branches, so GitHub rejected the branch. That run therefore did not test the fix. The next scheduled run, [41406705381](https://github.com/relax-mode/lagaw/actions/runs/41406705381) (07:30 UTC, Nov 2), failed in the same step; its credential job passed.
- **Root cause.** The staging API runs with `TRIP_AUTH_MODE=supabase` (`deploy-staging` in `.github/workflows/ci.yml`), which ignores the old demo token. Before PR #100, `scheduled-live-checks.yml` and `scripts/ai_live_smoke.py` still sent `STAGING_TRIP_DEMO_TOKEN` as a bearer token, so the API rejected the request. `backend/test_auth.py` (`test_demo_values_do_not_enable_demo_access_by_default`) covers the rule that demo values do not grant access by default.
- **Fix.** [PR #100](https://github.com/relax-mode/lagaw/pull/100) (`fix/ai-live-smoke-supabase-auth`) changes the live check to sign in with the smoke account. It merged at 05:30:14 UTC on Nov 3. Status: **recovered**.
- **Recovery time.** A manual `workflow_dispatch` run on `main`, [41586194489](https://github.com/relax-mode/lagaw/actions/runs/41586194489) (created 05:50:02 UTC, Nov 3), passed both jobs; its `Live AI extraction (staging)` job finished at 05:50:17 UTC. Measured from the first failed scheduled run (06:52:14 UTC, Oct 29): about 119 h (4 days 23 h). Every scheduled run from Nov 5 to Nov 23 also passed: [41989922558](https://github.com/relax-mode/lagaw/actions/runs/41989922558) (Nov 5), [42581631913](https://github.com/relax-mode/lagaw/actions/runs/42581631913) (Nov 9), [43180242620](https://github.com/relax-mode/lagaw/actions/runs/43180242620) (Nov 12), [43826292525](https://github.com/relax-mode/lagaw/actions/runs/43826292525) (Nov 16), [44488640139](https://github.com/relax-mode/lagaw/actions/runs/44488640139) (Nov 19) and [45141477792](https://github.com/relax-mode/lagaw/actions/runs/45141477792) (Nov 23). In the Nov 26 run, [45790667724](https://github.com/relax-mode/lagaw/actions/runs/45790667724), the live AI job passed again; its other job failed for an unrelated reason (see [INC-6](#inc-6-cloudflare-pages-token-rejected-again)).
- **Impact.** The live check is off the merge and deploy path (see [PIPELINE.md](../PIPELINE.md#scheduled-live-checks)), so no deploy was blocked. Two scheduled runs (Oct 29 and Nov 2) failed in the window, and no passing live AI run was recorded until Nov 3.
- **Prevention.**
  - Done: after PR #100 merged, `scheduled-live-checks.yml` was run with `workflow_dispatch` on `main` and passed (run 41586194489, above).
  - The demo token is still compiled into the web bundles; see the open risk in [PIPELINE.md](../PIPELINE.md#open-risks).

## INC-5: Staging API traffic pinned to an old revision

- **What happened.** At 06:17:30 UTC on Nov 3, the CI staging deploy left traffic on `lagaw-api-staging` as "latest revision = 100%". At 10:03:08 UTC, a manual QA deploy from Andrew's account created the tagged revision `lagaw-api-staging-00038-cuc` (tag `s4-qa`) with no traffic. Writing explicit traffic made Cloud Run record the service's traffic as `lagaw-api-staging-00035-xp9 = 100%` instead of "latest". Two more manual updates at 16:31 and 16:36 the same day kept that setting. This log does not record the exact command.
  - From then on, every CI staging deploy (by the staging deployer service account) created a new revision but kept traffic on `00035-xp9`: Nov 3 at 17:46 and 18:11; Nov 5 at 06:35, 06:43, 06:45, 06:47, 08:09, 09:06 and 09:09; Nov 15 from 05:50 to 06:02. Fifteen revisions created in the window never served traffic (`00037-96q`, `00038-zf5`, `00039` through `00045`, `00046` through `00051`).
  - Between 08:52 and 08:55 UTC on Nov 5, the #120 staging rollback drill moved traffic to `00033-hvh` and then restored the exact original, `00035-xp9`, as the runbook advised. That re-applied the pin, and nobody noticed that `00035-xp9` was not the newest revision (see the [drill evidence](evidence/s4-20-staging-rollback-2026-11-05.md)).
  - Every staging smoke check (`scripts/smoke_deployed.py staging`) still passed. It calls the service URL, which `00035-xp9` (Nov 3 code) served, and it does not compare the served revision or commit with the one just deployed. From Nov 3 to Nov 27, the staging gate therefore did not exercise new backend code before production promotion. Production promotions happened on Nov 5 and Nov 15.
  - Production was not pinned. On Nov 27, `lagaw-api-00041-465` served 100% with `latestRevision: true`.
  - Kyle detected the pin on Nov 27, during the pre-panel audit, by reading the service traffic with `gcloud run services describe`.
- **Root cause.** A manual tagged deploy wrote explicit traffic, which turned "latest revision = 100%" into a pin on a named revision. A named-revision pin survives later deploys, so every new revision got 0% traffic. Nothing in CI checked where traffic went after a deploy. The #120 drill and the runbook's advice to restore the exact pre-rollback revision kept the pin in place. The smoke check could not see the problem because it never compared the served revision with the deployed one.
- **Fix.** At 04:13:59 UTC on Nov 27, Kyle ran `gcloud run services update-traffic lagaw-api-staging --to-latest`. The next CI deploy (07:33:15 UTC, revision `lagaw-api-staging-00052-xkd`) served 100% as the latest revision.
- **Recovery time.** About 23 days 18 hours, measured from the manual deploy that created the pin (10:03:08 UTC, Nov 3) to the `--to-latest` change (04:13:59 UTC, Nov 27).
- **Prevention.**
  - [Issue #204](https://github.com/relax-mode/lagaw/issues/204): after every deploy, CI routes traffic to the latest revision and fails unless the latest ready revision serves 100%, for staging and production. Status: open, owner Kyle.
  - Follow-up (not started): the smoke check should verify that the served revision or commit matches what was just deployed.
  - The [rollback runbook](rollback-runbook.md#restoring-the-latest-approved-version) now ends a drill or rollback with `--to-latest` and a traffic check, so a drill no longer ends with a named-revision pin.
  - A manual tagged or QA revision must be followed by `--to-latest` once the next CI revision exists, and should be recorded in the sprint log.

## INC-6: Cloudflare Pages token rejected again

- **What happened.**
  - At 09:17:55 UTC on Nov 26, the scheduled run [45790667724](https://github.com/relax-mode/lagaw/actions/runs/45790667724) failed. Its `Cloudflare deploy credential` job failed at the step "Check that the Pages deploy token still works": Wrangler reported `Authentication error [code: 10000]` on the Pages deployments API. The `Live AI extraction (staging)` job in the same run passed. Nobody acted on the failure. Apart from GitHub's default failed-run email to the workflow's owner, nothing alerted the team.
  - At 08:05:48 UTC on Nov 27, PR #206 (a frontend change) merged. Main run [45963052878](https://github.com/relax-mode/lagaw/actions/runs/45963052878), attempt 1, passed all checks, but `Deploy - Staging` failed at "Deploy staging Flutter Web" (job 08:08:09 to 08:09:40 UTC). `Deploy - Production web` was skipped, so production kept serving the previous build. There was no user impact on production.
  - At 08:38:50 UTC, Kyle replaced the repository secret `CLOUDFLARE_API_TOKEN`.
  - In attempt 2 of the same run, `Deploy - Staging` ran from 08:49:30 to 08:51:21 UTC and `Deploy - Production web` from 08:51:26 to 08:52:45 UTC. The next `main` run (PR #208, merged 09:13 UTC) deployed normally in 5.0 min.
- **Root cause.** The repository secret `CLOUDFLARE_API_TOKEN` was no longer accepted by Cloudflare (code `10000`), the same failure class as [INC-1](#inc-1-staging-cloudflare-credential-rejected). The CI logs do not record whether the token expired or was revoked. It recurred because the INC-1 prevention items were not completed. One repository-level token still serves both environments. The scheduled check detected the problem about 23 h before the deploy failed, but a failed scheduled run does not reach the team.
- **Fix.** Kyle replaced the repository secret `CLOUDFLARE_API_TOKEN` (08:38:50 UTC, Nov 27). Attempt 2 of run 45963052878 then deployed staging and production web.
- **Recovery time.** From the failed `Deploy - Staging` job (08:09:40 UTC) to the completed `Deploy - Production web` job (08:52:45 UTC): about 43 min. From the PR #206 merge (08:05:48 UTC): 47 min.
- **Prevention.**
  - Record the replacement token's expiry date and holder in [PIPELINE.md](../PIPELINE.md#environments-and-secrets). Holder: Kyle. Expiry date: to be recorded by Kyle.
  - Separate staging and production Cloudflare tokens as environment secrets, so one failure cannot block both (still open; see INC-1).
  - Make scheduled-check failures notify the team (follow-up, for example by opening an issue automatically).
  - Re-run the scheduled check after any token rotation. A manual `workflow_dispatch` run after the rotation is recorded below:
    - Verification run: [45989252146](https://github.com/relax-mode/lagaw/actions/runs/45989252146) (`workflow_dispatch` on `main`, 11:17 UTC on Nov 27). Both `Live AI extraction (staging)` and `Cloudflare deploy credential` passed.
