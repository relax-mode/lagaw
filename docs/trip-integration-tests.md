# Trip CRUD database tests — issue #29

These tests exercise FastAPI's real Trip routes, validation, demo-token
authorization and `TripDatabase` through an HTTPX-backed TestClient. Database
requests use real PostgREST and PostgreSQL; database responses are not mocked.
Only the connection provider is replaced because standalone PostgREST serves
at `/`, without Supabase's `/rest/v1/` gateway prefix.

## Coverage and isolation

- Create, list, retrieve, PATCH and DELETE; defaults, exact budgets, pagination,
  ordering, partial updates, optional clearing and independently read persistence.
- Missing/malformed IDs and bodies, missing/unsupported fields, invalid dates,
  reversed budgets, negative/nonfinite/overprecision money and unauthorized calls.
- Owner isolation, existing-user foreign keys, joined user-trip records,
  PostgreSQL checks and user deletion cascading only to that user's trips.
- Unique synthetic users for each test, fixed payload values and dates, cleanup
  registered before setup writes, and verification that users/trips were removed.

The `db` tests use only the existing CI job's disposable PostgreSQL 17 database
`lagaw_test` on loopback port 5432 and PostgREST v12.2.3 on `127.0.0.1:53000`.
The fixture validates both target settings before requests, ignores proxy
environment variables and refuses redirects. It never loads `.env`, hosted
credentials or a running staging/production API. Offline guard tests reject
both development Supabase `vnpkyvtbupnquvirzlzp` and production
`zjnuqqtbapbpudsjbpif`. Staging uses development Supabase, so it is excluded too.

Each test has two unique synthetic users and owns all of its rows. HTTP writes
commit separately, so cleanup deletes those exact parents and verifies their
trips disappeared; an outer SQL rollback would not undo API writes. Cleanup runs
on assertion/setup failures. Missing-user tests also remove any unexpected
orphan insertion if a foreign key is broken. No test resets/truncates a table,
changes shared demo profiles, or uses existing catalog data. Tests run
sequentially; parallel execution is not configured. Forced termination or a lost
database connection can prevent teardown; the CI services are discarded with
the job regardless. Cleanup failures fail pytest.

Trip-itinerary-location associations remain outside #29. No application code,
schema migration, new dependency or environment-file change is needed.

## Commands and CI

Install the existing development dependencies from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pip install -r backend/requirements-dev.txt
```

Then run ordinary offline regressions and lint from `backend/`:

```powershell
..\.venv\Scripts\python.exe -m pytest -q -m "not db"
..\.venv\Scripts\python.exe -m ruff check .
```

The existing **Database - PostgreSQL migrations and smoke tests** Actions job
creates PostgreSQL, applies repository migrations, runs the existing SQL/ORM
checks and starts its loopback PostgREST container. No hosted keys are supplied.
Its Trip test command, from `backend/`, is:

```sh
python -m pytest -v -m db --junitxml=test-results/trip-integration.xml
```

The job supplies test-only process settings:

```text
DATABASE_URL=postgresql+psycopg://postgres:local_ci_only@localhost:5432/lagaw_test?sslmode=disable
CI_POSTGREST_URL=http://127.0.0.1:53000/
```

These are disposable service settings, never values to copy into `.env`.
Local database execution requires equivalent freshly migrated disposable
services; otherwise use the PR's Database job. Missing configuration, readiness
failure, assertion errors, cleanup errors and zero collected tests all fail the
check. The previous temporary pytest exit-code-5 exception is removed.

The `trip-integration-results` Actions artifact contains JUnit XML and uploads
even on failure. Full assertion output remains in the job log. Existing
association tests and service cleanup are retained. Repeat the Database job on
the same commit to check repeatability with fresh disposable services.

## Completion

Track observed results in [the evidence record](evidence/trip-integration-tests.md).
The PR uses `Refs #29`, leaving closure until teammate review, passing CI,
merge and post-merge checks are complete. This change adds tests and
documentation without changing application behavior or database schema. However,
it also changes `.github/workflows/ci.yml`, which the existing deployment
classifier treats as both backend and frontend changes. Merging #82 therefore
triggers the normal staging deployment and, after staging smoke checks pass,
production promotion. The database tests themselves still use only disposable
services. No manual deployment or hosted database test run is required. A later
documentation-only evidence merge does not trigger deployment.
