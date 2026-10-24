# Issue #26 — manual itinerary association verification

Status: local offline, guarded development database, and guided development
Swagger/SQL verification have passed. PR/CI/review/merge, deployed acceptance
and actual hosted redeployment persistence remain pending.

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

Pending: PR URL, all required CI checks, disposable PostgREST/PostgreSQL
association test execution, teammate review and merge. Docker/PostgreSQL
executables were unavailable in the agent environment, so development success
does not claim that the disposable CI container has already run.

After reviewed merge, coordinate staging verification against development,
then authorized production deployment and independent hosted database checks.
The newer recorded policy requires manual production workflow dispatch on main;
the older pitch/Trip guide descriptions of automatic production deployment
remain a flagged discrepancy outside #26.

## Actual redeployment persistence and completion

Pending: serving revision IDs and deployment/run links; retrieve the same saved
hosted associations after a later revision, then confirm item removal remains
effective after a further revision while the catalog location is retained.
Local FastAPI restarts and a new local application/client do not satisfy this
hosted redeployment check.

Link the reviewed PR, passing CI run, deployed results and this evidence to #26.
Keep the issue open until its Definition of Done is satisfied.
