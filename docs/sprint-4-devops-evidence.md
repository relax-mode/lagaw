# Sprint 4 DevOps Evidence Index

Factual index of Sprint 4 DevOps work for [issue #122](https://github.com/relax-mode/lagaw/issues/122) and the consultation pack. It records what exists on `main` and in GitHub on October 30, 2026, and what is still pending. It does not record outcomes that have not happened. Owner: CyGray (DevOps).

PR numbers are placeholders (`PR: TBD`) until the lead fills them in. Work that is in review is not on `main` yet, so links to its files are not given here.

## Issue to work map

| Issue | Title (as on GitHub, state on Oct 30) | PR | Status | Branch or location |
|---|---|---|---|---|
| [#112](https://github.com/relax-mode/lagaw/issues/112) | [S4-12] Evaluate Brevo and Resend for Supabase Authentication Emails (open) | PR: TBD | In review | `chore/s4-resend-auth-readiness` |
| [#113](https://github.com/relax-mode/lagaw/issues/113) | [S4-13] Configure and Verify Production Authentication Email Delivery (open) | PR: TBD | Blocked on the sender domain and SMTP credentials | `chore/s4-resend-auth-readiness` (preparation only) |
| [#118](https://github.com/relax-mode/lagaw/issues/118) | [S4-18] Restore Scheduled AI Smoke Checks and Production Verification (open) | PR: TBD | Fix in review. The scheduled check is failing. | `fix/ai-live-smoke-supabase-auth` |
| [#119](https://github.com/relax-mode/lagaw/issues/119) | [S4-19] Improve CI/CD Security and Pipeline Efficiency (open) | PR: TBD | Security work in review. Metrics work in this branch. | `chore/s4-cicd-security` (security); `docs/s4-devops-records` (metrics and docs) |
| [#120](https://github.com/relax-mode/lagaw/issues/120) | [S4-20] Document and Execute a Staging Rollback Drill (open) | PR: TBD | Runbook and helper in review. **Drill not performed.** | `chore/s4-rollback-readiness` |
| [#121](https://github.com/relax-mode/lagaw/issues/121) | [S4-21] Prepare and Publish the Verified v1.0.0 Release (open) | PR: TBD | Changelog and release process in review. **No tag or release exists.** | `chore/s4-release-readiness` |
| [#122](https://github.com/relax-mode/lagaw/issues/122) | [S4-22] Maintain Sprint 4 Records and Consultation Evidence (open) | PR: TBD | This branch | `docs/s4-devops-records` |

## Evidence available now

| Item | Evidence | Date |
|---|---|---|
| Sprint 3 pipeline metrics (partial, through the last run available) | [`pipeline-metrics.md`](pipeline-metrics.md#sprint-3-source-partial) | Oct 30 (data to Oct 29 07:24 UTC) |
| Scheduled live AI check failure (HTTP 401) | Run [40831834404](https://github.com/relax-mode/lagaw/actions/runs/40831834404); the Cloudflare deploy-credential job in the same run passed. See [INC-4](incident-log.md#inc-4-scheduled-live-ai-check-returns-http-401). | Oct 29 |
| Attempted fix run (not a valid test) | Manual run on the fix branch, [40833831042](https://github.com/relax-mode/lagaw/actions/runs/40833831042). Both jobs were rejected by environment branch protection before any step ran. | Oct 29 |
| Production promotion, automatic | Run [40482703372](https://github.com/relax-mode/lagaw/actions/runs/40482703372): staging, production API and production web succeeded. | Oct 27 |
| Manual recovery runs | Runs [40815650607](https://github.com/relax-mode/lagaw/actions/runs/40815650607), [40816436789](https://github.com/relax-mode/lagaw/actions/runs/40816436789) and [40816925527](https://github.com/relax-mode/lagaw/actions/runs/40816925527): all deploy jobs succeeded. These show the redeploy path works, which is not a rollback drill. | Oct 29 |
| Staging recovery after the Cloudflare credential failure | Run [40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050) and [staging incident evidence](evidence/staging-incident-2026-10-25.md) | Oct 25 |
| Staging acceptance (browser write in development only) | [staging acceptance evidence](evidence/staging-acceptance-2026-10-26.md) | Oct 26 |
| Branch protection settings | Read from the GitHub API on Oct 30: one approving review, dismiss stale reviews, strict checks, the three required CI checks, no force pushes or deletion | Oct 30 |
| Staging and production environment rules | Read from the GitHub API on Oct 30: protected branches only, no required reviewers | Oct 30 |
| Supabase Auth redirect and email settings | [sprint log](sprint-log.md) Oct 29 entry: Site URL and redirect allow-lists set in both projects; email rate limit still 2 per hour because custom SMTP is not configured | Oct 29 |

## Pending

| Item | Needed before it can be recorded |
|---|---|
| Scheduled live AI check passing | The fix merged to `main` (PR #100 is the open fix branch, `fix/ai-live-smoke-supabase-auth`), then a passing run recorded. Scheduled runs are Mondays and Thursdays 09:00 Asia/Manila; a manual run is possible. |
| Staging rollback drill | Explicit authorization to run it on staging. The runbook is still in review. |
| Release tag `v1.0.0` and release | The `chore/s4-release-readiness` PR merged, then the tag and release created. No tag or release exists on Oct 30. |
| Email sender domain and SMTP for Supabase Auth | A verified sender domain and SMTP credentials chosen and entered by the owner. Sprint log Oct 29: custom SMTP is required before the email rate limit can be raised. |
| Independent live production extraction and browser acceptance | Not recorded; INC-3 lists it as pending. |
| Sprint 4 metrics row | Regenerate for the full Sprint 4 window once it ends. |
| Domain verification (scope item from the Sprint 4 records request) | The repository has no evidence for it. The lead needs to confirm which domain is meant. |

## Honest gaps

- **No standups for Sprint 3 or Sprint 4 are recorded.** The [sprint log](sprint-log.md) says none has been posted for Sprint 3 and asks that each be added on the day, without backfilling. This index does not create any.
- **No consultation outcome is recorded.** The sprint log lists the Sprint 3 consultation pack as dated November 1 and says its outcome is recorded only after the meeting.
- **No retrospective is recorded** for Sprint 2 or Sprint 3 in the sprint log. The Sprint 2 retrospective is marked as pending there.
- **The Sprint 3 metrics are partial.** Runs after Oct 29 07:24 UTC were not yet available when they were generated.
- **The scheduled live check has no passing run** in GitHub's workflow history. The history contains two runs, and both failed.
- **The rollback drill has not been run.** The rollback commands in [`PIPELINE.md`](../PIPELINE.md#rollback) are documented but not exercised.
- **Documentation corrections in this branch** are listed in the commit history. They fix statements that did not match `ci.yml`, including the manual-run behavior and the demo token. The workflow comment that still says manual runs redeploy production only is recorded as an open item in [`PIPELINE.md`](../PIPELINE.md#continuous-deployment).
