# Issue #23: trip create, list, and retrieve verification

- Implementation prepared: October 21, 2026 (Asia/Manila).
- Scope: POST/list/retrieve API and controlled demo-user context only.
- Development target: `vnpkyvtbupnquvirzlzp`.
- Production target for later reviewed deployment: `zjnuqqtbapbpudsjbpif`.
- Procedure: [trip API guide](../trips-api.md).

The developer reported all 56 backend tests passing in 1.493 seconds and Ruff
returning `All checks passed!`. Python compilation and `git diff --check` both
completed without output. These are offline results, not hosted database
verification. Live development results are recorded below as reported.

The developer reported `Success. No rows returned` after running the documented
development fixture SQL: two synthetic demo profiles and the other-owner trip
`23000000-0000-4000-8000-000000000004`. This establishes fixture setup only;
trip API requests and persistence verification remain pending.

| Check | Status |
| --- | --- |
| Local backend regression tests | Passed: developer reported 56 tests, 1.493s, OK |
| Ruff lint | Passed: developer reported All checks passed! |
| Python compilation, whitespace check | Passed: developer reported both commands completed without output |
| Development POST persists an owned trip in PostgreSQL | Passed: HTTP 201 and independent development SQL confirmation reported |
| Development list contains only configured owner's trips | Passed: developer supplied HTTP 200 containing the created trip and excluding the other-owner fixture |
| Development retrieve returns saved details | Passed: developer supplied HTTP 200 with matching saved details |
| Missing and other-owner trip IDs both return 404 | Passed: developer reported identical HTTP 404 responses for both IDs |
| Invalid dates/budgets/body return 422 without inserting rows | Passed: reversed dates, negative/reversed budgets, missing title, and owner override returned 422; SQL returned only the two expected fixtures |
| Malformed trip UUID rejected | Offline backend check passed; Swagger blocked the live malformed UUID before sending a request |
| Missing/invalid bearer token returns 401 | Offline checks passed; live missing-token response matched the expected rejection message (HTTP status not supplied); live incorrect-token check not run |
| Saved trip survives page refresh and backend restart | Passed: developer reported HTTP 200 with matching details after browser refresh, reauthorization, and backend restarts |
| Reviewed, merged PR and passing GitHub CI | Pending |
| Deployed API acceptance checks | Pending |
| Saved trip survives a subsequent deployment | Pending |
| Evidence linked to issue #23 | Pending |

Add actual safe outputs and links as each check completes. Include trip IDs and
synthetic trip details only; never record tokens, authorization headers, backend
keys, connection strings, or environment-file contents.

## Development create — October 21, 2026

Independent development SQL confirmation was subsequently reported: querying
trips for both synthetic demo users returned exactly two IDs,
`7c51b2e1-5111-408f-802a-981ce2da9761` (API-created trip) and
`23000000-0000-4000-8000-000000000004` (other-owner fixture).
This confirms the API-created trip exists in PostgreSQL and no extra rows from
the guided invalid requests were present for either demo user.

The developer confirmed the server was running and the Swagger demo context was
authorized, then supplied HTTP **201** from `POST /api/v1/trips`. The response
Date header was `Wed, 21 Oct 2026 08:11:41 GMT`. Safe response body:

```json
{
  "title": "Bacolod afternoon",
  "start_date": "2026-11-01",
  "end_date": "2026-11-01",
  "budget_min": "100",
  "budget_max": "500.5",
  "transportation_mode": "walking",
  "group_type": "solo",
  "preferred_tags": ["heritage", "cafe"],
  "id": "7c51b2e1-5111-408f-802a-981ce2da9761",
  "user_id": "23000000-0000-4000-8000-000000000001",
  "status": "draft",
  "estimated_total_cost": null
}
```

The response carries the configured demo owner, generated trip UUID, database
draft status, and submitted details. Decimal strings may omit trailing zeroes
without changing their monetary values. Listing, retrieval, independent SQL
confirmation, and restart/deployment persistence checks remain pending.

## Development list and token rotation — October 21, 2026

The developer supplied HTTP **200** from
`GET /api/v1/trips?limit=10&offset=0`. The response contained one item, saved trip
`7c51b2e1-5111-408f-802a-981ce2da9761`, with the same details as the create
response, `limit: 10`, and `offset: 0`. The other-owner fixture
`23000000-0000-4000-8000-000000000004` was absent.

The shared Swagger output also exposed the temporary development demo bearer
token. Verification was paused and the developer confirmed rotation after being
guided to stop FastAPI, generate a replacement token, restart, and reauthorize
Swagger. No token value is recorded here. Subsequent evidence must exclude Curl
sections and request headers. Rejection of the old token was not independently
verified.

## Development retrieve after restart — October 21, 2026

After confirming completion of the token-rotation procedure, including the
FastAPI restart, the developer supplied HTTP **200** from
`GET /api/v1/trips/7c51b2e1-5111-408f-802a-981ce2da9761`.
The response matched the recorded create response: same UUID, configured demo
owner, title, dates, budgets, transportation, group, tags, draft status, and null
estimated total cost. This records successful retrieval and persistence across
the reported local backend restart. Browser-refresh and redeployment persistence
checks remain separate and pending.

## Development missing and inaccessible trips — October 21, 2026

The developer reported HTTP **404** for both of these GET requests:

- Other-owner fixture: `/api/v1/trips/23000000-0000-4000-8000-000000000004`.
- Unused UUID: `/api/v1/trips/23000000-0000-4000-8000-000000000099`.

Both returned the same safe response, without exposing another owner's details:

```json
{"detail": "Trip not found."}
```

## Development validation — October 21, 2026

The developer supplied HTTP **422** with these safe validation errors:

| Submitted case | Error location | Message | Type |
| --- | --- | --- | --- |
| Start `2026-11-01`, end `2026-10-31` | `body` | Value error, end_date must be on or after start_date. | `value_error` |
| `budget_min: "-1.00"` | `body.budget_min` | Input should be greater than or equal to 0 | `greater_than_equal` |
| Omitted title | `body.title` | Field required | `missing` |
| Minimum budget `600.00`, maximum `500.00` | `body` | Value error, budget_max must be greater than or equal to budget_min. | `value_error` |
| Client-supplied other-owner `user_id` | `body.user_id` | Extra inputs are not permitted | `extra_forbidden` |

The reported responses omitted submitted values and validator context, as
intended. Independent confirmation that invalid requests inserted no rows is
pending.

The developer attempted `not-a-uuid` in Swagger's `trip_id` input. Swagger
displayed `Value must be a Guid` and prevented submission. This is client-side
validation, not a live backend UUID rejection result; backend rejection is
covered by the passed offline suite.

## Development request without bearer token — October 21, 2026

Opening `http://127.0.0.1:8000/api/v1/trips` directly in a new browser tab,
without Swagger's authorization header, returned this developer-reported body:

```json
{"detail": "A valid trip demo bearer token is required."}
```

The browser response status was not supplied. The offline tests establish 401
and the bearer challenge for missing and incorrect tokens; this live check
records the matching rejection message without assuming an observed status.

## Development browser-refresh persistence — October 21, 2026

Following the guided backend restart, browser refresh, and Swagger
reauthorization, the developer supplied HTTP **200** for saved trip
`7c51b2e1-5111-408f-802a-981ce2da9761`. All fields matched the create response,
including the demo owner and exact monetary values. Together with the SQL query,
this establishes the recorded development persistence checks across refresh and
local restarts. Persistence across a hosted redeployment remains pending.
