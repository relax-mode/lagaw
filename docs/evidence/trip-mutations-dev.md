# Issue #24 — trip update/delete verification

Issue: https://github.com/relax-mode/lagaw/issues/24

Prepared October 22, 2026 on `feat/trip-update-delete` after the developer
confirmed updating `main` and creating the branch. On October 22, 2026, the
developer reported all four offline checks passing and completed the guided
hosted development checks below, including actual itinerary cascading deletion.
The developer subsequently confirmed PR review, passing CI, merge, and backend
deployment. Development and production CRUD/cascade verification are complete
as reported. Final evidence publication and linkage to issue #24 remain pending.
Intermediate pending notes below describe what was known at each verification
step; the acceptance tables record the current results.

Guide: [development-first steps](../trip-mutations-api.md).

## Offline checks

| Check | Result |
| --- | --- |
| Backend unittest discovery (including focused #24 checks) | Developer-reported pass: 69 tests in 1.793 seconds, `OK` (October 22, 2026) |
| Backend Ruff | Developer-reported pass: `All checks passed!` |
| Python compilation | Developer reported all four commands completed; no compilation output/errors |
| `git diff --check` | Developer reported all four commands completed; no whitespace output/errors |

The tests use mocked HTTP and dummy settings. The stateful CRUD transport is not
a real database and cannot prove PostgreSQL persistence or cascading deletion.

## Development — `vnpkyvtbupnquvirzlzp`

On October 22, 2026, the developer reported
`PASS: development Supabase target and read connection verified.` from the
backend configuration/read check. Existing `.env` files were left unchanged;
the demo context was configured temporarily in PowerShell. No token was shared.

POST returned **201** for new synthetic trip
`c5f56c50-aedb-4806-ba19-765914302527`, owner
`23000000-0000-4000-8000-000000000001`, with these saved values:

```json
{
  "title": "Issue 24 development verification",
  "start_date": "2026-11-01",
  "end_date": "2026-11-02",
  "budget_min": "100",
  "budget_max": "500.5",
  "transportation_mode": "walking",
  "group_type": "solo",
  "preferred_tags": ["heritage", "cafe"],
  "status": "draft",
  "estimated_total_cost": null
}
```

The decimal strings preserve exact numeric values; trailing zeros are not
required.

The developer subsequently supplied **200** for the initial GET by UUID,
**200** for PATCH with only
`{"title":"Issue 24 updated verification"}`, and **200** for the following
GET of the same UUID. Both mutation/retrieval responses contained the updated
title; dates, budgets, transportation, group, tags, trip/owner IDs, status, and
estimated cost matched the original create response. This verifies the reported
partial-update result and saved retrieval. List, remaining update cases, and
deletion/cascade checks remain pending.

The developer then supplied **200** for a PATCH of all eight editable fields and
**200** for a subsequent GET, both returning title `Issue 24 full update`, dates
`2026-11-03` through `2026-11-04`, budgets `200`–`800`, transportation `taxi`,
group `friends`, and tags `["food", "heritage"]`. Trip/owner UUIDs, `draft`
status, and null estimated cost remained unchanged. These saved values are the
baseline for invalid-update preservation checks.

The developer next supplied **422** for the one-sided PATCH
`{"budget_min":"801"}` against the saved maximum of `800`. The sanitized
response identified `loc: ["body"]`, type `value_error`, and message
`Value error, budget_max must be greater than or equal to budget_min.`
The following GET returned **200**, with all saved values matching the full-update
baseline: title `Issue 24 full update`, November 3–4 dates, budgets `200`–`800`,
taxi/friends, food/heritage tags, the same trip/owner UUIDs, draft status, and null
estimated cost. This confirms the rejected budget update did not change the row.
The remaining invalid-update cases have not yet been verified live.

The developer then supplied **422** for the one-sided PATCH
`{"end_date":"2026-11-02"}` against the saved start date `2026-11-03`.
The sanitized response identified `loc: ["body"]`, type `value_error`, and
message `Value error, end_date must be on or after start_date.` A subsequent
read to confirm preservation after this date rejection remains pending.

The developer supplied **422** for PATCH `{"budget_min":-1}`. The sanitized
response identified `loc: ["body", "budget_min"]`, type
`greater_than_equal`, and message `Input should be greater than or equal to 0`.
The developer also supplied **422** for PATCH `{"title":null}`, with
`loc: ["body", "title"]`, type `string_type`, and message
`Input should be a valid string`. Empty-body and server-owned-field live checks
remain pending.

The developer supplied **422** for PATCH `{}`, with `loc: ["body"]`, type
`value_error`, and message
`Value error, Supply at least one trip field to update.` The server-owned-field
live check remains pending.

The developer subsequently supplied **422** for PATCH
`{"user_id":"23000000-0000-4000-8000-000000000002"}`. The sanitized response
identified `loc: ["body", "user_id"]`, type `extra_forbidden`, and message
`Extra inputs are not permitted`. All six guided invalid-update requests have
now returned 422. A final GET after the date/negative/null/empty/owner attempts
was subsequently supplied by the developer: **200**, with every field matching
the full-update baseline, including the original owner UUID ending `0001`.
This confirms the six rejected updates did not corrupt the saved trip.

| Acceptance check | Safe evidence/result |
| --- | --- |
| New synthetic trip created, listed, retrieved | POST 201, GET by UUID 200, and GET list (limit 100, offset 0) 200 reported October 22 |
| PATCH title only; every omitted field retained | PATCH 200 and subsequent GET 200 reported October 22; title updated, all other fields retained |
| PATCH all eight editable fields; GET reflects saved values | PATCH 200 and subsequent GET 200 reported October 22; all eight values saved, IDs/status/estimated cost retained |
| Invalid one-sided date/budget edits rejected; saved row unchanged | Budget/date attempts returned 422; final GET 200 after all six rejected updates confirmed every field matched the full-update baseline |
| Invalid/null/empty/server-owned fields rejected | Negative budget, null title, empty update, and client-supplied owner each returned 422; final GET 200 confirmed all saved fields and ownership unchanged |
| Optional labels cleared with null; tags cleared with [] | PATCH 200 and subsequent list 200 confirmed transportation/group null, tags [], all other fields unchanged |
| Saved update survives refresh/backend restart; SQL confirms values | GET 200 after restart/refresh retained all saved updates; independent development SQL JSON matched every field |
| Existing other-owner trip rejects PATCH/DELETE and remains intact | PATCH and DELETE each returned 404; subsequent SQL confirmed fixture still exists with original owner and title `Other user fixture` |
| Nonexistent IDs return 404; unauthenticated mutations return 401 | Missing-trip PATCH/DELETE each returned 404; unauthenticated PATCH/DELETE each returned 401 |
| Owned trip has a confirmed itinerary child before DELETE | Development INSERT returned child `31778ade-f5a7-4c30-8c5b-ed884ae4d244`, linked to verification trip and Cathedral location |
| DELETE returns 204/no body; retrieve/repeat DELETE return 404; list excludes trip | Initial DELETE 204/no body; post-delete GET and repeated DELETE each 404; final GET list 200 excluded the deleted UUID and retained the original issue #23 trip |
| SQL confirms trip and child absent after DELETE | Developer confirmed exact expected counts: verification trip 0, all itinerary items for that trip 0 |
| Demo user, referenced location, and unrelated trip remain | Developer confirmed exact expected counts: demo user 1, Cathedral location 1, other-owner fixture 1, earlier issue #23 demo trip 1 |

The trip and child UUIDs, safe response excerpts, and SQL outcomes above record
the verification. Never include bearer tokens, keys, request headers, connection
strings, raw `.env` content, or Swagger Curl sections.

The developer supplied **200** for PATCH
`{"transportation_mode":null,"group_type":null,"preferred_tags":[]}` on the
development verification trip. The response showed both optional labels cleared
and tags empty, with title, dates, budgets, trip/owner UUIDs, draft status, and
null estimated cost unchanged. The subsequent GET list (`limit=100`, `offset=0`)
returned **200**, showing that saved cleared state for
`c5f56c50-aedb-4806-ba19-765914302527`. The list also retained the original issue
#23 trip `7c51b2e1-5111-408f-802a-981ce2da9761`, with its original `Bacolod
afternoon` details. Independent SQL and restart persistence remain pending.

The developer ran the guided SELECT in development Supabase and reported both
requested IDs were returned: `23000000-0000-4000-8000-000000000004` and
`c5f56c50-aedb-4806-ba19-765914302527`. This independently confirms both rows
exist in PostgreSQL. Only IDs were supplied; the SQL owner and saved-value
columns have not yet been confirmed, so this does not establish owner isolation
or independent SQL confirmation of the updated values.

The developer subsequently confirmed the SQL `user_id` for fixture
`23000000-0000-4000-8000-000000000004` is
`23000000-0000-4000-8000-000000000002`, different from the configured demo owner
ending `0001`. The fixture's existence and other-owner context are now confirmed;
The developer then supplied **404** with `{"detail":"Trip not found."}` for
PATCH of that fixture using `{"title":"Unauthorized update attempt"}` under
the configured demo owner. Other-owner PATCH rejection is verified as reported;
The developer subsequently supplied **404** with the same
`{"detail":"Trip not found."}` response for DELETE of that other-owner fixture.
Both mutation rejections are verified as reported. Independent SQL confirmation
that the fixture remains present with its original title and owner was requested.
The developer subsequently supplied SQL result ID
`23000000-0000-4000-8000-000000000004` and owner
`23000000-0000-4000-8000-000000000002`, confirming the fixture survived both
attempts with its owner unchanged. The developer then confirmed its title remains
`Other user fixture`, completing the reported SQL presence/owner/title
preservation checks after both rejected mutations.

The developer supplied **404** with `{"detail":"Trip not found."}` for PATCH
of missing-trip test UUID `24000000-0000-4000-8000-000000000099`, using valid
body `{"title":"Missing trip check"}`. The developer then supplied **404** with
the identical response for DELETE of the same UUID. Both missing-trip mutation
checks passed as reported. After Swagger logout, the developer supplied **401**
with `{"detail":"A valid trip demo bearer token is required."}` for PATCH of
the owned verification trip using
`{"title":"Unauthenticated update attempt"}`. While still logged out, DELETE
of the same owned trip also returned **401** with the identical safe response,
as supplied by the developer. Both unauthenticated mutation checks passed as
reported. After the guided backend restart in the same PowerShell session,
Swagger refresh, and reauthorization with the existing temporary token, the
developer supplied **200** for GET of the owned verification trip. Its title
remained `Issue 24 full update`, dates November 3–4, budgets `200`–`800`, both
optional labels null, tags empty, IDs unchanged, status draft, and estimated cost
null. This confirms saved updates survived the reported restart/refresh and the
unauthenticated attempts did not alter or delete the trip. `.env` remained
unchanged; direct SQL updated-value and itinerary cascade checks remain pending.

The developer then supplied the complete `saved_trip` JSON from the direct
development SQL SELECT. It matched every field from the post-restart GET:
trip/owner UUIDs, title `Issue 24 full update`, draft status, November 3–4 dates,
budgets 200–800, null transportation/group, empty tags, and null estimated cost.
This independently confirms the final updated values persisted in development
PostgreSQL. The itinerary fixture and actual API deletion/cascade checks remain
pending.

The developer ran the guided child INSERT once in development and supplied:

- Itinerary item ID: `31778ade-f5a7-4c30-8c5b-ed884ae4d244`.
- Trip ID: `c5f56c50-aedb-4806-ba19-765914302527`.
- Cathedral location ID: `1a3bca09-5532-5de6-8587-2440c4e5830d`.

The returned row confirms an actual child exists before deletion. This is an
intentional persistent development test fixture, not a migration. API DELETE
and independent SQL confirmation of the cascade remain pending.

The developer subsequently supplied **204** and confirmed an empty response body
for API DELETE of verification trip `c5f56c50-aedb-4806-ba19-765914302527`.
Independent SQL cascade/preservation checks and post-deletion API reads/repeated
DELETE remain pending; this HTTP result alone does not establish child removal.

The developer confirmed the post-deletion development SQL query returned exactly
the expected six values:

| SQL result | Count |
| --- | --- |
| `deleted_trip_rows` | 0 |
| `remaining_itinerary_rows` | 0 |
| `demo_user_rows` | 1 |
| `location_rows` | 1 |
| `other_owner_trip_rows` | 1 |
| `earlier_demo_trip_rows` | 1 |

This confirms the reported API deletion removed the trip and all its itinerary
children in actual development PostgreSQL, while preserving the demo user,
referenced location, other-owner fixture, and earlier issue #23 trip. Post-delete
API retrieve/repeated DELETE/list checks remain pending.

The developer subsequently supplied **404** with
`{"detail":"Trip not found."}` for GET of deleted trip
`c5f56c50-aedb-4806-ba19-765914302527`. Post-delete retrieval is verified as
reported; repeated DELETE and list exclusion remain pending.

The developer then supplied **404** with the same
`{"detail":"Trip not found."}` response when repeating DELETE of that deleted
UUID. Repeated-delete behavior is verified as reported; post-delete list exclusion
is the remaining guided development API check.

The final development GET list (`limit=100`, `offset=0`) returned **200**, with
only the original issue #23 trip `7c51b2e1-5111-408f-802a-981ce2da9761` and its
unchanged `Bacolod afternoon` details. Deleted verification trip
`c5f56c50-aedb-4806-ba19-765914302527` was absent. All guided development
acceptance checks in the table are complete as reported by the developer.
No production verification is claimed.

## Reviewed merge, CI, and deployment

- Implementation PR: [#41](https://github.com/relax-mode/lagaw/pull/41), supplied by the developer.
- Local feature commit: `27b3857` (`feat: implement trip update and delete endpoints`); local branch tracks `origin/feat/trip-update-delete`.
- Teammate review: developer confirmed approval.
- Required CI checks: developer confirmed all required checks passed.
- Merge: developer confirmed PR #41 merged; merge commit SHA not supplied.
- Successful backend deployment: developer confirmed Deploy Backend succeeded for that merge; run link not supplied.

The developer supplied PR #41 and said the preceding steps were complete.
This session could not fetch the GitHub PR page (cache miss). After being asked
explicitly about teammate approval, required CI, merge, and successful backend
deployment for that merge, the developer replied `all four confirmed`. These
release outcomes are recorded as developer-reported. Production verification
was performed separately below; a green deployment alone is not treated as
production acceptance evidence.

## Production — `zjnuqqtbapbpudsjbpif`

Development verification is complete. The developer confirmed reviewed merge,
passing CI, and successful backend deployment. Production CRUD and cascade
verification are also complete as reported, using a separate synthetic trip
and the production demo context. Results are listed below; production data was
kept separate from development data.

| Deployed acceptance check | Safe evidence/result |
| --- | --- |
| POST/list/retrieve new synthetic production trip | POST 201, GET by UUID 200, matching production SQL row, and pre-delete list 200 included trip `9070ee51-dde3-4526-9082-8f5d1c5bf4b0`; final list excluded it and retained the earlier production trip |
| Partial PATCH persisted; omitted fields retained | PATCH 200 changed only the title; subsequent GET 200 confirmed the saved title and retained fields |
| All editable fields saved; optional fields can be cleared | Production PATCH 200 and follow-up GET 200 confirmed all eight requested values; optional clearing verified in development |
| Invalid updates rejected; saved row unchanged | Production PATCH with budget_min 801 against saved maximum 800 returned 422; subsequent GET 200 confirmed all fields unchanged |
| Ownership/auth/missing-record behavior | Development: other-owner PATCH/DELETE 404 and fixture preserved; missing PATCH/DELETE 404; unauthenticated PATCH/DELETE 401. Production: deleted trip GET/repeated DELETE 404 |
| SQL confirms updated production row and child before DELETE | Full-update production JSON row matched GET; INSERT returned itinerary child `99519743-dd2d-4df8-a928-7cbeda838db9` for production trip |
| DELETE 204; retrieve/repeat DELETE 404; list excludes trip | Production DELETE 204; post-delete GET and repeated DELETE each 404; final list 200 excludes the verification trip |
| SQL confirms trip/child removed; user/location/unrelated trip preserved | Developer confirmed expected counts: trip 0, itinerary items 0, demo user 1, location 1, earlier production trip 1, development trip in production 0 |

The developer supplied **201** from the deployed POST endpoint for new
synthetic production verification trip `9070ee51-dde3-4526-9082-8f5d1c5bf4b0`,
owner `23000000-0000-4000-8000-000000000001`, with title
`Issue 24 production verification`, dates November 1–2, budgets `100`–`500.5`,
walking/solo, heritage/cafe tags, draft status, and null estimated cost. This
confirms the deployed demo authorization allowed creation. Production mutation,
saved retrieval, independent SQL, and cascade checks remain pending; the earlier
issue #23 production verification trip is not used for these mutations.

The developer supplied **200** for production PATCH of only
`{"title":"Issue 24 production updated"}` on trip
`9070ee51-dde3-4526-9082-8f5d1c5bf4b0`. The returned row contained the new title;
dates, budgets, transportation, group, tags, IDs/owner, draft status, and null
estimated cost matched the production create response. This verifies deployed
partial-update behavior. Follow-up GET persistence and production deletion/cascade
checks remain pending.

The developer subsequently supplied **200** for GET of the same production trip.
It returned title `Issue 24 production updated` and the same dates, budgets,
transportation, group, tags, IDs/owner, draft status, and null estimated cost as
the PATCH response. This confirms deployed retrieval after the update. Direct
production SQL, list, and deletion/cascade checks remain pending.

The developer supplied the complete production `saved_trip` JSON from the SQL
Editor. It matches the deployed GET exactly: trip/owner IDs, title `Issue 24
production updated`, draft status, November 1–2 dates, budgets 100–500.5, walking,
solo, heritage/cafe tags, and null estimated cost. This independently confirms
production database persistence of the API update. List, remaining production
update checks, and the actual cascade remain pending.

The developer supplied **200** for production GET list (`limit=100`, `offset=0`),
which contained the new `9070ee51-dde3-4526-9082-8f5d1c5bf4b0` trip with the saved
partial update and retained the earlier production
`9c45ad80-3762-4203-95ac-a97128fd68a2` `Production API verification` trip.
Production create/list/retrieve is now verified as reported. Full-field update,
remaining edge checks, and the actual production cascade remain pending.

The developer supplied **200** for a production PATCH with all eight editable
fields: title `Issue 24 production full update`, dates November 3–4, budgets
200–800, taxi, friends, and food/heritage tags. Trip and owner IDs, draft status,
and null estimated cost were retained. This verifies production writes for every
editable field. A subsequent production GET returned **200** with all eight
values saved by the PATCH and the same trip/owner IDs, draft status, and null
estimated cost. Follow-up production SQL confirmation and cascade/deletion
checks remain pending.

The developer supplied **422** for a production PATCH changing only
`budget_min` to `801` against the saved maximum `800`. The sanitized error
identified the budget-order validation failure. The subsequent GET returned
**200** and retained title `Issue 24 production full update`, dates November 3–4,
budgets 200–800, taxi/friends, food/heritage tags, trip/owner IDs, draft status,
and null estimated cost. This confirms the rejected update did not change the
API-visible row. Independent SQL confirmation of the final full-update values
was then supplied below.

The developer supplied the complete production `saved_trip` JSON after all eight
fields were updated. It matched GET, including production trip/owner IDs, title
`Issue 24 production full update`, draft status, dates November 3–4, budgets
200–800, taxi/friends, food/heritage tags, and null estimated cost. This confirms
independent SQL persistence of the final update. Production deletion/cascade
verification remains pending.

The developer ran the guided child INSERT in production and supplied itinerary
item `99519743-dd2d-4df8-a928-7cbeda838db9`, linked to verification trip
`9070ee51-dde3-4526-9082-8f5d1c5bf4b0` and Cathedral location
`1a3bca09-5532-5de6-8587-2440c4e5830d`. The returned row confirms an actual
production child exists before deletion. Production API DELETE and independent
SQL cascade/preservation checks remain pending.

The developer supplied **204** for production API DELETE of synthetic verification
trip `9070ee51-dde3-4526-9082-8f5d1c5bf4b0`, which had the confirmed itinerary
child above. Production post-delete SQL and API checks remain pending; the HTTP
response alone does not establish that the child cascade completed.

The developer confirmed the post-delete production SQL query returned exactly
the expected counts: deleted verification trip 0, its itinerary items 0, demo
user 1, Cathedral location 1, earlier production issue #23 trip 1, and the
development issue #24 trip in production 0. This confirms the production API
deletion removed the trip and its itinerary child while preserving related and
unrelated production records and maintaining environment separation.
Production post-delete API reads/list checks remain pending.

The developer subsequently supplied production GET **404** with
`{"detail":"Trip not found."}` for deleted UUID
`9070ee51-dde3-4526-9082-8f5d1c5bf4b0`. Post-delete retrieval is verified as
reported; repeated DELETE and production list exclusion remain pending.

The developer then supplied **404** with the same not-found response for a
second production DELETE of the already-deleted UUID. Repeated-delete behavior
is verified as reported.

The developer supplied the final production GET list with **200**. It contained
the earlier production trip `9c45ad80-3762-4203-95ac-a97128fd68a2`
(`Production API verification`) and did not contain the deleted verification
trip `9070ee51-dde3-4526-9082-8f5d1c5bf4b0`. Together with the production SQL
counts, DELETE 204, and post-delete GET/repeated DELETE 404 results above, this
completes the reported production CRUD and itinerary-cascade verification.

## Definition of Done

- [x] PR reviewed and merged into `main` (developer-confirmed PR #41).
- [x] Required CI pipeline passes (developer-confirmed).
- [x] All four CRUD operations verified through the development and deployed APIs/databases.
- [x] Persisted partial updates, invalid-update preservation, ownership, and
      actual development and production itinerary cascades verified.
- [ ] Publish this evidence and link it from issue #24.

The implementation and deployment conditions are complete. Publish this
evidence in a reviewed documentation PR and link it from issue #24 before
closing the issue.
