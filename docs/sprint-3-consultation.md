# Sprint 3 Consultation Pack (November 1, 2026)

Prepared by CyGray for [#59](https://github.com/relax-mode/lagaw/issues/59). Re-check every item marked *pending* on October 31 and update this file with what actually happened. Never mark a check done ahead of time.

## 1. Live demo (4 min, from the deployed app)

### Before the session

- [ ] Confirm #68 and #73 are merged and the latest `main` run shows `Deploy - Production API` and `Deploy - Production web` green. Until then, production lacks the AI routes ([INC-3](incident-log.md#inc-3-production-drifted-behind-main)).
- [ ] 10 minutes before: wake both APIs (`curl -s <api>/locations?limit=1`). They scale to zero, and a cold start takes a few seconds.
- [ ] Open `https://lagaw.pages.dev` (production) and `https://staging.lagaw.pages.dev` (fallback) in separate tabs.
- [ ] Confirm the DeepSeek balance covers the demo. Holder: Kyle.

### Demo path

Steps 3 and 4 depend on #53, #54, #55 and #56; mark any that have not shipped as *not shipped* and explain why.

1. Type a request in the trip form, for example *"a cheap, relaxing afternoon with coffee and photography spots"*. Show the validated preference draft and that it requires confirmation (#55).
2. Show what the backend did with the output: schema validation, canonical tags, budget scope, missing fields, and no trip written until the user confirms (#50).
3. Get recommendations for the confirmed preferences (#53 → #56).
4. Generate and save the itinerary, then reload to show it persisted (#54 → #56).

### Failure handling

- **AI failure.** Point the app, or an API call, at the zero-traffic `aifail` staging revision (drill steps in [`PIPELINE.md`](../PIPELINE.md#ai-failure-drill)). Expect `503 extraction_unavailable` with `manual_fallback: true`, and the standard trip form in the app. Verified on staging October 26 ([evidence](evidence/ai-ci-cd-2026-10-26.md)).
- **Malformed request.**

  ```sh
  curl -s -X POST <api>/api/v1/preferences/extract \
    -H "Authorization: Bearer <demo token>" -H "Content-Type: application/json" -d '{"prompt": ""}'
  ```

  This returns 422 with a readable validation body. The provider is never called.

## 2. Board walkthrough (3 min)

Use the [Sprint 3 plan and status table](sprint-log.md#sprint-3-plan-and-status-recorded-october-26) and the [milestone](https://github.com/relax-mode/lagaw/milestone/3). Before presenting, refresh each row's status and the reason for any slip.

## 3. AI evidence

| Requirement | Evidence |
|---|---|
| Structured output processed by the backend | Extraction API (#50, PR [#64](https://github.com/relax-mode/lagaw/pull/64)), [preference extraction write-up](preference-extraction-api.md) |
| Small evaluation set | 12 success and 15 regression extraction fixtures, plus 10 recommendation cases ([evaluation suite](week3-evaluation.md), [results](evidence/week3-results.md), PR [#66](https://github.com/relax-mode/lagaw/pull/66)) |
| Mocked LLM tests in CI, no paid calls | Green run [40308275898](https://github.com/relax-mode/lagaw/actions/runs/40308275898) with no provider key in GitHub. Failure probes [40307281405](https://github.com/relax-mode/lagaw/actions/runs/40307281405) and [40308048372](https://github.com/relax-mode/lagaw/actions/runs/40308048372) ([AI CI/CD evidence](evidence/ai-ci-cd-2026-10-26.md)) |
| Evaluation reruns on prompt or AI changes | Backend job summary "AI evaluation versus baseline", compared with the target branch's baseline |
| AI error handling | Safe failure codes with `manual_fallback` ([regression fixtures](week3-evaluation.md)); staging failure drill |
| Recommendation quality | [Content-based results](evidence/content-based-results.md), [hybrid results](evidence/hybrid-results.md) |

## 4. DevOps report (3 min)

### What changed this sprint

1. **Path-filtered PR checks** (#31, PR [#68](https://github.com/relax-mode/lagaw/pull/68)).
   - Docs-only PRs: 83 s → **9 s**.
   - Backend-only PRs: 90 s → **54 s**.
   - The `psql` step: 8 s → 0 s.
2. **AI evaluation gate and network guard** (#58, PR [#73](https://github.com/relax-mode/lagaw/pull/73)). CI cannot call DeepSeek, and a quality drop fails even if the author refreshes the baseline.
3. **Automatic production promotion** (#58). Every qualifying merge goes staging → production with no manual step. This resolves the earlier manual-production policy and INC-3.
4. **Scheduled live checks**, twice a week: one real extraction through staging, plus the Cloudflare credential.
5. **Staging acceptance** (#30, PR [#67](https://github.com/relax-mode/lagaw/pull/67)). A browser write landed in the development database only.

### Metrics log

[Weekly metrics log](pipeline-metrics.md#weekly-metrics-log): fill the Sprint 3 row on October 31 with `python scripts/pipeline_metrics.py --since 2026-10-26 --until 2026-11-01`.

| Week | Avg PR time (min) | Main time (min) | Success rate (%) | Production deploys | Lead time (min) | Failed deploys | Time to recover (min) |
|---|---|---|---|---|---|---|---|
| Sprint 1 | 4.5 | 1.9 | 96.8 | 2 | 4.2 | 0 | n/a |
| Sprint 2 | 1.6 | 2.2 | 96.6 | 3 | 1.9 | 2 | 863.9 |
| Sprint 3, Oct 26 only (partial) | 1.5 | n/a | 100.0 | 0 | n/a | 0 | n/a |

The Sprint 3 partial row excludes 9 deliberate probe runs that proved the gates fail when they should. The final row replaces it.

### Incidents ([incident log](incident-log.md))

| ID | What | Postmortem |
|---|---|---|
| INC-1 | Staging Cloudflare credential rejected | Fixed by a token replacement; prevented by the scheduled credential check |
| INC-2 | A staging approval wait blocked `main` CI for about 53 h | Fixed by per-run concurrency and job timeouts |
| INC-3 | Production four days behind `main` under manual deploys | Fixed by automatic promotion; closes on the first promotion run |

### Next sprint (DevOps)

- A rollback workflow and a tested rollback drill.
- A tagged release with a changelog.
- A second optimization: the Flutter build time.
- Secret scanning and dependency audit.
- Per-environment Cloudflare tokens and deployer identities.

## 5. After the consultation

Record in the [sprint log](sprint-log.md), only after the session:

- Instructor feedback, as given.
- A retrospective: what went well, what did not, and one change for Sprint 4.
- Re-planned items, with reasons.
