# Pipeline Metrics Log

Record actual GitHub Actions run IDs and job durations. Compare the same job and event type; include cache state so a warm-cache result is clear.

## Sprint 2 — Database job dependency cache

Optimization: enable the existing `setup-python` pip cache in the PostgreSQL CI job, keyed by `backend/requirements.txt`. The backend CI job already uses the same key, so the database job can reuse that dependency cache instead of downloading the same packages on every run.

| Measurement | Baseline | After optimization |
| --- | --- | --- |
| PR run | [#39729412274](https://github.com/relax-mode/lagaw/actions/runs/39729412274) | [#39732744012](https://github.com/relax-mode/lagaw/actions/runs/39732744012), repeated in [#39733432495](https://github.com/relax-mode/lagaw/actions/runs/39733432495) |
| Database job duration | 41 seconds (05:41:01–05:41:42 UTC) | 32 seconds (06:14:45–06:15:17 UTC); repeat 36 seconds (06:21:32–06:22:08 UTC) |
| Install backend dependencies step | 8 seconds (05:41:29–05:41:37 UTC) | 6 seconds (06:15:08–06:15:14 UTC); repeat 4 seconds (06:21:59–06:22:03 UTC) |
| Pip cache | Not configured for Database CI | 37 MB restored on both runs (cache hit) |

The first after run completed 9 seconds faster (22%) than baseline; the repeat completed 5 seconds faster (12%). Dependency installation took 2 seconds less on the first after run and 4 seconds less on the repeat. The two after runs averaged 34 seconds, but this comparison has only one baseline run and PostgreSQL startup varied, so treat the total-job delta as preliminary. Baseline evidence: the PR run's job details report a successful database check. The job spent 16 seconds initializing its PostgreSQL service, 8 seconds installing the PostgreSQL client, and 8 seconds installing Python dependencies. The optimization targets only the repeated Python dependency download; it does not reduce database startup time.

Both updated CI runs passed the migrations and SQLAlchemy relationship checks. The pip cache was restored from the shared `setup-python` key used by the backend job.

## Other measured pipeline changes

- PR #35 removed the Android APK build after a successful `main` run showed that step taking 148 seconds. The pipeline metrics log does not yet contain a comparable before/after total-duration measurement for that change.
