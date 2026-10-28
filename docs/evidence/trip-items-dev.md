# Issue #26 — manual itinerary association verification

Status: local offline, guarded development database, deployed staging API and
hosted redeployment checks against development Supabase, and deployed production
API/database checks have passed as reported. PR #60 review and passing CI were
reported, and its merge is confirmed at `708707f`. Staging persistence was
verified across a Cloud Run revision change; no production redeployment was
performed. The remaining work is to publish and link this evidence update to
issue #26.

## Scope and environment

- Branch: `feat/trip-itinerary-items`, based on `main` at `2156388`.
- Three manual association endpoints using the existing Trip demo context,
  backend-only Supabase Data API, and existing trip/item/location schema.
- Development: `vnpkyvtbupnquvirzlzp`. All reported live checks below used development.
- Production: `zjnuqqtbapbpudsjbpif`; no production verification/change claimed.
- Existing `.env` preserved. Demo settings were supplied through the PowerShell
  process, and the automatic verifier supplies/restores its own temporary context.
- Issue #29's stash remains separate. No frontend, AI ranking (#53), generated
  schedule/persistence (#54), or route optimization work is included.
- Existing unique trip/day/order positions reject repeated insertions. A location
  may be revisited at another position/day; no migration was required.

## Offline checks

Agent-run on October 24, 2026:

- Pytest from `backend/`: **97 passed, 1 warning in 3.33s**.
- Ruff: `All checks passed!`.
- `git diff --check`: passed; Git emitted CRLF normalization notices.
- Tests cover request/response validation, owner scoping, authentication, safe
  failures, conflicts, deletion filters, pagination, CORS, production refusal
  before requests, and complete cleanup attempts after fixture setup/delete failure.
- The warning is the existing non-fatal Starlette HTTPX deprecation.
- No hosted database call was made by the agent.

## Guarded development database checks

On October 24, 2026, the developer supplied the complete successful output of
`python backend/verify_trip_items.py` against guarded development Supabase:

```text
PASS: Multiple associations, nested locations, ordering and PostgreSQL persistence.
PASS: Repeated additions conflict atomically; revisits at other positions are allowed.
PASS: Invalid associations, owner isolation, authentication and cross-trip removal.
PASS: PostgreSQL rejects invalid trip and location foreign keys.
PASS: Removal preserves locations; committed changes survive a new application/client.
PASS: Exact synthetic fixtures cleaned and absence verified.
```

Synthetic fixture owners were `8ec74608-e730-4472-bc0f-ade10aabf96a` and
`908c0093-90c9-4e9c-8ccc-7ffef09867c6`. Cleanup and absence checks passed.
The Starlette warning was non-fatal. The verifier uses unique users/trips/locations,
exact-UUID cleanup, and real Data API/PostgreSQL requests. A new application/client
read is distinguished from an actual hosted redeployment.

## Guided development Swagger and independent SQL checks

All outcomes below were supplied by the developer on October 24, 2026.

### Verification records

| Record | UUID / saved fields |
| --- | --- |
| New #26 trip | `391d0cca-ddf6-454c-8ad4-941e59288f00` |
| Trip owner | `23000000-0000-4000-8000-000000000001` |
| Trip details | `Issue 26 development verification`; November 1–2, 2026; budgets 0–500 PHP; draft |
| Cathedral location | `1a3bca09-5532-5de6-8587-2440c4e5830d` |
| Cathedral item, later removed | `0d6edde0-a915-4d03-833a-a078cc91ced1`; day 1/order 1 |
| Museum location | `61bf94ab-6ec0-5ec3-8451-b575ee06169e` |
| Museum item, retained | `b378e1f4-c286-4953-a5a7-20ce168a95a8`; day 1/order 2 |
| Existing protected trip | `23000000-0000-4000-8000-000000000004`; title `Other user fixture` |
| Protected trip owner | `23000000-0000-4000-8000-000000000002` |

### API and SQL outcomes

| Check | Reported result |
| --- | --- |
| Create a new saved trip | POST Trip returned 201 with the server-selected demo owner |
| Empty itinerary | GET items returned 200 with `items: []`, limit 10, offset 0 |
| Add Cathedral | POST items returned 201, day 1/order 1, matching nested location details |
| Add Museum | POST items returned 201 with a distinct item ID, day 1/order 2 and matching location details |
| Retrieve both saved items | GET returned 200, original UUIDs and day/order sorting |
| Repeat Cathedral insertion | 409 with the safe occupied-position/association-changed message |
| Preservation after repeat | GET returned exactly the original two item IDs/details |
| Nonexistent location | UUID `26000000-0000-4000-8000-000000000099` returned 404, `Active location not found.` |
| Zero visit order | 422, `body.visit_order` / `greater_than_equal`, requiring at least 1 |
| Day outside the two-day trip | Day 3 returned 422, `body.day_number` / `value_error`, requiring a day within the trip dates |
| Malformed location UUID | `not-a-uuid` returned backend HTTP 422, `body.location_id` / `uuid_parsing` |
| Confirm protected parent exists | Development SQL returned the other-owner trip, owner UUID and title above |
| Other-owner list and add | GET and POST returned 404, `Trip not found.` |
| Delete protected-parent check | Other-owner trip paired with the owned Cathedral item returned 404, `Trip not found.` |
| Independent SQL item preservation | Itinerary/location join returned exactly the original two items at orders 1 and 2 |
| Independent protected-trip preservation | Separate SQL query returned the original other-owner trip UUID, owner and title |
| Unauthorized GET, POST and DELETE | Each returned 401, `A valid trip demo bearer token is required.`, in a separate private Swagger window |
| Preservation after unauthorized attempts | Authorized GET returned 200 and the two original item IDs/details unchanged |
| Addition restart/refresh persistence | After FastAPI restart and Swagger refresh/reauthorization, GET returned 200 with both original items/details |
| Cathedral item removal | Authorized DELETE returned 204; an independently observed empty body was not separately reported |
| Post-removal list | GET returned 200 with only the unchanged original Museum item at day 1/order 2 |
| Repeated item removal | 404, `Itinerary item not found.` |
| Underlying Cathedral location preserved | Development SQL returned its original UUID, `San Sebastian Cathedral`, `is_active: true` |
| Removal restart/refresh persistence | After another FastAPI restart and Swagger refresh/reauthorization, GET returned 200 with only the original Museum item at day 1/order 2 |

The manual delete protected-parent check used an owned item under a mismatched
other-owner parent. The automatic development verifier separately checked an
actual other-owner child and cross-trip removal. No rejected request was counted
as a successful addition. The original protected fixture was not modified.
The manual verification trip and Museum item remain for traceability; automatic
verifier fixtures were cleaned.

## CI, review and deployed checks

[PR #60](https://github.com/relax-mode/lagaw/pull/60) was approved by a teammate
and passed all checks, as reported by the developer. The merge is confirmed in
local Git history at `708707f` (`Merge pull request #60 from
relax-mode/feat/trip-itinerary-items`). The evidence follow-up branch is
`docs/issue-26-deployed-evidence`. The exact successful PR CI run URL remains
to be linked; GitHub job logs were not independently accessible to the agent.

The developer supplied logs from an earlier staging run,
[39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096).
The `Deploy staging Flutter Web` step failed: Wrangler 4.151.0 reported
Cloudflare authentication code 10000 and `Invalid access token` code 9109.
The workflow at the time used `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`
from GitHub Actions secrets in the protected staging environment. The logs
establish rejected Cloudflare authentication, but do not establish whether the
token was revoked, expired, copied incorrectly, or scoped incorrectly. No
secret values were requested/read and no credentials or workflow were changed.
This older run does not establish the outcome of the new PR #60 merge run.
The later staging recovery is recorded below; this is a historical failure.

### October 28 resumption and updated deployment records

The evidence branch and local main were updated to `d30ef03` after preserving
this issue's notes separately from the older #29 stash. Current source documents
record these completed deployments:

- [Staging recovery run 40163792050](https://github.com/relax-mode/lagaw/actions/runs/40163792050),
  commit `4c844c4`: staging backend/API smoke and Flutter Web/web smoke passed
  after the Cloudflare token was replaced. See the
  [staging acceptance record](staging-acceptance-2026-10-26.md).
- [Promotion run 40482703372](https://github.com/relax-mode/lagaw/actions/runs/40482703372):
  staging and production promotion passed on October 27, according to the
  [CI/CD evidence](ai-ci-cd-2026-10-26.md#4-production-promotion).

These are committed team evidence records reviewed during resumption; live
cloud revision/traffic status has not been independently queried in this session.
The updated pitch and pipeline agree: qualifying main pushes deploy staging,
then automatically promote production after checks pass. Manual dispatch is
reserved for production recovery. The earlier deployment-policy discrepancy
has therefore been superseded by the team's reviewed changes.

Staging uses development Supabase `vnpkyvtbupnquvirzlzp` with dedicated demo
profile `16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c` and a separate staging token.
The old local demo owner's verification trip will not be visible through this
staging owner context. Verify new synthetic staging-owned trips and associations
on the deployed API before proceeding to production, and keep both environment
records distinct. Existing `.env` contents remain untouched.

The shared staging/production smoke checks establish deployment health and Trip
access. Explicit #26 deployed add/list/remove/location-preservation checks and
actual hosted-redeployment evidence are still required. No additional API
implementation or unrelated CI repair is currently indicated.

### Deployed staging Swagger, October 28

The developer reported that the deployed staging Swagger page loads and shows
all three #26 POST, GET and DELETE item endpoints. This confirms route visibility;
authenticated requests, database writes and hosted persistence remain pending.
- **October 28 — staging trip creation:** The developer supplied HTTP 201
  for `Issue 26 staging verification`, trip
  `6a319067-7046-469a-8359-e3562b633c82`, with the documented staging demo
  owner `16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c`, November 1–2 dates, budgets
  0–500 PHP, draft status and null estimated cost. The token was accepted by
  the deployed API. Initial itinerary listing and item verification are next.
- **October 28 — empty staging itinerary:** The developer supplied HTTP 200
  for GET items on staging trip `6a319067-7046-469a-8359-e3562b633c82`,
  returning `{"items": [], "limit": 10, "offset": 0}`. The first deployed
  location association is next.
- **October 28 — staging Cathedral addition:** The developer supplied HTTP 201
  from POST items for staging trip `6a319067-7046-469a-8359-e3562b633c82`.
  Item `4ee5ed83-8935-48ea-9a79-2099ae6848c5` references Cathedral location
  `1a3bca09-5532-5de6-8587-2440c4e5830d` at day 1/order 1; the nested location
  ID and details matched. A second association and retrieval are next.
- **October 28 — staging Museum addition:** The developer supplied HTTP 201
  from POST items for staging trip `6a319067-7046-469a-8359-e3562b633c82`.
  Item `6f6f07db-b9f7-4d06-8315-f0f44912ea45` references Museum location
  `61bf94ab-6ec0-5ec3-8451-b575ee06169e` at day 1/order 2; nested location
  ID and details matched. A separate GET confirming both saved items is next.
- **October 28 — staging item retrieval:** The developer supplied HTTP 200
  from GET items for trip `6a319067-7046-469a-8359-e3562b633c82`. The response
  contained Cathedral item `4ee5ed83-8935-48ea-9a79-2099ae6848c5` at day 1/order 1,
  followed by Museum item `6f6f07db-b9f7-4d06-8315-f0f44912ea45` at day 1/order 2.
  Both included their matching nested location details. Duplicate-position
  rejection and subsequent persistence checks remain next.
- **October 28 — staging duplicate position:** The developer supplied HTTP 409
  after repeating the Cathedral POST at day 1/order 1 for trip
  `6a319067-7046-469a-8359-e3562b633c82`. The safe response reported an occupied
  position or changed association. Independent development SQL confirmation
  of the two saved items after this rejected request is next.
- **October 28 — independent staging data check:** The developer supplied the
  development Supabase SQL join result for staging trip
  `6a319067-7046-469a-8359-e3562b633c82` after the rejected duplicate. It
  returned exactly Cathedral item `4ee5ed83-8935-48ea-9a79-2099ae6848c5` at
  day 1/order 1 and Museum item `6f6f07db-b9f7-4d06-8315-f0f44912ea45` at
  day 1/order 2. The staging-created associations persisted in development and
  survived the rejected duplicate. Capture the current staging serving revision
  before removal and a later redeployment persistence check.
- **October 28 — staging revision baseline:** The developer reported that Cloud
  Run service `lagaw-api-staging` was serving revision
  `lagaw-api-staging-00017-6ct` after the staging additions and duplicate check.
  A later different serving revision and matching item reads are needed to prove
  hosted redeployment persistence. Cathedral item removal is next.
- **October 28 — staging item removal:** The developer reported HTTP 204 for
  DELETE of Cathedral item `4ee5ed83-8935-48ea-9a79-2099ae6848c5` from
  staging trip `6a319067-7046-469a-8359-e3562b633c82`. A separate GET confirming
  the remaining item and independent SQL confirmation of location preservation
  are next. The response body was not separately reported.
- **October 28 — staging post-removal listing:** The developer supplied HTTP
  200 from GET items for trip `6a319067-7046-469a-8359-e3562b633c82`. Exactly
  the original Museum item `6f6f07db-b9f7-4d06-8315-f0f44912ea45` remained
  at day 1/order 2 with matching nested location details; Cathedral item
  `4ee5ed83-8935-48ea-9a79-2099ae6848c5` was absent. Independent SQL location
  preservation and subsequent hosted revision persistence remain pending.
- **October 28 — staging removal preserved location:** The developer supplied
  the development Supabase SQL result showing location
  `1a3bca09-5532-5de6-8587-2440c4e5830d` still exists, is named
  `San Sebastian Cathedral`, and remains active after removal of staging item
  `4ee5ed83-8935-48ea-9a79-2099ae6848c5`. The remaining Museum association
  was confirmed through staging GET. Hosted-revision persistence is pending.
- **October 28 — post-removal serving baseline:** The developer confirmed
  `lagaw-api-staging-00017-6ct` remained the staging revision receiving 100%
  traffic after the Cathedral item was removed and the Museum item retained.
  A subsequent deployment serving a different revision, followed by reads of
  both states, is still required. No deployment was initiated for this check.
- **October 28 — staging nonexistent location:** The developer supplied HTTP
  404 after POSTing location `26000000-0000-4000-8000-000000000099` at day
  1/order 3 for staging trip `6a319067-7046-469a-8359-e3562b633c82`.
  The response was `{"detail":"Active location not found."}`. This deployed
  invalid-association check passed. An unauthenticated staging GET is next.
- **October 28 — staging unauthorized GET:** In an unauthorized private
  Swagger window, the developer supplied HTTP 401 for GET items on staging
  trip `6a319067-7046-469a-8359-e3562b633c82`, with the safe valid-demo-token
  required message. The deployed GET route rejects unauthenticated access.
  Unauthorized POST/DELETE and owner isolation were verified by the earlier
  guarded development suite; this staging check covers GET only.
- **October 28 — new staging revision:** The developer reported redeploying
  the staging service and observing revision `lagaw-api-staging-00018-qs2`.
  The previous 100% serving baseline was `lagaw-api-staging-00017-6ct`. Traffic
  allocation and subsequent reads of the retained and removed items have not yet
  been reported; the new revision's existence alone does not prove persistence.
- **October 28 — new staging revision serving:** The developer confirmed
  `lagaw-api-staging-00018-qs2` receives 100% of staging traffic. This differs
  from the pre-redeployment baseline `lagaw-api-staging-00017-6ct`. The API
  must now be queried to verify the retained and removed item states.
- **October 28 — staging post-redeployment persistence:** After the developer
  reported staging revision `lagaw-api-staging-00018-qs2` receiving 100% traffic
  instead of baseline `lagaw-api-staging-00017-6ct`, the developer supplied HTTP
  200 from GET items for staging trip `6a319067-7046-469a-8359-e3562b633c82`.
  Exactly the original Museum item `6f6f07db-b9f7-4d06-8315-f0f44912ea45`
  remained at day 1/order 2 with matching location details, and the previously
  removed Cathedral item `4ee5ed83-8935-48ea-9a79-2099ae6848c5` remained absent.
  This verifies retained and removed association states across the staging backend
  revision change. A follow-up SQL read of the Cathedral location is next;
  production acceptance and evidence publication remain pending.
- **October 28 — location after staging redeployment:** The developer supplied
  the development SQL result confirming Cathedral location
  `1a3bca09-5532-5de6-8587-2440c4e5830d` remains present and active after
  staging revision `lagaw-api-staging-00018-qs2` took 100% traffic. Combined
  with the post-redeployment GET, this confirms the retained Museum association,
  removed Cathedral association and preserved Cathedral location across the
  staging backend revision change. Production-specific API acceptance and
  publication/linkage of evidence remain pending.
### Production Swagger verification, October 28

- **Route visibility:** The developer reported that the production Swagger page
  loads and displays all three #26 item endpoints. This is a read-only visibility
  check; endpoint acceptance and database verification are recorded below.
- **October 28 — production trip creation:** The developer supplied HTTP 201
  for `Issue 26 production verification`, trip
  `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`, owned by synthetic demo profile
  `23000000-0000-4000-8000-000000000001`. Dates are November 1–2, budgets
  0–500 PHP, status draft and estimated total cost null. This production trip
  is separate from staging trip `6a319067-7046-469a-8359-e3562b633c82`.
  Empty-item listing and production item verification are next.
- **October 28 — empty production itinerary:** The developer supplied HTTP 200
  from production GET items for trip `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`,
  returning `{"items": [], "limit": 10, "offset": 0}`. The first production
  location association is next.
- **October 28 — production Cathedral addition:** The developer supplied HTTP
  201 from POST items for production trip `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`.
  Item `8becf135-baa2-483a-883a-7dddc3640ff5` references Cathedral location
  `1a3bca09-5532-5de6-8587-2440c4e5830d` at day 1/order 1, with matching nested
  location details. A second association and subsequent production read are next.
- **October 28 — production Museum addition:** The developer supplied HTTP 201
  from POST items for production trip `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`.
  Item `2e9746bc-c478-4e46-b49a-833bb3dac190` references Museum location
  `61bf94ab-6ec0-5ec3-8451-b575ee06169e` at day 1/order 2, with matching nested
  location details. A separate production GET confirming both items is next.
- **October 28 — production item retrieval:** The developer supplied HTTP 200
  for production trip `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`, listing Cathedral
  item `8becf135-baa2-483a-883a-7dddc3640ff5` at day 1/order 1 followed by
  Museum item `2e9746bc-c478-4e46-b49a-833bb3dac190` at day 1/order 2, each
  with matching nested location details. Production duplicate-position handling
  and independent SQL persistence verification are next.
- **October 28 — production duplicate position:** The developer supplied HTTP
  409 after repeating the Cathedral POST at day 1/order 1 for production trip
  `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`. The safe response reported an
  occupied position or changed association. Independent production SQL
  confirmation of the two saved items after the rejected request is next.
- **October 28 — independent production data check:** The developer supplied
  the production Supabase SQL join result for trip
  `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc` after the rejected duplicate. It
  returned exactly Cathedral item `8becf135-baa2-483a-883a-7dddc3640ff5`
  at day 1/order 1 and Museum item `2e9746bc-c478-4e46-b49a-833bb3dac190`
  at day 1/order 2. Both deployed production associations persisted and were
  retained after the rejected repeat. Production item removal is next.
- **October 28 — production item removal:** The developer reported HTTP 204
  for DELETE of Cathedral item `8becf135-baa2-483a-883a-7dddc3640ff5` from
  synthetic production trip `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`. A separate
  GET confirming the Museum item and independent production SQL confirmation
  of Cathedral location preservation are next. The response body was not
  separately reported.
- **October 28 — production post-removal listing:** The developer supplied
  HTTP 200 from GET items for production trip
  `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc`. Exactly the original Museum item
  `2e9746bc-c478-4e46-b49a-833bb3dac190` remained at day 1/order 2 with
  matching nested location details; Cathedral item
  `8becf135-baa2-483a-883a-7dddc3640ff5` was absent. Independent production
  SQL confirmation of Cathedral location preservation follows.
- **October 28 — production location after removal:** The developer supplied
  the production SQL result for Cathedral location
  `1a3bca09-5532-5de6-8587-2440c4e5830d`: it remains present and active after
  item `8becf135-baa2-483a-883a-7dddc3640ff5` was deleted. This confirms that
  removing the itinerary association did not delete its underlying location.
- **October 28 — production invalid location:** The developer supplied HTTP 404
  for a POST using nonexistent location UUID
  `00000000-0000-0000-0000-000000000000`, with detail `Active location not
  found.` The deployed production API rejects invalid location associations.
- **October 28 — production unauthenticated request:** The developer supplied
  HTTP 401 for GET items on production trip
  `13035281-7a2c-4f55-9e6b-a4bd7ebb73bc` without authorization, with detail
  `A valid trip demo bearer token is required.` No credential value was shared.
## Actual redeployment persistence and completion

Staging hosted persistence passed as reported across revisions
`lagaw-api-staging-00017-6ct` and `lagaw-api-staging-00018-qs2`: the retained
Museum association persisted, the removed Cathedral association remained absent,
and development SQL confirmed the Cathedral location remained active. The latter
revision was manually redeployed by the developer directly through Cloud Run;
the user reported it received 100% of staging traffic.

Production deployed API and database acceptance passed as reported. The deployed
API created and retrieved two ordered location associations, rejected a repeated
position with HTTP 409, removed one association with HTTP 204 while preserving
its active location, rejected a nonexistent location with HTTP 404, and rejected
an unauthenticated read with HTTP 401. Production Supabase independently
confirmed both saved rows before removal and the underlying location after
removal. Staging and production records refer to separate Supabase projects and
separate synthetic demo trips.

No production redeployment was performed or claimed. Hosted persistence across
a Cloud Run revision change was verified in staging against development
Supabase. PR #60 review, passing checks and merge were reported; merge is
confirmed at `708707f`. The exact successful PR CI run URL was not supplied.
Remaining: publish this evidence update through a reviewed documentation PR and
link the merged evidence to issue #26.

Link the reviewed PR, passing CI run, deployed results and this evidence to #26.
Keep the issue open until its Definition of Done is satisfied.
