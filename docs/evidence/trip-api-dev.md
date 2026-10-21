# Issue #23: trip create, list, and retrieve verification

- Implementation prepared: October 21, 2026 (Asia/Manila).
- Scope: POST/list/retrieve API and controlled demo-user context only.
- Development target: `vnpkyvtbupnquvirzlzp`.
- Production target, verified after development: `zjnuqqtbapbpudsjbpif`.
- Procedure: [trip API guide](../trips-api.md).

The developer reported all 56 backend tests passing in 1.493 seconds and Ruff
returning `All checks passed!`. Python compilation and `git diff --check` both
completed without output. These are offline results, not hosted database
verification. Live development results are recorded below as reported.

The developer reported `Success. No rows returned` after running the documented
development fixture SQL: two synthetic demo profiles and the other-owner trip
`23000000-0000-4000-8000-000000000004`. This establishes fixture setup only;
the subsequent API and persistence results are recorded below.

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
| Reviewed, merged PR and passing GitHub CI | Passed as reported: teammate reviewed and merged PR #39; developer confirmed all required [PR checks](https://github.com/relax-mode/lagaw/pull/39/checks) passed on October 22 |
| Production demo-context configuration | Developer reported green/ready Cloud Run revision after adding demo user ID and token secret version 1 |
| Independent production PostgreSQL persistence | Passed: developer confirmed the production SQL query returned the created trip |
| Deployed API acceptance checks | Developer reported POST 201, list/retrieve 200, negative-budget 422, missing-trip 404, and missing-token 401 |
| Saved trip survives a subsequent deployment | Passed: developer supplied HTTP 200 with identical saved details after serving revision changed from 00005-r75 to 00006-8vk |
| Evidence linked to issue #23 | Pending |

All results below are developer-reported; the agent could not independently
access the private GitHub pages or deployed host. Functional verification is
complete as reported. Publishing this evidence through a reviewed documentation
PR and linking it to issue #23 remain pending. This record contains synthetic
trip details only; credentials and authorization headers are excluded.

## Reviewed merge and production setup — October 21, 2026

The developer subsequently confirmed receiving Google Cloud access from the
DevOps teammate, generating a separate production demo token privately in
PowerShell, and creating Secret Manager secret `TRIP_DEMO_TOKEN` in project
`relax-mode-lagaw`. The developer holds the generated token; its value is not
recorded. The developer also confirmed saving the secret-level Secret Manager
Secret Accessor grant for runtime identity
`lagaw-api@relax-mode-lagaw.iam.gserviceaccount.com`. The completed Cloud Run
mapping and deployed verification are recorded below.

The developer supplied [PR #39](https://github.com/relax-mode/lagaw/pull/39),
reported teammate review, and confirmed merging it to `main`. They subsequently
reported every job passed in the resulting
[Deploy Backend job](https://github.com/relax-mode/lagaw/actions/runs/39573957458/job/119134734364).
These GitHub pages could not be fetched from this session; review, merge, and
deployment success are developer-reported. On October 22, the developer also
confirmed all required [PR #39 checks](https://github.com/relax-mode/lagaw/pull/39/checks)
passed.

After the successful development checks and reported deployment, the developer
ran the guided synthetic profile insert in production project
`zjnuqqtbapbpudsjbpif` and reported the returned UUID
`23000000-0000-4000-8000-000000000001`. This provisions the dedicated production
demo profile. Production backend settings, API requests, and persistence across
a subsequent hosted deployment were then verified as recorded below. No schema
migration was added or applied.

## Production Cloud Run configuration — October 21, 2026

The developer supplied the public Swagger URL
`https://lagaw-api-663710289405.asia-southeast1.run.app/docs` and confirmed
authorization with the separate production demo token. The browsing tool could
not access this host; live results below are developer-reported.

### Production create

The developer supplied HTTP **201** from the public `POST /api/v1/trips` with
this safe response:

```json
{
  "title": "Production API verification",
  "start_date": "2026-11-01",
  "end_date": "2026-11-01",
  "budget_min": "100",
  "budget_max": "500.5",
  "transportation_mode": "walking",
  "group_type": "solo",
  "preferred_tags": ["heritage", "cafe"],
  "id": "9c45ad80-3762-4203-95ac-a97128fd68a2",
  "user_id": "23000000-0000-4000-8000-000000000001",
  "status": "draft",
  "estimated_total_cost": null
}
```

### Production list and retrieve

The developer supplied HTTP **200** from the public
`GET /api/v1/trips?limit=10&offset=0`, containing exactly one item: production
trip `9c45ad80-3762-4203-95ac-a97128fd68a2`, with the same saved details,
`limit: 10`, and `offset: 0`. Development trip
`7c51b2e1-5111-408f-802a-981ce2da9761` was absent.

The developer then supplied HTTP **200** from public
`GET /api/v1/trips/9c45ad80-3762-4203-95ac-a97128fd68a2`, with every field
matching the recorded production create response. The developer subsequently
confirmed that the targeted SQL query in production Supabase project
`zjnuqqtbapbpudsjbpif` returned this same trip, independently confirming that
the deployed API saved it in production PostgreSQL. Persistence across a
subsequent hosted deployment is recorded in the final section.

### Production error handling

The developer supplied these results from the public Swagger page:

- Negative `budget_min: "-1.00"`: HTTP **422**, location `body.budget_min`,
  message `Input should be greater than or equal to 0`, type
  `greater_than_equal`.
- GET unused UUID `23000000-0000-4000-8000-000000000099`: HTTP **404**,
  `{"detail": "Trip not found."}`.
- After Swagger logout, GET the trip list without a bearer token: HTTP **401**,
  `{"detail": "A valid trip demo bearer token is required."}`.

These establish deployed representative validation, missing-resource, and
unauthenticated-access responses without recording credentials.

The developer reported adding `TRIP_DEMO_USER_ID` with synthetic profile UUID
`23000000-0000-4000-8000-000000000001` and referencing Secret Manager secret
`TRIP_DEMO_TOKEN`, version `1`, as the same-named environment variable in
`lagaw-api`. After reviewing the configuration and redeploying, the developer
reported a green check for the new Cloud Run revision. The runtime secret-access
grant was confirmed earlier. No token value is recorded. The public service URL
and API results appear above; the serving revision change and persistence check
appear in the final section.

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
confirmation, and persistence results are recorded in this document.

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
the reported local backend restart. Browser-refresh and hosted redeployment
results are recorded separately below.

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
intended. The development SQL check recorded above returned only the two
expected trips after these requests, confirming no additional trip rows for
either synthetic demo user.

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
local restarts. Hosted redeployment verification is recorded separately below.

## Production redeployment — October 21, 2026

Before triggering the existing Deploy Backend workflow on `main`, the developer
identified `lagaw-api-00005-r75` as serving 100% of traffic. They then reported
the [subsequent deployment job](https://github.com/relax-mode/lagaw/actions/runs/39582693468/job/119163910998)
passed and identified `lagaw-api-00006-8vk` as the new serving revision. These
outcomes are developer-reported. The production trip was created before this
redeployment. After the revision change, the developer supplied HTTP **200**
from the public GET endpoint for original trip
`9c45ad80-3762-4203-95ac-a97128fd68a2`. Every field matched the recorded
production create response: title, dates, exact monetary values, transportation,
group, tags, configured demo owner, draft status, and null estimated total cost.
This establishes developer-reported persistence across the hosted redeployment.
Successful authenticated retrieval also confirms the demo-user/token settings
were retained by that deployment. The developer subsequently confirmed all
required PR #39 checks passed on October 22. Publication of this post-deployment
evidence through a reviewed documentation PR and linkage to issue #23 remain
pending.
