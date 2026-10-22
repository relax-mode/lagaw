# Pipeline Metrics Log

Record actual GitHub Actions run IDs and job durations. Compare the same job and event type; include cache state so a warm-cache result is clear.

## Sprint 2 — Database job dependency cache

Optimization: enable the existing `setup-python` pip cache in the PostgreSQL CI job, keyed by `backend/requirements.txt`. The backend CI job already uses the same key, so the database job can reuse that dependency cache instead of downloading the same packages on every run.

| Measurement | Baseline | After optimization |
| --- | --- | --- |
| PR run | [#39729412274](https://github.com/relax-mode/lagaw/actions/runs/39729412274) | Pending this branch's GitHub Actions run |
| Database job duration | 41 seconds (05:41:01–05:41:42 UTC) | Pending |
| Install backend dependencies step | 8 seconds (05:41:29–05:41:37 UTC) | Pending |
| Pip cache | Not configured for Database CI | Pending |

Baseline evidence: the PR run's job details report a successful database check. The job spent 16 seconds initializing its PostgreSQL service, 8 seconds installing the PostgreSQL client, and 8 seconds installing Python dependencies. The optimization is limited to the repeated Python dependency download; it does not claim to reduce database startup time.

After the new PR run completes, record the job URL, job duration, dependency-install duration, and whether the pip cache was restored. Add the measured delta and actual result here before claiming improvement.

## Other measured pipeline changes

- PR #35 removed the Android APK build after a successful `main` run showed that step taking 148 seconds. The pipeline metrics log does not yet contain a comparable before/after total-duration measurement for that change.
