# #116 — Backend health, readiness, OpenAPI, and safe errors

Implemented by the FastAPI entry point in `backend/app/main.py`; source probes
are in `backend/app/health.py`.

## Public operational endpoints

| Endpoint | Success | Failure | Dependencies |
| --- | --- | --- | --- |
| `GET /health` | 200 `{"status":"ok"}` | none expected for a running ASGI process | Local application process only |
| `GET /ready` | 200 `{"status":"ready"}` | 503 `{"status":"not_ready"}` | Existing Supabase PostgREST `locations` read, bounded to 2 seconds |

These endpoints require no bearer token and expose no database names, secrets,
connection strings, table content, request inputs or stack traces. `/health`
is liveness, not a promise of database or AI functionality. `/ready` is a
lightweight read-only database readiness probe; it intentionally does not call
paid DeepSeek, verify AI balances, or depend on optional recommendation quality.

A missing or malformed database configuration, network outage, non-200 status,
or malformed PostgREST response makes readiness fail closed with 503. The
readiness check uses the same backend-only Supabase credentials already used
by `GET /locations`. No new environment variables are introduced. It never
writes data or alters the database.

`GET /locations` retains its existing pagination and response contract.
Invalid query parameters return 422 with sanitized error location, type and
message, excluding the raw submitted values. Other existing routes retain
their current validated request and provider-error contracts.

## API reference and architecture

- Machine-readable API reference: `GET /openapi.json`.
- Interactive reference: `GET /docs` (Swagger UI) and `GET /redoc`.
- Current application: Flutter → FastAPI (Cloud Run) → Supabase PostgreSQL
  (PostgREST); only FastAPI calls the DeepSeek extraction provider.
- `GET /locations` is public. `/api/v1/trips`, onboarding preferences,
  interactions, itinerary generation, recommendations and
  `POST /api/v1/preferences/extract` use the verified Supabase access token
  security scheme and backend-resolved profile ownership.
- The extraction API returns a draft for confirmation, not a saved trip.
  It handles bad requests (422), provider failures (502/503/504), and
  provider 429 without exposing raw provider data. Local shared rate limiting
  from issue #114 must be integrated before its 429 behavior is documented
  as deployed.

## Verification and safe rollout

Run from `backend/`:
```sh
python -m pytest -v -m "not db"
python -m ruff check .
```

`backend/test_health.py` uses mocked PostgREST responses, tests both public
probes and failure cases, checks response redaction, and inspects OpenAPI.
No external credentials, hosted database calls, or paid AI requests are needed.

The probes are additive. They do not change the existing CI/CD deployment
stages or replace the staging and production smoke checks in `PIPELINE.md`.
After review, use the approved staging deployment and test `/health` and
`/ready`, then explicitly authorize any production-affecting merge.
Rollback is to the previous reviewed Cloud Run revision; no schema changes
are required for this issue.
