# Pipeline Metrics Log

Record actual GitHub Actions run IDs and job durations. Compare the same job and event type; include cache state so a warm-cache result is clear.

## Weekly metrics log

Generated from the GitHub Actions API with `python scripts/pipeline_metrics.py --since <first day> --until <last day>` for the `Lagaw CI` workflow (UTC weeks). Notes on the columns:

- PR and main times are the mean wall time of successful runs. Cancelled runs are excluded from the success rate.
- Production deploys count only runs whose deploy step actually ran on `main`. Deploys from the retired separate `Deploy Backend` workflow are not included.
- Lead time is measured from PR merge to the first successful production deploy of the merge commit, so it covers only merges that reached production through the pipeline.
- Failed deploys include staging. Time to recover is measured from a failed deploy to the next successful run of the same deploy job.

| Week | Avg PR pipeline time (min) | Main pipeline time (min) | Pipeline success rate (%) | Production deploys | Avg lead time, merge to live (min) | Failed deploys | Time to recover (min) | Change made this week |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sprint 1 (Oct 12–18) | 4.5 | 1.9 | 96.8 | 2 | 4.2 | 0 | n/a | First CI pipeline and Cloudflare Pages deploys (Cloud Run was deployed by a separate workflow). The Android APK build made PR runs slow (median 239 s). |
| Sprint 2 (Oct 19–25) | 1.6 | 2.2 | 96.6 | 3 | 1.9 (3 of 22 merges) | 2 (staging, [INC-1](incident-log.md#inc-1-staging-cloudflare-credential-rejected)) | 863.9 | Removed the APK build (#35); pip cache in the DB job; staging environment; production deploys made manual (#44), which is why only 3 of 22 merges reached production. |
| Sprint 3 (Oct 26–Nov 1), **PARTIAL**: data through Oct 29, 07:24 UTC | 1.2 | 4.9 | 97.5 | 23 | 6.9 (12 of 24 merges) | 0 | n/a (no failed deploy on `main` in the window) | Path-filtered PR checks and pipeline hardening (#31, below); production promotion and AI checks (#58). |
| Sprint 4 | | | | | | | | pending |

Fill the Sprint 3 row from the script output before the Sprint 3 consultation, and record the remaining weeks as they happen. The Sprint 3 figures below come from the command in [Sprint 3 source](#sprint-3-source-partial). Runs after Oct 29 07:24 UTC were not yet available when the script ran on Oct 30, so the row must be regenerated for the full week before it is final.

### Sprint 3 source (PARTIAL)

Command, run on Oct 30, 2026 (about 12:40 UTC), from the repository root with an authenticated `gh` CLI:

```sh
python3 scripts/pipeline_metrics.py --since 2026-10-26 --until 2026-11-01 --jobs
```

- **Query window:** workflow `Lagaw CI` (`ci.yml`), runs created Oct 26 to Nov 1 (UTC), completed runs only. The last completed run in the window at query time was [40834627148](https://github.com/relax-mode/lagaw/actions/runs/40834627148) (`main`, Oct 29 07:24 UTC).
- **Run count:** 81 completed runs: 77 success, 2 failure, 2 cancelled. The script excluded 9 deliberate `test/ci-proof-*` probe runs. They belong to probe PRs [#69](https://github.com/relax-mode/lagaw/pull/69) to [#75](https://github.com/relax-mode/lagaw/pull/75), all closed without merging; the failing ones are intentional. The success rate is 77 of 79 (cancelled runs excluded).
- **Failed runs:** none of the failures was a deploy. The 2 failures are PR runs on `feat/s3-09-itinerary-generation` ([40684950570](https://github.com/relax-mode/lagaw/actions/runs/40684950570) and [40685146214](https://github.com/relax-mode/lagaw/actions/runs/40685146214), Oct 28), both failed in the Database job. Cancelled PR runs: [40813555854](https://github.com/relax-mode/lagaw/actions/runs/40813555854) and [40833672392](https://github.com/relax-mode/lagaw/actions/runs/40833672392). The script's failed-deploy count covers `main` runs only, so it reports 0 failed deploys and `n/a` recovery time.
- **Production deploys:** 23 is the number of successful production deploy jobs (API and web counted separately) on `main` runs, as the script counts them. Production-deploying `main` runs in the window include the first automatic promotion [40482703372](https://github.com/relax-mode/lagaw/actions/runs/40482703372) (Oct 27; API and web jobs both succeeded), and the manual `workflow_dispatch` runs [40815650607](https://github.com/relax-mode/lagaw/actions/runs/40815650607), [40816436789](https://github.com/relax-mode/lagaw/actions/runs/40816436789) and [40816925527](https://github.com/relax-mode/lagaw/actions/runs/40816925527) (Oct 29), which also ran Deploy - Staging. The docs do not record why those three manual runs were made; the sprint log's Oct 29 entry says manual runs on `main` were allowed for redeploys.
- **Lead time:** 6.9 min is the mean of 12 merges that reached production through the pipeline, out of 24 merged PRs in the window. The other 12 are not in the average.
- **Recovery:** `n/a`, because no deploy job failed on `main` in the window. The incident in this window, [INC-3](incident-log.md#inc-3-production-drifted-behind-main), was production drift rather than a failed deploy, so the script does not count it. The failed staging deploys of [INC-1](incident-log.md#inc-1-staging-cloudflare-credential-rejected) happened on Oct 24, before this window.
- **Scheduled live checks:** not part of `Lagaw CI`, so not in these numbers. Its Oct 29 failure is in [INC-4](incident-log.md#inc-4-scheduled-live-ai-check-returns-http-401).
- **Operational note:** the GitHub API returned intermittent HTTP 502 errors. The script has no retry; the reported output is from the fourth attempt, unedited.

Per-job median durations, Sprint 3 window (`--jobs` output; `n` is the number of job results counted, including non-success results; durations are job start to completion; skipped jobs have no duration):

| Event | Job | Median | p90 | Mean | n |
| --- | --- | --- | --- | --- | --- |
| pull_request | Backend - Python | 30 s | 41 s | 32 s | 34 |
| pull_request | Database - PostgreSQL migrations and smoke tests | 42 s | 49 s | 42 s | 34 |
| pull_request | Detect changed areas | 6 s | 7 s | 6 s | 53 |
| pull_request | Frontend - Flutter | 89 s | 102 s | 98 s | 31 |
| pull_request | Decide, Deploy - Staging, Deploy - Production API, Deploy - Production web (n=2 each) | 0 s | 0 s | 0 s | 2 |
| push | Backend - Python | 32 s | 38 s | 32 s | 23 |
| push | Database - PostgreSQL migrations and smoke tests | 40 s | 49 s | 41 s | 23 |
| push | Detect changed areas | 6 s | 7 s | 6 s | 22 |
| push | Frontend - Flutter | 88 s | 104 s | 89 s | 23 |
| push | Decide - Staging deployment | 5 s | 6 s | 5 s | 23 |
| push | Deploy - Staging | 131 s | 186 s | 141 s | 13 |
| push | Deploy - Production API | 56 s | 62 s | 57 s | 8 |
| push | Deploy - Production web | 74 s | 83 s | 77 s | 9 |
| workflow_dispatch | Backend - Python | 39 s | 40 s | 38 s | 3 |
| workflow_dispatch | Database - PostgreSQL migrations and smoke tests | 45 s | 48 s | 44 s | 3 |
| workflow_dispatch | Detect changed areas | 6 s | 6 s | 6 s | 3 |
| workflow_dispatch | Frontend - Flutter | 105 s | 107 s | 101 s | 3 |
| workflow_dispatch | Decide - Staging deployment | 5 s | 6 s | 5 s | 3 |
| workflow_dispatch | Deploy - Staging | 147 s | 170 s | 151 s | 3 |
| workflow_dispatch | Deploy - Production API | 73 s | 97 s | 80 s | 3 |
| workflow_dispatch | Deploy - Production web | 81 s | 83 s | 79 s | 3 |

The `pull_request` rows for the three deploy and decide jobs show 0 s over 2 results. The script does not explain them, and they are not deploy times, so no interpretation is made here.

On October 27, [PR #77](https://github.com/relax-mode/lagaw/pull/77) merged at 09:41:28 UTC. Its [promotion run](https://github.com/relax-mode/lagaw/actions/runs/40482703372) completed the production API job at 09:46:29 (5 min 1 sec after merge) and the production web job at 09:47:45 (6 min 17 sec after merge). These are individual job completion times, not the Sprint 3 average.

## Sprint 2 — Database job dependency cache

Optimization: enable the existing `setup-python` pip cache in the PostgreSQL CI job. In the commit before #68 (`14677f7~1`), that job keyed the cache on `backend/requirements.txt`, while the backend job keyed on `backend/requirements-dev.txt`, so the two jobs did not share a cache entry. Since #68 (commit `14677f7`), both jobs key the cache on, and install from, `backend/requirements-dev.txt` (`.github/workflows/ci.yml`, lines 98 and 197). The results below were measured before that change.

| Measurement | Baseline | After optimization |
| --- | --- | --- |
| PR run | [#39729412274](https://github.com/relax-mode/lagaw/actions/runs/39729412274) | [#39732744012](https://github.com/relax-mode/lagaw/actions/runs/39732744012), repeated in [#39733432495](https://github.com/relax-mode/lagaw/actions/runs/39733432495) |
| Database job duration | 41 seconds (05:41:01–05:41:42 UTC) | 32 seconds (06:14:45–06:15:17 UTC); repeat 36 seconds (06:21:32–06:22:08 UTC) |
| Install backend dependencies step | 8 seconds (05:41:29–05:41:37 UTC) | 6 seconds (06:15:08–06:15:14 UTC); repeat 4 seconds (06:21:59–06:22:03 UTC) |
| Pip cache | Not configured for Database CI | 37 MB restored on both runs (cache hit) |

The first after run completed 9 seconds faster (22%) than baseline; the repeat completed 5 seconds faster (12%). Dependency installation took 2 seconds less on the first after run and 4 seconds less on the repeat. The two after runs averaged 34 seconds, but this comparison has only one baseline run and PostgreSQL startup varied, so treat the total-job delta as preliminary. Baseline evidence: the PR run's job details report a successful database check. The job spent 16 seconds initializing its PostgreSQL service, 8 seconds installing the PostgreSQL client, and 8 seconds installing Python dependencies. The optimization targets only the repeated Python dependency download; it does not reduce database startup time.

Both updated CI runs passed the migrations and SQLAlchemy relationship checks. The pip cache was restored from the database job's own `setup-python` key (`requirements.txt`), not from the backend job's key.

## Other measured pipeline changes

- PR #35 removed the Android APK build after a successful `main` run showed that step taking 148 seconds. The pipeline metrics log does not yet contain a comparable before/after total-duration measurement for that change.

## Sprint 3: Path-filtered pull request checks (#31)

**Bottleneck.** `Frontend - Flutter` was the slowest job in every sampled run: median 84 s, p90 92 s over 40 PR runs from Oct 19–25. It ran on every PR, including 6 docs-only and 8 backend-only PRs among the 22 merged in Sprint 2. Every PR waited about 90 s regardless of what it changed.

**Change.** A `Detect changed areas` job (`dorny/paths-filter`) classifies each PR. Backend, Database and Frontend checks run only when their paths change, and a skipped check still satisfies branch protection. Pushes to `main` and manual runs still run everything. The same PR also reuses the runner's preinstalled `psql` instead of `apt-get install postgresql-client`.

| Pull request type | Before (old workflow ran every check) | After (path-filtered) |
| --- | --- | --- |
| Docs-only | 83 s ([#67](https://github.com/relax-mode/lagaw/pull/67), run [40303263203](https://github.com/relax-mode/lagaw/actions/runs/40303263203)); Sprint 2 PR median 90 s (n=39) | **9 s** median: 9, 12, 9 s (run [40304669945](https://github.com/relax-mode/lagaw/actions/runs/40304669945) attempts 1–3) |
| Backend-only | Sprint 2 PR median 90 s (n=39) | **54 s** median: 50, 54, 56 s (run [40304682540](https://github.com/relax-mode/lagaw/actions/runs/40304682540) attempts 1–3) |
| Workflow change (all checks) | Sprint 2 PR median 90 s (n=39) | 90 s (run [40304632572](https://github.com/relax-mode/lagaw/actions/runs/40304632572), n=1) |
| Database job "PostgreSQL client" step | 8 s (`apt-get`, run [39729412274](https://github.com/relax-mode/lagaw/actions/runs/39729412274)) | **0 s**, 3 of 3 runs (psql 16.15 preinstalled) |

**Expected effect.** If Sprint 2's 22 merged PRs are re-weighted with these timings, the mean PR wait falls from about 90 s to about 54 s, roughly 40% shorter. The re-weighting uses 6 docs-only at 10 s, 8 backend at 54 s, 2 frontend at an estimated 85 s, and 6 full at 90 s. Runner minutes fall further, because skipped jobs use none.

**Cost.** Runs that need every check gain the 3–5 s classification job, so they did not get faster. The measured wall time for these was unchanged in the one sample.

**What we learned.**
- Path filtering helped because most of our PRs touch a single area, not because any one job got faster. Docs-only PRs now return in about 10 s, which matters most during the Demo Day live-deploy rehearsal and sprint-log updates.
- The Flutter job itself is still about 85 s. The next optimization target is the Flutter toolchain setup and build.
- Re-measure the Sprint 3 average with `scripts/pipeline_metrics.py` once real Sprint 3 PRs accumulate. These figures come from controlled probe PRs: [#69](https://github.com/relax-mode/lagaw/pull/69) and [#70](https://github.com/relax-mode/lagaw/pull/70), closed without merging.

