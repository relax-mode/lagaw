# Issue #53 verification evidence

Prepared October 28, 2026 for [#53](https://github.com/relax-mode/lagaw/issues/53),
on `feat/s3-08-trip-recommendations`, based on up-to-date main `bde91ce`.
Scope and reproducible commands: [API guide](../trip-recommendations-api.md).
Implementation: [PR #86](https://github.com/relax-mode/lagaw/pull/86),
code commit `9f7781a6579efa0a8045260ff124e2a45a2e4bea`.

| Check | Observed result |
| --- | --- |
| Full offline backend suite | 495 passed, 91 database tests deselected in 10.12 seconds, including strict numeric-score/coordinate boundary checks |
| Ruff | Passed |
| Week 3 evaluation | 27/27 extraction cases; 84/84 field checks; 10/10 content cases; no failures |
| Evaluation comparison | No regression; content Recall@3 0.75, NDCG@3 0.5898, HitRate@1 0.375; synthetic hybrid metrics remain 1.0 (not real-user quality evidence) |
| Development Supabase verification | Passed using the existing private app configuration, with target guard restricted to `vnpkyvtbupnquvirzlzp` |
| Development cleanup | Every generated interaction, item, trip, user and location removed; absence independently checked |
| Required PR CI | [Run 40674256269](https://github.com/relax-mode/lagaw/actions/runs/40674256269): Backend and Database succeeded; Flutter/deployment correctly skipped for this backend-only PR |
| Disposable PostgreSQL/PostgREST tests | 91 passed, zero failures/errors/skips, 3.947 seconds; new saved-trip recommendation persistence/owner test passed in 0.151 seconds |
| Independently downloaded JUnit | [trip-integration-results artifact 12809638076](https://github.com/relax-mode/lagaw/actions/runs/40674256269/artifacts/12809638076), XML parsed to confirm counts and the new test |
| CI evaluation artifact | [ai-evaluation artifact 12810021358](https://github.com/relax-mode/lagaw/actions/runs/40674256269/artifacts/12810021358); Backend job's evaluation and regression gate passed |
| Teammate review and merge | CyGray approved final head `d08c77c`; Andrew merged [PR #86](https://github.com/relax-mode/lagaw/pull/86) October 28, 2026 at 10:56:07 UTC as `38ff7e648bb2be639290cb47912ed61d40cf8487` |
| Main CI/deployment | [Run 40676016889](https://github.com/relax-mode/lagaw/actions/runs/40676016889): Backend, Database and Flutter passed; staging deployment/smoke checks and production API promotion/smoke checks passed; production web correctly skipped |
| Post-merge database artifact | Downloaded and parsed [JUnit artifact 12811365043](https://github.com/relax-mode/lagaw/actions/runs/40676016889/artifacts/12811365043): 91 tests, zero failures/errors/skips, 2.878 seconds; #53 persistence/owner test passed in 0.113 seconds |
| Staging route and unauthenticated access | New route present in deployed OpenAPI; POST without bearer returned 401 and correct `https://staging.lagaw.pages.dev` CORS permission |
| Deployed staging ranked response | Andrew supplied HTTP 200 for existing trip `abf9c3b7-02d2-48ec-880d-2418bcfc7819`, party size 2, three visits, limit 10: The Negros Museum `61bf94ab-6ec0-5ec3-8451-b575ee06169e`, score `0.6733327333273332`, matching heritage/photography reason, budget allocation 83.33–333.33, `empty_reason: null`; [request/response record](trip-recommendations-staging.json) |
| Independent staging database checks | Museum is active, matching tags and known PHP 100 upper cost; saved trip and its one itinerary item match the before snapshot exactly. Staging owner has zero persisted events, confirming cold start |
| Deployed staging restrictive filter | Andrew supplied HTTP 200 for the same saved trip/counts with `requires_step_free_access: true`: unchanged allocation 83.33–333.33, `items: []`, `empty_reason: no_compatible_locations`. Unknown accessibility facts fail closed without turning no-match into an error |
| Deployed staging invalid limit | Andrew supplied HTTP 422 for `limit: 0`, with only `loc: [body, limit]`, the lower-bound message and `type: greater_than_equal`; no submitted value or validator context exposed |
| Deployed staging missing trip | Andrew supplied HTTP 404 `Trip not found.` for the zero UUID with otherwise valid options |
| Staging completion and preservation | Ranked cold-start response, restrictive empty result, sanitized 422, missing-trip 404 and unauthenticated 401 passed. A final guarded database read after these checks confirms the original trip and its one itinerary item are unchanged |
| Deployed acceptance | Complete in staging/development first, then production; authenticated checks are recorded below, separately from pipeline smoke checks |
| Production public checks after staging acceptance | New recommendation route present in production OpenAPI; unauthenticated POST returned 401 with correct `https://lagaw.pages.dev` CORS. Public catalog contains the active Museum with known PHP 100 upper cost |
| Production authorization and trip baseline | Andrew supplied HTTP 200 for GET trips (`limit=100`, `offset=0`), returning two existing trips owned by the configured production demo owner. Selected `9c45ad80-3762-4203-95ac-a97128fd68a2`, saved solo/heritage/cafe preferences and total PHP 100–500.50; [baseline record](trip-recommendations-production.json). The other trip has null group and remains unchanged |
| Production itinerary baseline | Andrew supplied HTTP 200 for GET items of selected trip (`limit=100`, `offset=0`): empty `items`. Recorded before recommendation requests to check read-only preservation |
| Production ranked recommendations | Andrew supplied HTTP 200 for selected trip, party size 1, three visits and limit 10: Museum `61bf94ab-6ec0-5ec3-8451-b575ee06169e`, score `0.48011748486483247`, heritage/solo reason and correct PHP 33.33–166.83 allocation. The response validates against the HTTP schema, and every returned location field independently matches the public production catalog. [Request/response record](trip-recommendations-production.json) |
| Production restrictive filter | Andrew supplied HTTP 200 with `requires_step_free_access: true`, same trip/counts/allocation, `items: []` and `empty_reason: no_compatible_locations`; unavailable accessibility fails closed in production too |
| Production invalid limit | Andrew supplied HTTP 422 for `limit: 0`, exposing only `loc: [body, limit]`, lower-bound `msg` and `type: greater_than_equal`, matching the sanitized staging response |
| Production missing trip | Andrew supplied HTTP 404 `Trip not found.` for the zero UUID with valid options |
| Production final trip and itinerary preservation | Andrew supplied both final GETs with HTTP 200: the complete trip object exactly matches the recorded baseline and items remain empty (`limit=100`, `offset=0`). Parsed comparisons passed; no acceptance records were created or removed |

The initial development attempt failed before recommendation assertions because
the verifier's dependency override accidentally made FastAPI expect an extra model
body field. All fixtures were cleaned. Replaced that override with a zero-argument
factory; the actual endpoint required no corresponding fix. No production requests
or `.env` edits were made.

Successful development run's generated owner IDs:
`3fbf7ac2-c0a5-4878-84be-8ae750e39abd`, `b5bf36ef-4d05-46a8-8ce5-64c0f2143a99`.
Location IDs: `d99b6b4f-4160-46a8-9daf-e31896e52d5f`,
`e0cf0336-507e-4c46-aec9-d3af955e5876`.
Trip IDs: `fbc4674b-0c6e-4b6a-b5ef-4b1ead724265`,
`88938f3f-55c3-4f56-b809-0783c5486e3e`. These fixtures no longer exist.

Observed verifier results:

```text
PASS: Real saved manual trip/catalog rank with no model artifact or DeepSeek; other-owner rejection is isolated.
PASS: Persistence-backed owner isolation, auth, input validation and valid empty result.
PASS: Persisted rejection filters and malformed/failing model requests preserve trip and itinerary exactly.
PASS: Exact fixture cleanup and independent absence checks.
```

No schema, Flutter, scheduling, training or deployment configuration changes are
included. Production acceptance used the existing synthetic demo trip through
read-only requests; no production writes or cleanup were needed. Deployment
promoted the staging-tested image through the existing pipeline. The existing untracked
root `test-results/` directory is excluded from this work.

## Completion evidence

The PR body references #53, linking implementation, contract, checks and this
evidence to the assigned issue. Main requires one teammate approval and successful
required checks. Review, merge and deployments are linked above; authenticated
new-route acceptance is tracked separately from the existing pipeline smoke checks.

The deployment jobs for merge commit `38ff7e648bb2be639290cb47912ed61d40cf8487`
are [staging](https://github.com/relax-mode/lagaw/actions/runs/40676016889/job/122775228818)
and [production API](https://github.com/relax-mode/lagaw/actions/runs/40676016889/job/122775819821).
The pipeline promotes the same staging-tested image to production. Public OpenAPI
checks independently confirmed the new route in both environments.

Andrew executed authenticated Swagger requests privately and supplied the statuses
and response bodies in the linked JSON records. The agent independently validated
the response schemas, checked all location fields against development PostgreSQL
and the public production catalog, compared the supplied production final reads
with their baselines, and verified staging preservation directly in the guarded
development database. No direct production SQL verification is claimed.

Normal, fallback, filtering, malformed model output, unavailable artifact,
database failure and access cases passed automated tests, including persistence-
backed owner isolation. DeepSeek outage/manual-preference independence was tested
with a failing mocked provider; no paid provider call or live outage was introduced.
Unknown setting/accessibility facts and Haversine distance assumptions are documented
in the API guide. Automatic persistence/scheduling and Flutter display remain #54
and #56 respectively.

The implementation is reviewed, merged, CI-verified and deployed, and staging then
production acceptance passed. Final evidence is published through a documentation
PR; the requested issue comment links that record before issue closure. No private
`.env`, credentials, application code or database data changed during acceptance.
