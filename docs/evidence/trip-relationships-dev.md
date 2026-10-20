# Issue #22: database relationship verification

- Date: October 20, 2026 (Asia/Manila).
- Environment: test/development Supabase project `vnpkyvtbupnquvirzlzp`.
- Source: terminal output reported by the developer during guided verification.
- Command, from the repository root:

```powershell
.\.venv\Scripts\python.exe backend/verify_trip_relationships.py
```

Reported output:

```text
PASS: Related user, trip, itinerary, and locations loaded.
PASS: Invalid and missing foreign keys rejected.
PASS: Trip deletion removed its itinerary items.
PASS: User and destinations preserved.
PASS: Temporary verification records rolled back.
```

The fixture trip references the existing San Sebastian Cathedral and The Negros
Museum UUIDs. It checks the user/trip/itinerary/location relationships, missing
and invalid foreign keys, trip deletion, and rollback without committing fixtures.
The developer also reported that the original SQL schema smoke test returned
`Success. No rows returned` and the development PostgreSQL connection succeeded.

## Locations endpoint regression — October 21, 2026

The developer reported a successful local FastAPI request against the development
database using:

```powershell
$page = Invoke-RestMethod 'http://127.0.0.1:8000/locations?limit=10&offset=0'
$page.items | Select-Object id, name
```

The supplied response contained all ten seeded destinations:

| ID | Name |
| --- | --- |
| `f52c28a6-cf76-5efa-b0a3-d04f8b15794c` | Arima Restaurant |
| `a752a30a-1859-503d-8a77-8cd59097ac1d` | Cafetolyo Coffee Shop |
| `f2ccf475-56ea-51a0-a003-70f66d9f852a` | Calea Pastries & Coffee |
| `af80a358-d1ad-529f-84b3-ff1e591e041f` | Capitol Park and Lagoon |
| `b3783066-7484-5917-a09b-404974974880` | Negros Forest Park |
| `4618dfae-4a30-5917-85f1-94f216cf5b97` | Negros Occidental Provincial Capitol |
| `d184610e-f8c9-584a-95a3-79809cd81c49` | Orange Project |
| `ee2c8f6e-7a15-5081-b8a3-b43d48d5a83c` | Panaad Park and Sports Complex |
| `1a3bca09-5532-5de6-8587-2440c4e5830d` | San Sebastian Cathedral |
| `61bf94ab-6ec0-5ec3-8451-b575ee06169e` | The Negros Museum |

This confirms the existing locations endpoint still returns the Sprint 1
destinations after the relationship verification changes.

## Deployment and production verification — October 21, 2026

The developer reported all four checks passed, a teammate approved the PR, and
supplied [merged implementation PR #37](https://github.com/relax-mode/lagaw/pull/37).
Their screenshot of the latest `main` **Deploy Backend** run shows the
**Deploy - Cloud Run** job succeeded. **Deploy to Cloud Run** completed in 38
seconds and **Smoke test** completed in 1 second with:

```text
smoke test ok: 1 location
```

The screenshot was inspected during this session. The developer supplied the
[successful deployment job](https://github.com/relax-mode/lagaw/actions/runs/39455881955/job/118742502234)
as the linked record of that run.

After deployment, the developer ran the complete
`supabase/tests/schema_smoke.sql` transaction in the SQL Editor of production
project `zjnuqqtbapbpudsjbpif`. They reported:

```text
Success. No rows returned
```

The existing SQL smoke test verifies database joins, rejected foreign keys,
trip-to-itinerary deletion cascades, and preservation of related location data.
Its fixtures are rolled back. This production result is developer-reported;
the development-only ORM verifier was not run against production.

## Completion evidence links

No schema changes were needed: the Sprint 1 migration already defines the
required columns and foreign keys. No existing migration was edited or replayed.

The development, deployment smoke, and production database checks have passed
as recorded above. Completion records:

- [Merged implementation PR #37](https://github.com/relax-mode/lagaw/pull/37):
  the developer reported approved review and all four checks passing.
- [Deploy Backend run](https://github.com/relax-mode/lagaw/actions/runs/39455881955):
  the inspected screenshot shows the deployment and locations smoke test passed.
- Production SQL smoke test: the developer-reported result above.

Publish this post-deployment documentation update through a reviewed PR, then
link the final verification record to
[issue #22](https://github.com/relax-mode/lagaw/issues/22) before closing it.
